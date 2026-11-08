// NOTE：Flutter 3.47+ 的 material_ui / cupertino_ui 解耦
// https://docs.flutter.dev/release/breaking-changes/material-ui-and-cupertino-ui

// 等待以下包或类似的替代品支持：
// markdown_widget
// silky_scroll
// window_manager
// mesh_gradient
// scrollable_positioned_list

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:system_fonts/system_fonts.dart';
import 'package:window_manager/window_manager.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:windows_taskbar/windows_taskbar.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'hot_keys.dart';
import 'theme/theme_provider.dart';
import 'layout/app_shell.dart';
import 'page/playlist/playlist_content_notifier.dart';
import 'services/notification_service.dart';
import 'services/update_check_service.dart';
import 'page/setting/settings_provider.dart';
import 'page/setting/setting_page.dart';
import 'src/rust/frb_generated.dart';
import 'package:flutter_single_instance/flutter_single_instance.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'page/statistics_page/statistics_manager.dart';
import 'layout/navigation_notifier.dart';
import 'services/license_service.dart';
import 'tv/tv_device.dart';
import 'tv/tv_focus.dart';
import 'tv/tv_focus_nav.dart';
import 'tv/tv_input_scope.dart';
import 'tv/tv_navigation.dart';
import 'tv/tv_settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AppLicenses.register();

  if (Platform.isAndroid) {
    // 先判定设备类型：TV 分支不启用沉浸式，也不使用手机端的应用内缩放。
    await TvDevice.initialize();
    if (!TvDevice.isTv) {
      // 隐藏系统状态栏与手势导航条；横屏媒体应用由手势从边缘唤出系统栏。
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  // ===== 以下为桌面端专属初始化，Android 上跳过 =====
  if (!Platform.isAndroid) {
    // 初始化全局快捷键管理器
    await hotKeyManager.unregisterAll();

    // 先初始化window_manager
    await windowManager.ensureInitialized();

    // 回调函数
    FlutterSingleInstance.onFocus =
        (Map<String, dynamic> metadata) async {
              // 先恢复窗口，再显示和聚焦
              await windowManager.restore();
              await windowManager.show();
              await windowManager.focus();
            }
            as FutureOr<void> Function(Map<String, dynamic>)?;

    // 单实例检测
    final singleInstance = FlutterSingleInstance();
    if (!await singleInstance.isFirstInstance()) {
      await singleInstance.focus();
      exit(0); // 退出第二个实例
    }
  }
  // ===== 桌面端专属初始化结束 =====

  PaintingBinding.instance.imageCache.maximumSize = 200;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 20 * 1024 * 1024;

  MpvAudioKit.ensureInitialized();

  await RustLib.init();

  // 初始化系统托盘（仅桌面）
  if (!Platform.isAndroid) {
    await trayManager.setIcon('assets/images/icon/tray_icon.ico');
    if (!Platform.isLinux) {
      await trayManager.setToolTip('MyuneMusic');
    }

    final Menu menu = Menu(
      items: [
        MenuItem(key: 'prev_song', label: '上一首'),
        MenuItem(key: 'play_pause', label: '播放/暂停'),
        MenuItem(key: 'next_song', label: '下一首'),
        MenuItem.separator(),
        MenuItem(key: 'show_window', label: '显示窗口'),
        MenuItem.separator(),
        MenuItem(key: 'exit_app', label: '退出'),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  // // 初始化window_manager
  // await windowManager.ensureInitialized();

  // 初始化窗口状态管理器（仅桌面）
  if (!Platform.isAndroid) {
    final windowState = WindowStateManager();
    final initialSize = await windowState.loadWindowSize();
    final initialPosition = await windowState.loadWindowPosition();

    const minPossibleSize = Size(480, 600);
    final windowOptions = WindowOptions(
      size: initialSize,
      minimumSize: minPossibleSize,
      center: true,
      title: "MyuneMusic",
      titleBarStyle: TitleBarStyle.hidden,
      // backgroundColor: Colors.transparent, // 让原生窗口背景透明
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      // 这一行会导致全屏的时候抖3次
      // await windowManager.setAsFrameless();

      if (!Platform.isLinux) {
        await windowManager.setHasShadow(true);
      }
      // 设置窗口位置
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey('window_x') && prefs.containsKey('window_y')) {
        await windowManager.setPosition(initialPosition);
      }
      await windowManager.show();
      await windowManager.focus();
    });

    //  添加监听器 保存窗口大小
    windowManager.addListener(windowState);
  }

  final themeProvider = ThemeProvider();
  await themeProvider.initialize();

  final statsManager = StatisticsManager();
  await statsManager.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider(create: (_) => NotificationService()),
        ChangeNotifierProvider(
          create: (context) => PlaylistContentNotifier(
            context.read<SettingsProvider>(),
            context.read<ThemeProvider>(),
            context.read<NotificationService>(),
          ),
        ),
        ChangeNotifierProvider<StatisticsManager>(
          create: (context) => StatisticsManager(),
        ),
        ChangeNotifierProvider(create: (_) => NavigationNotifier()),
        ChangeNotifierProvider(create: (_) => TvSettings()),
      ],
      child: const MyApp(),
    ),
  );

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
  };

  // 系统字体枚举仅桌面可用，Android 跳过（使用内置 MiSans）
  if (!Platform.isAndroid) {
    final systemFonts = SystemFonts();
    await themeProvider.loadCurrentFont(systemFonts);
  }
}

class _AndroidUiScaler extends StatelessWidget {
  const _AndroidUiScaler({required this.child, required this.scale});

  final Widget child;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 在更大的逻辑画布上布局，再整体视觉缩小。这样不需要修改系统 DPI，
        // 固定的桌面字号/尺寸也会按同一比例变小，且点击坐标随变换一起缩放。
        final effectiveScale = scale.clamp(0.55, 1.0);
        final virtualWidth = constraints.maxWidth / effectiveScale;
        final virtualHeight = constraints.maxHeight / effectiveScale;
        return SizedBox.expand(
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: virtualWidth,
              maxWidth: virtualWidth,
              minHeight: virtualHeight,
              maxHeight: virtualHeight,
              child: Transform.scale(
                scale: effectiveScale,
                alignment: Alignment.topLeft,
                transformHitTests: true,
                child: SizedBox(
                  width: virtualWidth,
                  height: virtualHeight,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with TrayListener, WidgetsBindingObserver {
  late PlaylistContentNotifier _playlistNotifier;
  SettingsProvider? _settingsProvider;
  StreamSubscription<Duration>? _taskbarPositionSubscription;
  StreamSubscription<bool>? _taskbarPlayingSubscription;
  StreamSubscription<bool>? _taskbarCompletedSubscription;
  bool _taskbarReady = false;
  bool _listenersBound = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addObserver(this);
    } else {
      trayManager.addListener(this);
    }

    // 确保窗口已经初始化
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (Platform.isWindows) {
        // 等待窗口完全准备就绪后再初始化任务栏功能
        await Future.delayed(const Duration(milliseconds: 100));
        _taskbarReady = true; // 标记任务栏功能已准备就绪
        _initializeThumbnailToolbar();
        _initializeTaskbarProgress();
      }
    });

    // 启动时自动检查更新（仅桌面，Android 无更新机制）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!Platform.isAndroid) _runStartupUpdateCheck();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (Platform.isAndroid &&
        !TvDevice.isTv &&
        state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  Future<void> _runStartupUpdateCheck() async {
    try {
      final settings = _settingsProvider ?? context.read<SettingsProvider>();
      // 等待设置读取完成，避免拿到默认值
      await settings.initializationFuture;
      if (!mounted || !settings.autoCheckUpdates) return;

      await UpdateCheckService.runSilentCheck(
        currentVersion: appVersion,
        notificationService: context.read<NotificationService>(),
      );
    } catch (e) {
      debugPrint('启动时自动检查更新出现错误: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextPlaylistNotifier = context.read<PlaylistContentNotifier>();
    final nextSettingsProvider = context.read<SettingsProvider>();

    if (_listenersBound) {
      if (identical(_playlistNotifier, nextPlaylistNotifier) &&
          identical(_settingsProvider, nextSettingsProvider)) {
        return;
      }

      if (Platform.isWindows) {
        _playlistNotifier.removeListener(_updateThumbnailToolbar);
      }
      _settingsProvider?.removeListener(_onSettingsChanged);
    }

    _playlistNotifier = nextPlaylistNotifier;
    _settingsProvider = nextSettingsProvider;

    if (Platform.isWindows) {
      _playlistNotifier.addListener(_updateThumbnailToolbar);
    }

    _settingsProvider?.addListener(_onSettingsChanged);
    _listenersBound = true;
  }

  void _onSettingsChanged() {
    try {
      final settings = _settingsProvider ?? context.read<SettingsProvider>();
      if (!settings.showTaskbarProgress) {
        // 当关闭任务栏进度显示时，立即重置进度条状态
        if (Platform.isWindows && _taskbarReady) {
          try {
            WindowsTaskbar.setProgressMode(TaskbarProgressMode.noProgress);
          } catch (_) {}
        }
      } else {
        // 当开启任务栏进度显示时，根据当前播放状态设置进度条模式
        if (Platform.isWindows && _taskbarReady) {
          try {
            if (_playlistNotifier.isPlaying) {
              WindowsTaskbar.setProgressMode(TaskbarProgressMode.normal);
            } else {
              WindowsTaskbar.setProgressMode(TaskbarProgressMode.paused);
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('_onSettingsChanged出现错误: $e');
    }
  }

  Future<void> _initializeThumbnailToolbar() async {
    if (!_taskbarReady) return;

    try {
      WindowsTaskbar.setWindowTitle('MyuneMusic');
      await WindowsTaskbar.setThumbnailToolbar([
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/images/icon/prev.ico'),
          '上一首',
          _playlistNotifier.playPrevious,
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/images/icon/play.ico'),
          '播放',
          _playlistNotifier.play,
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/images/icon/next.ico'),
          '下一首',
          _playlistNotifier.playNext,
        ),
      ]);

      // 初始化任务栏进度模式
      await WindowsTaskbar.setProgressMode(TaskbarProgressMode.normal);
    } catch (e) {
      debugPrint('_initializeThumbnailToolbar出现错误: $e');
    }
  }

  Future<void> _updateThumbnailToolbar() async {
    if (!_taskbarReady) return;

    try {
      final isPlaying = _playlistNotifier.isPlaying;

      await WindowsTaskbar.setThumbnailToolbar([
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/images/icon/prev.ico'),
          '上一首',
          _playlistNotifier.playPrevious,
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon(
            isPlaying
                ? 'assets/images/icon/pause.ico'
                : 'assets/images/icon/play.ico',
          ),
          isPlaying ? '暂停' : '播放',
          isPlaying ? _playlistNotifier.pause : _playlistNotifier.play,
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/images/icon/next.ico'),
          '下一首',
          _playlistNotifier.playNext,
        ),
      ]);
    } catch (e) {
      // debugPrint('_updateThumbnailToolbar出现错误: $e');
    }
  }

  Future<void> _initializeTaskbarProgress() async {
    final settings = _settingsProvider ?? context.read<SettingsProvider>();

    // 监听播放进度变化以更新任务栏进度
    _taskbarPositionSubscription = _playlistNotifier.mediaPlayer.stream.position
        .throttleTime(const Duration(milliseconds: 500))
        .listen((position) async {
          if (!_taskbarReady || !settings.showTaskbarProgress) return;

          final bool isVisible = await windowManager.isVisible();
          if (!isVisible) return;

          try {
            final duration = _playlistNotifier.totalDuration;
            if (duration != Duration.zero) {
              final progress =
                  (position.inMilliseconds / duration.inMilliseconds * 100)
                      .round();
              WindowsTaskbar.setProgress(progress.clamp(0, 100), 100);
            }
          } catch (_) {}
        });

    // 监听播放状态变化
    _taskbarPlayingSubscription = _playlistNotifier.mediaPlayer.stream.playing
        .listen((playing) async {
          if (!_taskbarReady || !settings.showTaskbarProgress) {
            // 当关闭任务栏进度显示时，重置进度条状态
            try {
              WindowsTaskbar.setProgressMode(TaskbarProgressMode.noProgress);
            } catch (_) {}
            return;
          }

          final bool isVisible = await windowManager.isVisible();
          if (!isVisible) return;

          try {
            WindowsTaskbar.setProgressMode(
              playing ? TaskbarProgressMode.normal : TaskbarProgressMode.paused,
            );
          } catch (_) {}
        });

    // 监听播放完成
    _taskbarCompletedSubscription = _playlistNotifier
        .mediaPlayer
        .stream
        .completed
        .listen((completed) async {
          if (!_taskbarReady || !settings.showTaskbarProgress) {
            // 当关闭任务栏进度显示时，重置进度条状态
            try {
              WindowsTaskbar.setProgressMode(TaskbarProgressMode.noProgress);
            } catch (_) {}
            return;
          }

          final bool isVisible = await windowManager.isVisible();
          if (!isVisible) return;

          if (completed) {
            try {
              WindowsTaskbar.setProgress(0, 100);
            } catch (_) {}
          }
        });
  }

  @override
  void dispose() {
    if (Platform.isAndroid) {
      WidgetsBinding.instance.removeObserver(this);
    } else {
      trayManager.removeListener(this);
    }
    _taskbarPositionSubscription?.cancel();
    _taskbarPlayingSubscription?.cancel();
    _taskbarCompletedSubscription?.cancel();
    if (_listenersBound) {
      if (Platform.isWindows) {
        _playlistNotifier.removeListener(_updateThumbnailToolbar);
      }
      _settingsProvider?.removeListener(_onSettingsChanged);
    }
    super.dispose();
  }

  @override
  void onTrayIconMouseDown() {
    // 点击托盘图标时显示窗口
    windowManager.show();
  }

  @override
  void onTrayIconRightMouseDown() {
    // 右键点击托盘图标时弹出菜单
    if (!Platform.isLinux) {
      trayManager.popUpContextMenu();
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_window') {
      windowManager.show();
    } else if (menuItem.key == 'exit_app') {
      windowManager.close();

      // exit是为了确保即使有后台任务，进程也能立即结束
      // 如果close已经让进程自毁了，这一行就不会执行
      exit(0);
    } else if (menuItem.key == 'prev_song') {
      _playlistNotifier.playPrevious();
    } else if (menuItem.key == 'play_pause') {
      _playlistNotifier.isPlaying
          ? _playlistNotifier.pause()
          : _playlistNotifier.play();
    } else if (menuItem.key == 'next_song') {
      _playlistNotifier.playNext();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        Widget app = MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh', 'CH'), Locale('en', 'US')],
          locale: const Locale('zh', 'CH'),

          debugShowCheckedModeBanner: false,
          title: '星音 StarNote',
          navigatorKey: tvRootNavigatorKey,
          navigatorObservers: <NavigatorObserver>[
            TvFocusNavigatorObserver(),
          ],
          // 焦点高亮完全沿用 Material / Android 原生样式，不再叠加 TV 专属主题。
          theme: themeProvider.lightThemeData,
          darkTheme: themeProvider.darkThemeData,
          themeMode: themeProvider.themeMode,
          builder: (context, materialAppChild) {
            // Android TV：不做手机端的 0.72 缩放，也不做过扫描留白；
            // 只挂统一输入层与焦点遍历策略，界面保持原样。
            if (Platform.isAndroid && TvDevice.isTv) {
              final tv = context.watch<TvSettings>();
              return TvInputScope(
                child: TvUiScaler(
                  scale: tv.uiScale,
                  child: materialAppChild!,
                ),
              );
            }
            // Android（手机）上去掉窗口拖拽缩放与全局快捷键，并做应用内整体缩放。
            if (Platform.isAndroid) {
              final uiScale = context
                  .watch<SettingsProvider>()
                  .androidUiScale;
              return _AndroidUiScaler(
                scale: uiScale,
                child: materialAppChild!,
              );
            }
            return DragToResizeArea(child: Hotkeys(child: materialAppChild!));
          },

          home: const AppShell(),
        );

        // 在 Windows 平台上排除语义化
        // https://github.com/flutter/flutter/issues/182444
        // TODO: 待修复
        if (Platform.isWindows) {
          app = ExcludeSemantics(child: app);
        }

        return app;
      },
    );
  }
}

// 管理窗口大小的加载与保存
class WindowStateManager with WindowListener {
  Future<Size> loadWindowSize() async {
    final prefs = await SharedPreferences.getInstance();
    final width = prefs.getDouble('window_width') ?? 1150;
    final height = prefs.getDouble('window_height') ?? 620;
    return Size(width, height);
  }

  Future<Offset> loadWindowPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getDouble('window_x') ?? 0;
    final y = prefs.getDouble('window_y') ?? 0;
    return Offset(x, y);
  }

  Timer? _resizeTimer;
  @override
  void onWindowResize() async {
    _resizeTimer?.cancel();
    _resizeTimer = Timer(const Duration(milliseconds: 300), () async {
      final size = await windowManager.getSize();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('window_width', size.width);
      await prefs.setDouble('window_height', size.height);
    });
  }

  Timer? _moveTimer;
  @override
  void onWindowMove() async {
    _moveTimer?.cancel();
    _moveTimer = Timer(const Duration(milliseconds: 300), () async {
      final position = await windowManager.getPosition();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('window_x', position.dx);
      await prefs.setDouble('window_y', position.dy);
    });
  }
}
