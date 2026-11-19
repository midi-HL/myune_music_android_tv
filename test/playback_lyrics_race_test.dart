import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:myune_music/lyrics/lyrics_handler.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late SettingsProvider settings;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'lyricSourceOrder': ['lrc']});
    settings = SettingsProvider();
    await settings.initializationFuture;
    directory = await Directory.systemTemp.createTemp('starnote_lyric_race');
    for (final name in ['A', 'B']) {
      await File(p.join(directory.path, '$name.lrc')).writeAsString('[00:00.00]$name');
    }
  });
  tearDown(() async { await directory.delete(recursive: true); });
  Song song(String name) => Song(title: name, artist: 'artist', filePath: p.join(directory.path, '$name.mp3'));
  Uint8List bytes(String text) => Uint8List.fromList(utf8.encode('[00:00.00]$text'));

  test('an old external-lyric read cannot overwrite the next song', () async {
    Song current = song('A');
    final readStarted = Completer<void>();
    final delayed = Completer<Uint8List>();
    final handler = LyricsHandler(settingsProvider: settings,
      notificationService: NotificationService(), notifyListeners: () {},
      getCurrentSong: () => current,
      readExternalBytes: (file) {
        if (p.basename(file.path) == 'A.lrc') { readStarted.complete(); return delayed.future; }
        return file.readAsBytes();
      });
    final first = handler.loadLyricsForSong(current.filePath);
    await readStarted.future;
    current = song('B');
    await handler.loadLyricsForSong(current.filePath);
    delayed.complete(bytes('A'));
    await first;
    expect(handler.currentLyrics.first.texts.first, 'B');
    handler.dispose();
  });
  test('a newer lyric request wins even for the same song path', () async {
    final current = song('A');
    final readStarted = Completer<void>();
    final delayed = Completer<Uint8List>();
    var reads = 0;
    final handler = LyricsHandler(settingsProvider: settings,
      notificationService: NotificationService(), notifyListeners: () {},
      getCurrentSong: () => current, readExternalBytes: (_) {
        if (reads++ == 0) { readStarted.complete(); return delayed.future; }
        return Future.value(bytes('new request'));
      });
    final first = handler.loadLyricsForSong(current.filePath);
    await readStarted.future;
    await handler.loadLyricsForSong(current.filePath);
    delayed.complete(bytes('old request'));
    await first;
    expect(handler.currentLyrics.first.texts.first, 'new request');
    handler.dispose();
  });
  test('disposal invalidates a pending external read', () async {
    final current = song('A');
    final started = Completer<void>();
    final delayed = Completer<Uint8List>();
    var notifications = 0;
    final handler = LyricsHandler(settingsProvider: settings,
      notificationService: NotificationService(), notifyListeners: () { notifications++; },
      getCurrentSong: () => current, readExternalBytes: (_) { started.complete(); return delayed.future; });
    final reading = handler.loadLyricsForSong(current.filePath);
    await started.future;
    handler.dispose();
    final before = notifications;
    delayed.complete(bytes('late'));
    await reading;
    expect(notifications, before);
    expect(handler.currentLyrics, isEmpty);
  });
}
