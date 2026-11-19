import 'dart:ui' show SemanticsAction, SemanticsFlag;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myune_music/layout/main_view.dart';
import 'package:myune_music/layout/navigation_notifier.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/page/song_detail_page.dart';
import 'package:myune_music/tv/tv_focus_nav.dart';
import 'package:myune_music/widgets/playbar.dart';
import 'package:myune_music/widgets/ui_scale_scope.dart';

class _PlayerStreams implements PlayerStream {
  @override
  Stream<Duration> get position => const Stream.empty();
  @override
  Stream<Duration> get duration => const Stream.empty();
  @override
  Stream<bool> get playing => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements Player {
  @override
  final PlayerState state = const PlayerState();
  @override
  final PlayerStream stream = _PlayerStreams();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Playback extends ChangeNotifier implements PlaylistContentNotifier {
  @override
  final Player mediaPlayer = _Player();
  @override
  Song get currentSong => Song(title: 'Layout song', artist: 'Artist', album: 'Album', filePath: '/song.mp3');
  @override
  bool get isPlaying => false;
  @override
  double get volume => 50;
  @override
  List<LyricLine> get currentLyrics => const [];
  @override
  Stream<int> get lyricLineIndexStream => const Stream.empty();
  @override
  int get currentLyricLineIndex => -1;
  @override
  List<Playlist> get playlists => const [];
  @override
  bool get isSearching => false;
  @override
  bool get isMultiSelectMode => false;
  @override
  bool get isWritingReplayGain => false;
  @override
  bool get isLoadingSongs => false;
  @override
  int get selectedIndex => -1;
  @override
  List<Song> get currentPlaylistSongs => const [];
  @override
  List<Song> get selectedSongs => const [];
  @override
  Set<String> get selectedSongPaths => const {};
  @override
  Duration get currentPosition => Duration.zero;
  @override
  Duration get totalDuration => const Duration(minutes: 4);
  @override
  PlayMode get playMode => PlayMode.sequence;
  @override
  Future<void> pause() async {}
  @override
  Future<void> play() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final physicalWidth in [1280.0, 920.0]) {
    testWidgets('fullscreen lyrics settings opens at ${physicalWidth.toInt()}px', (tester) async {
      const scale = 0.7;
      tester.view.physicalSize = Size(physicalWidth, 720);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'autoHidePlayPageComponents': false});
      final settings = SettingsProvider();
      await settings.initializationFuture;
      final playback = _Playback();
      addTearDown(settings.dispose);
      addTearDown(playback.dispose);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<PlaylistContentNotifier>.value(value: playback),
        ],
        child: MaterialApp(
          builder: (context, child) => TvFocusScope(
            child: LayoutBuilder(builder: (context, constraints) {
              final width = constraints.maxWidth / scale;
              final height = constraints.maxHeight / scale;
              return ClipRect(child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: width, maxWidth: width,
                minHeight: height, maxHeight: height,
                child: UiScaleScope(
                  visualScale: scale,
                  child: Transform.scale(
                    scale: scale, alignment: Alignment.topLeft,
                    child: SizedBox(width: width, height: height, child: child!),
                  ),
                ),
              ));
            }),
          ),
          home: const SongDetailPage(),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      final button = find.byTooltip('歌词显示设置');
      expect(button, findsOneWidget);
      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));
      expect(scaffold.isDrawerOpen, isFalse);
      if (physicalWidth == 1280) {
        expect(button.hitTestable(), findsOneWidget);
        await tester.tap(button);
      } else {
        // Enter the control row and navigate across the clipped viewport.
        // Each Right must scroll the newly focused button into reach.
        for (var step = 0; step < 8; step++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
        }
        expect(button.hitTestable(), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      }
      await tester.pumpAndSettle();
      expect(scaffold.isDrawerOpen, isTrue);
      expect(find.text('歌词选择'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final scale in [0.7, 1.0]) {
    testWidgets('640 logical width keeps every playback action visible at scale $scale', (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      await settings.initializationFuture;
      final playback = _Playback();
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<PlaylistContentNotifier>.value(value: playback),
        ],
        child: MaterialApp(home: Scaffold(body: LayoutBuilder(
          builder: (context, constraints) => OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: constraints.maxWidth / scale, maxWidth: constraints.maxWidth / scale,
            minHeight: constraints.maxHeight / scale, maxHeight: constraints.maxHeight / scale,
            child: Transform.scale(
              scale: scale, alignment: Alignment.topLeft,
              child: SizedBox(
                width: constraints.maxWidth / scale, height: constraints.maxHeight / scale,
                child: const Align(alignment: Alignment.bottomCenter, child: Playbar()),
              ),
            ),
          ),
        ))),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final label in ['打开播放页', '上一首', '播放', '下一首', '列表循环', '音量', '音效设置', '播放列表']) {
        final target = find.byTooltip(label);
        expect(target, findsOneWidget);
        expect(target.hitTestable(), findsOneWidget, reason: '$label can receive pointer/remote focus');
        final bounds = tester.getRect(target);
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(640.001));
        expect(bounds.top, greaterThanOrEqualTo(0));
        expect(bounds.bottom, lessThanOrEqualTo(360.001));
      }
      expect(find.semantics.byPredicate((node) {
        final data = node.getSemanticsData();
        return data.tooltip == '播放列表' && data.hasFlag(SemanticsFlag.isButton);
      }), findsOneWidget);
      final cover = find.bySemanticsLabel('打开播放页');
      expect(cover, findsOneWidget);
      final coverData = tester.getSemantics(cover).getSemanticsData();
      expect(coverData.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(coverData.hasAction(SemanticsAction.tap), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
      settings.dispose();
      playback.dispose();
    });
  }

  testWidgets('sidebar and page semantics survive the nested Navigator', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.initializationFuture;
    final playback = _Playback();
    final navigation = NavigationNotifier();
    final semantics = tester.ensureSemantics();
    addTearDown(settings.dispose);
    addTearDown(playback.dispose);
    addTearDown(navigation.dispose);
    addTearDown(semantics.dispose);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<PlaylistContentNotifier>.value(value: playback),
        ChangeNotifierProvider<NavigationNotifier>.value(value: navigation),
      ],
      child: const MaterialApp(home: MainView()),
    ));
    await tester.pumpAndSettle();
    final first = find.bySemanticsLabel('歌单');
    expect(first, findsOneWidget);
    expect(find.bySemanticsLabel('设置'), findsOneWidget);
    expect(find.bySemanticsLabel('请选择一个歌单'), findsOneWidget);
    final firstData = tester.getSemantics(first).getSemanticsData();
    expect(firstData.hasFlag(SemanticsFlag.isFocused), isTrue);
    expect(firstData.hasFlag(SemanticsFlag.isSelected), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('icon-only Android rail exports labelled focused button semantics', (tester) async {
    final node = FocusNode();
    var selected = 0;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(
      width: 80, child: AndroidRailButton(
        entry: PageEntry(
          visible: (_, __) => true, label: '设置', routeName: '/settings',
          icon: Icons.settings_outlined, selectedIcon: Icons.settings,
          page: const SizedBox.shrink(),
        ),
        selected: true, showLabel: false, focusNode: node,
        onSelect: () => selected++,
      ),
    ))));
    node.requestFocus();
    await tester.pumpAndSettle();
    final target = find.bySemanticsLabel('设置');
    expect(target, findsOneWidget);
    final data = tester.getSemantics(target).getSemanticsData();
    expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(data.hasFlag(SemanticsFlag.isFocused), isTrue);
    expect(data.hasFlag(SemanticsFlag.isSelected), isTrue);
    await tester.tap(target);
    expect(selected, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
    node.dispose();
  });
}
