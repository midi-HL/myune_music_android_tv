import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/lyrics/lyrics_handler.dart';
import 'package:myune_music/lyrics/lyric_source.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/services/android_content_resolver.dart';
import 'package:myune_music/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('myune_music_android/saf');
  const uri = 'content://com.android.externalstorage.documents/'
      'tree/volume%3AMusic/document/volume%3AMusic%2FAlbum%2FAudit_A.flac';
  const opaqueUri = 'content://music.test/tree/root/document/opaque-id';
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('SAF path fallback displays only the final decoded file name', () {
    expect(AndroidContentResolver.displayName(uri, null), 'Audit_A.flac');
  });

  test('SAF metadata uses the provider name for opaque document IDs', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getDisplayName');
      expect(call.arguments, {'uri': opaqueUri});
      calls++;
      return '真正的曲名.flac';
    });
    expect(await AndroidContentResolver.loadDisplayName(opaqueUri), '真正的曲名.flac');
    expect(AndroidContentResolver.displayName(opaqueUri, null), '真正的曲名.flac');
    expect(await AndroidContentResolver.loadDisplayName(opaqueUri), '真正的曲名.flac');
    expect(calls, 1);
  });

  test('SAF external lyrics use the document channel and the local LRC parser', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readSidecarLyrics');
      expect(call.arguments, {'uri': uri, 'extension': 'lrc'});
      return Uint8List.fromList(utf8.encode('[00:00.00]A_ONLY'));
    });
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.initializationFuture;
    final song = Song(title: 'Audit A', artist: 'Audit', filePath: uri);
    final handler = LyricsHandler(settingsProvider: settings,
      notificationService: NotificationService(), notifyListeners: () {},
      getCurrentSong: () => song);
    addTearDown(handler.dispose);
    await handler.selectLyricSource(LyricSource.externalLrc);
    expect(handler.currentLyrics.first.texts.first, 'A_ONLY');
  });
}
