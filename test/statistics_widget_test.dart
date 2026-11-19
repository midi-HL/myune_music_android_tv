import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/playlist/song_cover_store.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/page/statistics_page/statistics.dart';
import 'package:myune_music/page/statistics_page/statistics_manager.dart';
import 'package:myune_music/page/statistics_page/statistics_models.dart';

// Statistics rendering needs the library and cover store, not a native player.
class _LibraryOnlyNotifier extends ChangeNotifier implements PlaylistContentNotifier {
  @override
  final List<Song> allSongs = [];
  @override
  final SongCoverStore coverStore = SongCoverStore();
  @override
  String coverCacheKey(String filePath) => filePath;
  @override
  Uint8List? coverOfCacheKey(String key) => null;
  @override
  void releaseSongCover(String key) {}
  @override
  void requestSongCover(String key) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('rankings update from statistics events without a playback rebuild', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.initializationFuture;
    final library = _LibraryOnlyNotifier();
    final data = StatisticsManager().statisticsData;
    data.clearStats();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<PlaylistContentNotifier>.value(value: library),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ],
      child: const MaterialApp(home: Scaffold(body: Statistics())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Live count song'), findsNothing);
    final stat = SongPlayStat(
      title: 'Live count song', artist: 'Live artist', album: 'Live album', path: '/count.mp3',
    );
    data.recordSongPlayed(stat);
    await tester.pumpAndSettle();
    expect(find.text('Live count song'), findsOneWidget);
    expect(find.text('1 次'), findsWidgets);
    data.recordSongPlayed(stat);
    await tester.pumpAndSettle();
    expect(find.text('2 次'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    data.clearStats();
    library.coverStore.dispose();
    library.dispose();
    settings.dispose();
  });
}
