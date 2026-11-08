import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../page/pages/play_list.dart';
import '../page/pages/setting.dart';
import '../page/pages/song_details.dart';
import '../page/pages/all_songs.dart';
import '../page/pages/album_list_page.dart';
import '../page/pages/artist_list_page.dart';
import '../page/pages/statistics_page.dart';
import '../page/pages/audio_analysis_page.dart';

import '../page/playlist/playlist_content_notifier.dart';
import '../page/setting/settings_provider.dart';
import '../widgets/custom_background_layer.dart';
import '../tv/tv_device.dart';
import '../tv/tv_focus_nav.dart';
import 'navigation_notifier.dart';

class PageEntry {
  final bool Function(String label, Set<String> hiddenPages) visible; // 是否显示
  final String label;
  final String routeName;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;

  PageEntry({
    required this.visible,
    required this.label,
    required this.routeName,
    required this.icon,
    required this.selectedIcon,
    required this.page,
  });
}

class MainView extends StatefulWidget {
  const MainView({super.key});

  @override
  State<MainView> createState() => _MainViewState();
}

class _MainViewState extends State<MainView> {
  final int _tappedIndex = -1;

  late final List<PageEntry> _entries;

  final TextStyle _mainViewTextStyle = const TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
  );

  @override
  void initState() {
    super.initState();

    _entries = [
      PageEntry(
        visible: (label, hiddenPages) => true, // 歌单始终显示
        label: '歌单',
        routeName: '/playlist',
        icon: Icons.playlist_play,
        selectedIcon: Icons.playlist_play_outlined,
        page: const Playlist(),
      ),
      PageEntry(
        visible: (label, hiddenPages) => !hiddenPages.contains(label),
        label: '全部歌曲',
        routeName: '/all_songs',
        icon: Icons.queue_music,
        selectedIcon: Icons.queue_music_outlined,
        page: const AllSongs(),
      ),
      PageEntry(
        visible: (label, hiddenPages) => !hiddenPages.contains(label),
        label: '歌手',
        routeName: '/artists',
        icon: Icons.person_outlined,
        selectedIcon: Icons.person,
        page: const ArtistListPage(),
      ),
      PageEntry(
        visible: (label, hiddenPages) => !hiddenPages.contains(label),
        label: '专辑',
        routeName: '/albums',
        icon: Icons.album_outlined,
        selectedIcon: Icons.album,
        page: const AlbumListPage(),
      ),
      PageEntry(
        visible: (label, hiddenPages) => !hiddenPages.contains(label),
        label: '统计',
        routeName: '/statistics',
        icon: Icons.leaderboard_outlined,
        selectedIcon: Icons.leaderboard,
        page: const StatisticsPage(),
      ),
      PageEntry(
        visible: (label, hiddenPages) => !hiddenPages.contains(label),
        label: '歌曲详情信息',
        routeName: '/song_details',
        icon: Icons.library_music_outlined,
        selectedIcon: Icons.library_music,
        page: const SongDetails(),
      ),
      PageEntry(
        visible: (label, hiddenPages) => !hiddenPages.contains(label),
        label: '音频分析',
        routeName: '/audio_analysis',
        icon: Icons.graphic_eq_outlined,
        selectedIcon: Icons.graphic_eq,
        page: const AudioAnalysisPage(),
      ),
      PageEntry(
        visible: (label, hiddenPages) => true, // 设置始终显示
        label: '设置',
        routeName: '/settings',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        page: const Setting(),
      ),
    ];
  }

  NavigationRailDestination _buildDest(
    PageEntry entry,
    int index,
    int currentIndex,
  ) {
    return NavigationRailDestination(
      icon: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedScale(
          scale: _tappedIndex == index ? 1.1 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          child: Tooltip(
            message: entry.label,
            child: Icon(
              entry.icon,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
      selectedIcon: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedScale(
          scale: currentIndex == index ? 1.1 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          child: Icon(
            entry.selectedIcon,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      label: Text(entry.label, style: _mainViewTextStyle),
    );
  }

  // 非 TV 沿用 NavigationRail；TV 上换成每项都有显式 Focus 节点的侧边栏，
  // 第一项 autofocus，保证冷启动时方向键有起点。
  Widget _buildRail({
    required List<PageEntry> entries,
    required int currentIndex,
    required ValueChanged<int> onSelect,
    required Color railColor,
  }) {
    if (!TvDevice.isTv) {
      return SafeArea(
        child: NavigationRail(
          backgroundColor: railColor,
          selectedIndex: currentIndex,
          onDestinationSelected: onSelect,
          destinations: <NavigationRailDestination>[
            for (int i = 0; i < entries.length; i++)
              _buildDest(entries[i], i, currentIndex),
          ],
        ),
      );
    }

    return SafeArea(
      child: Container(
        width: 116,
        color: railColor,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (int i = 0; i < entries.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 4,
                ),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    // 鼠标 / 触控与遥控器 OK 走同一个 onSelect，方便真机排查。
                    onTap: () => onSelect(i),
                    child: TvFocusable(
                      autofocus: i == 0,
                      debugLabel: 'tv-rail-${entries[i].routeName}',
                      onActivate: () => onSelect(i),
                      child: _TvRailItem(
                        entry: entries[i],
                        selected: i == currentIndex,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playlistNotifier = context.read<PlaylistContentNotifier>();
    final settings = context.watch<SettingsProvider>();
    final navigationNotifier = context.watch<NavigationNotifier>();
    final hiddenPages = settings.hiddenPages.toSet();

    final visibleEntries = _entries
        .where((e) => e.visible(e.label, hiddenPages))
        .toList();

    int currentIndex = visibleEntries.indexWhere(
      (e) => e.routeName == navigationNotifier.currentRoute,
    );
    if (currentIndex == -1) {
      currentIndex = 0;
    }

    void selectDestination(int index) {
      switch (visibleEntries[index].page) {
        case Playlist _:
          playlistNotifier.clearActiveDetailView();
          break;
        case AllSongs _:
          playlistNotifier.setActiveAllSongsView();
          break;
        case SongDetails _:
          playlistNotifier.clearViewingSong();
          break;
      }
      if (currentIndex != index) {
        navigationNotifier.navigateTo(visibleEntries[index].routeName);
      }
    }

    final railColor = CustomBackgroundSurfaces.railColor(
      settings,
      Theme.of(context).colorScheme.surfaceContainerHighest,
    );

    Widget buildNavigator(bool instant) {
      return Navigator(
        key: navigationNotifier.navigatorKey,
        onGenerateRoute: (routeSettings) {
          final entry = visibleEntries.firstWhere(
            (e) => e.routeName == routeSettings.name,
            orElse: () => visibleEntries.first,
          );
          return PageRouteBuilder(
            pageBuilder: (context, _, __) => entry.page,
            transitionDuration: instant
                ? Duration.zero
                : const Duration(milliseconds: 150),
            reverseTransitionDuration: instant
                ? Duration.zero
                : const Duration(milliseconds: 150),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              if (instant) return child;
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOut,
                reverseCurve: Curves.easeInOut,
              );
              return FadeTransition(opacity: curved, child: child);
            },
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 横屏宽屏时把歌曲详情固定成右栏，形成 master-detail。
        // 窄屏仍走原来的单 Navigator，不叠加第三层列表。
        final isWideLandscape =
            constraints.maxWidth >= 1100 &&
            MediaQuery.of(context).orientation == Orientation.landscape;
        if (isWideLandscape) {
          return Row(
            children: [
              _buildRail(
                entries: visibleEntries,
                currentIndex: currentIndex,
                onSelect: selectDestination,
                railColor: railColor,
              ),
              Expanded(flex: 3, child: buildNavigator(true)),
              const VerticalDivider(width: 1),
              const SizedBox(width: 420, child: SongDetails()),
            ],
          );
        }
        return Row(
          children: [
            _buildRail(
              entries: visibleEntries,
              currentIndex: currentIndex,
              onSelect: selectDestination,
              railColor: railColor,
            ),
            Expanded(
              child: visibleEntries.isNotEmpty
                  ? buildNavigator(false)
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }
}

class _TvRailItem extends StatelessWidget {
  const _TvRailItem({required this.entry, required this.selected});

  final PageEntry entry;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: selected
            ? scheme.primary.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(selected ? entry.selectedIcon : entry.icon, size: 21, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              entry.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
