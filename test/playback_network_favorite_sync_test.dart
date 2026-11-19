import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myune_music/page/playlist/network_favorite_sync.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/services/network/network_library.dart';
import 'package:myune_music/services/network/remote_media_registry.dart';
import 'package:myune_music/page/playlist/playback_queue_logic.dart';

String media(String kind, String path, {String title = 'title'}) {
  final data = {'k': kind, 's': 'source', 'p': path, 't': title,
    'id': kind == 'gd' ? 'gd:$path' : 'nas:source:$path'};
  return 'http://127.0.0.1:18765/starnote/${base64Url.encode(utf8.encode(jsonEncode(data)))}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('playing cursor survives proxy-port and metadata URL changes', () {
    final stored = media('nas', '/one.mp3');
    final playing = media('nas', '/one.mp3', title: 'new title')
        .replaceFirst(':18765/', ':18766/');
    expect(reconcilePlayingIndex([stored, media('nas', '/two.mp3')], playing, 0,
      identityOf: RemoteMediaRegistry.identityOf), 0);
  });
  test('default playlist edits synchronize drive stars by stable identity only', () async {
    SharedPreferences.setMockInitialValues({});
    final nas = media('nas', '/one.mp3');
    final drive = media('gd', 'file-id');
    final updatedNas = media('nas', '/one.mp3', title: 'updated metadata');
    final favorite = Playlist(name: '收藏', isDefault: true, songFilePaths: [nas]);
    final store = NetworkLibraryStore.instance;
    await syncNetworkDriveFavorites(favorite);
    expect(store.isFavorite(nas), isTrue);
    favorite.songFilePaths = [updatedNas, drive];
    await syncNetworkDriveFavorites(favorite);
    expect(store.favorites.length, 2);
    expect(store.isFavorite(nas), isTrue);
    expect(store.isFavorite(drive), isTrue);
    await syncNetworkDriveFavorites(Playlist(name: 'ordinary'));
    expect(store.favorites.length, 2);
    favorite.songFilePaths = ['bilibili:BV1:1', '/local.mp3'];
    await syncNetworkDriveFavorites(favorite);
    expect(store.isFavorite(nas), isFalse);
    expect(store.isFavorite(drive), isFalse);
    expect(store.favorites, isEmpty);
    expect(favorite.songFilePaths, ['bilibili:BV1:1', '/local.mp3']);
  });
}
