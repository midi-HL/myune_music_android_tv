import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/services/network/bili_library.dart';
import 'package:myune_music/services/network/network_library.dart';
import 'package:myune_music/services/network/remote_media_registry.dart';
import 'package:myune_music/services/network/remote_stream.dart';
import 'package:myune_music/services/network/remote_source.dart';
import 'package:myune_music/services/network/remote_entry.dart';
import 'package:myune_music/services/network/network_media_service.dart';
import 'package:myune_music/page/network/tv_network_widgets.dart';

String proxyUrl(Map<String, dynamic> target, {int port = 18765}) =>
    'http://127.0.0.1:$port/starnote/'
    '${base64Url.encode(utf8.encode(jsonEncode(target))).replaceAll('=', '')}';

Song biliSong({String title = 'old', String mode = 'audio', int port = 18765}) =>
    Song(title: title, artist: 'artist', album: 'album', filePath: proxyUrl({
      'k': 'bili', 'b': 'BV1234567890', 'c': 123,
      'id': 'bilibili:BV1234567890:123:$mode', 'm': mode, 't': title,
    }, port: port));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('normal directory click excludes hidden video and enqueue selects one row', () {
    const first = RemoteEntry(name: 'first.flac', path: '/first.flac', isDirectory: false);
    const selected = RemoteEntry(name: 'second.mp3', path: '/second.mp3', isDirectory: false);
    const video = RemoteEntry(name: 'hidden.mp4', path: '/hidden.mp4', isDirectory: false);
    const folder = RemoteEntry(name: 'folder', path: '/folder', isDirectory: true);
    final entries = [first, video, folder, selected];
    final play = NetworkMediaService.directoryPlayback(entries, selected, enqueue: false);
    expect(play.entries, [first, selected]);
    expect(play.index, 1);
    final queue = NetworkMediaService.directoryPlayback(entries, selected, enqueue: true);
    expect(queue.entries, [selected]);
    expect(queue.index, 0);
    expect(NetworkMediaService.directoryPlayback(entries, video, enqueue: false).index, -1);
  });

  test('ignored Range is clamped to the actual resource length', () async {
    final info = describeHttpRange(
      contentRange: null, contentLength: 100,
      requestedStart: 0, requestedEnd: 2097151,
    );
    expect(info.servedStart, 0);
    expect(info.servedEnd, 99);
    expect(info.limit, 100);
    final bytes = await limitByteStream(
      Stream.value(List<int>.generate(100, (i) => i)), info.limit,
    ).expand((chunk) => chunk).toList();
    expect(bytes.length, info.servedEnd! - info.servedStart + 1);
  });

  test('ignored nonzero Range preserves zero start for proxy byte skipping', () {
    final info = describeHttpRange(
      contentRange: null, contentLength: 100,
      requestedStart: 70, requestedEnd: 150,
    );
    expect(info.servedStart, 0);
    expect(info.servedEnd, 99);
    expect(info.limit, 100);
  });

  test('valid upstream 206 retains its original byte interval', () {
    final info = describeHttpRange(
      contentRange: 'bytes 70-99/100', contentLength: 30,
      requestedStart: 70, requestedEnd: 150, upstreamPartial: true,
    );
    expect(info.totalLength, 100);
    expect(info.servedStart, 70);
    expect(info.servedEnd, 99);
    expect(info.limit, 30);
  });

  test('media identity ignores proxy port, title, artwork and Bili mode', () {
    expect(RemoteMediaRegistry.identityOf(biliSong().filePath),
        RemoteMediaRegistry.identityOf(
          biliSong(title: 'new', mode: 'video', port: 18766).filePath,
        ));
    expect(RemoteMediaRegistry.identityOf('bilibili:BV1234567890:123:audio'),
        RemoteMediaRegistry.identityOf(biliSong().filePath));
    final nas = {'k': 'nas', 's': 'source1', 'p': '/music/file.flac'};
    expect(RemoteMediaRegistry.identityOf(proxyUrl({...nas, 't': 'old'})),
        RemoteMediaRegistry.identityOf(proxyUrl({...nas, 't': 'new'}, port: 18766)));
    expect(RemoteMediaRegistry.identityOf(proxyUrl(nas)),
        isNot(RemoteMediaRegistry.identityOf(proxyUrl({...nas, 's': 'source2'}))));
  });

  test('Bili legacy duplicates collapse and changing mode can cancel favorite', () async {
    final old = biliSong();
    final current = biliSong(title: 'new', mode: 'video', port: 18766);
    SharedPreferences.setMockInitialValues({
      'starnote.bilibili.favorites.v1': [
        jsonEncode(old.toJson()), jsonEncode(current.toJson()),
      ],
      'starnote.bilibili.history.v1': [
        jsonEncode(old.toJson()), jsonEncode(current.toJson()),
      ],
    });
    final store = BiliLibraryStore.instance;
    await store.load();
    expect(store.favorites.length, 1);
    expect(store.history.length, 1);
    expect(store.isFavorite(current.filePath), isTrue);
    expect(await store.toggleFavorite(current), isFalse);
    expect(store.favorites, isEmpty);
    await store.addFavorites([old, current]);
    expect(store.favorites.length, 1);
    await store.removeFavorite(current.filePath);
    expect(store.favorites, isEmpty);
    await store.recordPlay(current);
    expect(store.history.length, 1);
    expect(store.history.single.title, 'new');
  });

  test('network-drive favorites use source and path rather than display metadata', () async {
    final target = {'k': 'nas', 's': 'drive', 'p': '/song.flac', 'id': 'nas:drive:1'};
    final old = Song(title: 'old', artist: '', album: '', filePath: proxyUrl(target));
    final current = Song(title: 'new', artist: '', album: '',
        filePath: proxyUrl({...target, 't': 'new'}, port: 18766));
    final store = NetworkLibraryStore.instance;
    await store.addAll([old, current]);
    expect(store.favorites.length, 1);
    expect(store.isFavorite(current.filePath), isTrue);
    expect(await store.toggle(current), isFalse);
    expect(store.favorites, isEmpty);
  });

  testWidgets('editing a Google Drive source preserves its authorization', (tester) async {
    const original = RemoteSource(id: 'gd-test', name: 'Drive',
      type: RemoteSourceType.googleDrive, host: '', port: 443, rootPath: '',
      clientId: 'CLIENT', clientSecret: 'SECRET', refreshToken: 'REFRESH',
      rootFolderId: 'ROOT');
    RemoteSource? saved;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => TextButton(onPressed: () async {
        saved = await showTvSourceEditor(context: context, existing: original);
      }, child: const Text('edit')),
    ))));
    await tester.tap(find.text('edit'));
    await tester.pumpAndSettle();
    expect(find.text('服务器地址'), findsNothing);
    expect(find.text('根文件夹 ID'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved?.id, original.id);
    expect(saved?.type, RemoteSourceType.googleDrive);
    expect(saved?.host, isEmpty);
    expect(saved?.clientId, original.clientId);
    expect(saved?.clientSecret, original.clientSecret);
    expect(saved?.refreshToken, original.refreshToken);
    expect(saved?.rootFolderId, original.rootFolderId);
  });
}
