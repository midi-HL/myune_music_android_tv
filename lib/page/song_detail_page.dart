// 音频可视化:https://pub.dev/packages/sonix

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mesh_gradient/mesh_gradient.dart';
import 'package:colorgram/colorgram.dart';

import '../widgets/lyrics_widget.dart';
import 'playlist/playlist_content_notifier.dart';
import '../widgets/song_detail_page/playbar.dart';
import '../widgets/song_detail_page/app_window_title_bar.dart';
import './setting/settings_provider.dart';
import '../widgets/playing_queue_drawer.dart';
import '../widgets/lyrics_settings_drawer.dart';
import '../tv/tv_focus_nav.dart';
import '../services/network/remote_media_registry.dart';
import '../widgets/ui_scale_scope.dart';
import 'playlist/playlist_models.dart';

/// 播放控制栏（横屏 Playbar / 竖屏 PortraitPlaybar）内的可聚焦控件。
bool _inPlaybar(BuildContext context) =>
    context.findAncestorWidgetOfExactType<Playbar>() != null ||
    context.findAncestorWidgetOfExactType<PortraitPlaybar>() != null;

/// 播放页方向键：控制栏只有一行按钮，上方没有任何可聚焦内容。
/// 全局几何导航在 UP 找不到候选时会把焦点交还框架，触发恢复 / 守卫连锁，
/// 真机与 MuMu 均复现「整页无高亮、后续方向键全部失效」。
/// 用页面级 Shortcuts/Actions 就近接管，行为完全确定，不依赖逻辑键名匹配。
class _PlayPageArrowIntent extends Intent {
  const _PlayPageArrowIntent(this.direction);

  final TraversalDirection direction;
}

class _PlayPageArrowAction extends Action<_PlayPageArrowIntent> {
  @override
  Object? invoke(_PlayPageArrowIntent intent) {
    final focus = FocusManager.instance.primaryFocus;
    final context = focus?.context;
    final inBar = context != null && context.mounted && _inPlaybar(context);
    if (!inBar) {
      // 播放队列抽屉 / 歌词设置抽屉等浮层打开时，交回全局几何导航。
      return KeyEventResult.ignored;
    }
    // 左右只在控制栏按钮行内移动；上下保持不动，永不离开这一行。
    TvFocusController.instance.stepWithinScopedRow(intent.direction, _inPlaybar);
    return KeyEventResult.handled;
  }
}

// 公共模糊背景组件
class BackgroundBlurWidget extends StatefulWidget {
  final Widget child;
  const BackgroundBlurWidget({super.key, required this.child});

  @override
  State<BackgroundBlurWidget> createState() => _BackgroundBlurWidgetState();
}

class _BackgroundBlurWidgetState extends State<BackgroundBlurWidget>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  List<Color>? _extractedColors;
  String? _lastSongFilePath;
  bool _isProcessingColor = false;

  // 初始网格位置
  static const List<Offset> _gridPositions = [
    Offset(0.15, 0.2),
    Offset(0.85, 0.15),
    Offset(0.2, 0.85),
    Offset(0.8, 0.8),
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    );

    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _checkAndUpdateColors(Song? song, bool isDarkTheme) {
    if (song == null || song.albumArt == null) {
      if (_extractedColors != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _extractedColors = null);
        });
      }
      return;
    }

    if (song.filePath == _lastSongFilePath || _isProcessingColor) return;

    _lastSongFilePath = song.filePath;
    _isProcessingColor = true;

    _extractColorsAsync(song, isDarkTheme);
  }

  Future<void> _extractColorsAsync(Song song, bool isDarkTheme) async {
    try {
      final ImageProvider imageProvider = MemoryImage(song.albumArt!);
      final List<CgColor> cgColors = await extractColor(imageProvider, 6);

      if (!mounted || song.filePath != _lastSongFilePath) return;

      final List<Color> adjustedColors = cgColors.map((cg) {
        final rawColor = Color.fromARGB(255, cg.r, cg.g, cg.b);
        final hsl = HSLColor.fromColor(rawColor);

        double newLightness;
        double newSaturation;

        if (isDarkTheme) {
          newLightness = hsl.lightness.clamp(0.08, 0.18);
          newSaturation = hsl.saturation.clamp(0.18, 0.35);
        } else {
          newLightness = hsl.lightness.clamp(0.35, 0.55);
          newSaturation = hsl.saturation.clamp(0.18, 0.38);
        }

        return hsl
            .withLightness(newLightness)
            .withSaturation(newSaturation)
            .toColor();
      }).toList();

      while (adjustedColors.length < 4) {
        adjustedColors.add(
          adjustedColors.isNotEmpty ? adjustedColors.first : Colors.blueGrey,
        );
      }

      if (mounted) {
        setState(() {
          _extractedColors = adjustedColors.sublist(0, 4);
        });
      }
    } catch (e) {
      //
    } finally {
      _isProcessingColor = false;
    }
  }

  List<MeshGradientPoint> _getMeshPoints(bool isDarkTheme) {
    final List<Color> baseColors =
        _extractedColors ??
        (isDarkTheme
            ? const [
                Color(0xFF0B0B0F),
                Color(0xFF08090D),
                Color(0xFF0A0B10),
                Color(0xFF0D0A12),
              ]
            : const [
                Color(0xFFD6D0D2),
                Color(0xFFD0D5D8),
                Color(0xFFD5D8DC),
                Color(0xFFD8D1D6),
              ]);

    return List.generate(_gridPositions.length, (i) {
      return MeshGradientPoint(
        position: _gridPositions[i],
        // 浅色模式下不稀释颜色
        color: baseColors[i].withValues(alpha: isDarkTheme ? 0.28 : 1.0),
      );
    });
  }

  void _manageAnimation(bool shouldAnimate) {
    if (shouldAnimate) {
      if (!_animationController.isAnimating) {
        _animationController.repeat(reverse: true); // 重复播放，反向播放
      }
    } else {
      if (_animationController.isAnimating) {
        _animationController.stop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final useBlurBackground = settings.useBlurBackground;
    final enableDynamicBackground = settings.enableDynamicBackground;

    // 动画开关逻辑，通过延迟到帧后来避免 build 期间的副作用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _manageAnimation(enableDynamicBackground && useBlurBackground);
      }
    });

    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    return Consumer<PlaylistContentNotifier>(
      builder: (context, playlistNotifier, child) {
        final currentSong = playlistNotifier.currentSong;

        _checkAndUpdateColors(currentSong, isDarkTheme);
        // 当没有封面图或用户未启用模糊背景时，使用纯色背景
        if (currentSong?.albumArt == null || !useBlurBackground) {
          return Container(
            color: Theme.of(context).colorScheme.surface,
            child: child,
          );
        }

        if (enableDynamicBackground) {
          final basePoints = _getMeshPoints(isDarkTheme);

          return Stack(
            fit: StackFit.expand,
            children: [
              AnimatedBuilder(
                animation: _animation,
                builder: (context, _) {
                  final List<MeshGradientPoint> animatedPoints = [];
                  const double amplitude = 0.35;
                  final double time = _animation.value * 2 * math.pi;

                  for (int i = 0; i < basePoints.length; i++) {
                    final point = basePoints[i];
                    double offsetX = 0.0;
                    double offsetY = 0.0;

                    if (i == 0) {
                      offsetX = amplitude * math.sin(time);
                      offsetY = amplitude * math.cos(time * 1.2);
                    } else if (i == 1) {
                      offsetX = amplitude * math.cos(time * 0.9);
                      offsetY = amplitude * math.sin(time * 1.1);
                    } else if (i == 2) {
                      offsetX = amplitude * math.sin(time * 1.3);
                      offsetY = amplitude * math.sin(time * 0.8);
                    } else {
                      offsetX = amplitude * math.cos(time * 1.1);
                      offsetY = amplitude * math.cos(time * 1.4);
                    }

                    animatedPoints.add(
                      MeshGradientPoint(
                        position: Offset(
                          (point.position.dx + offsetX).clamp(0.0, 1.0),
                          (point.position.dy + offsetY).clamp(0.0, 1.0),
                        ),
                        color: point.color,
                      ),
                    );
                  }

                  return MeshGradient(
                    points: animatedPoints,
                    options: MeshGradientOptions(
                      blend: 4.0,
                      noiseIntensity: 0.1,
                    ),
                  );
                },
              ),
              Container(
                color: Theme.of(context).colorScheme.surface.withValues(
                  alpha: isDarkTheme ? 0.4 : 0.6,
                ),
              ),
              if (child != null) child,
            ],
          );
        }

        // 静态高斯模糊背景：只在封面变化时绘制一次，不参与逐帧重绘。
        // 用户确认这类一次性模糊在弱电视上不卡，质感需要保留；要避免的是
        // 把原本不模糊的地方改成实时 / 逐帧高斯模糊。
        // sigma 按 1/visualScale 补偿，使视觉模糊半径与桌面端一致
        // （桌面端 visualScale=1.0，行为不变）。
        final double visual = UiScaleScope.of(context).clamp(0.5, 1.5);
        return Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: 40 / visual,
                sigmaY: 40 / visual,
                tileMode: TileMode.decal,
              ),
              child: Image.memory(
                currentSong!.albumArt!,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                errorBuilder: (context, error, stackTrace) =>
                    Container(color: Theme.of(context).colorScheme.surface),
              ),
            ),
            IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(
                        context,
                      ).colorScheme.surface.withValues(alpha: 0.8),
                      Theme.of(
                        context,
                      ).colorScheme.surface.withValues(alpha: 0.8),
                    ],
                  ),
                ),
              ),
            ),
            if (child != null) child,
          ],
        );
      },
      child: widget.child,
    );
  }
}

class SongDetailPage extends StatefulWidget {
  const SongDetailPage({super.key});

  @override
  State<SongDetailPage> createState() => _SongDetailPageState();
}

class _SongDetailPageState extends State<SongDetailPage> {
  bool _isHidden = false;
  Timer? _hideTimer;
  bool _lastSettingValue = false;
  bool _autoHideEnabled = false;

  // 网络媒体（B 站 / 网盘）封面按需下载后的回填缓存。Song 本身只带封面 URL，
  // albumArt 为空，播放页原先只显示音符占位；这里补上自动获取与方形缩放。
  Uint8List? _networkArtwork;
  String? _artworkSongPath;
  String? _artworkLoadingPath;

  // 缓存 tear-off，保证 add/remove 用的是同一个回调对象。
  late final bool Function(KeyEvent) _keyHandler = _onHardwareKey;

  @override
  void initState() {
    super.initState();
    // 原版只靠 Listener/MouseRegion 监听鼠标移动来唤醒隐藏的控件栏。电视
    // 盒子 / 遥控器 / 纯键盘没有 pointer move，隐藏后就再也唤不回来。这里
    // 只「观察」硬件按键（返回 false 不拦截），让任何方向键 / 确认键 / 媒体键
    // 都能先恢复控件栏，且不影响 TvInputScope 的几何导航与Flutter默认按键处理。
    HardwareKeyboard.instance.addHandler(_keyHandler);
    // 播放页自己声明「焦点该回到哪里」：任何时候焦点落空，都优先拉回控制栏，
    // 不让全局恢复逻辑跳到底层迷你播放条或保活旧页面。
    TvFocusController.instance.registerRestoreHandler(() {
      final ok = TvFocusController.instance.focusFirstWhere(_inPlaybar);
      if (!ok) {
        // 控件栏正在隐藏 / 刚唤醒还没 rebuild：下一帧再试，绝不让全局
        // _pickLeaf 把焦点扔到底层迷你播放条或旧页面。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            TvFocusController.instance.focusFirstWhere(_inPlaybar);
          }
        });
      }
      return true; // 本页负责恢复，不再走全局兜底
    });

    // 播放页是独立全屏 route，打开时若不主动指定焦点，Flutter 会把初始焦点
    // 交给第一个可聚焦控件 —— 实测是右侧歌词行（TextButton）。歌词行每行都
    // 可聚焦，于是 DOWN 在歌词间跳、LEFT/RIGHT 找不到候选就整页丢失焦点，
    // OK 还会误触发保活旧页面的收藏按钮。这里把焦点明确落到播放控制栏。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // 同步生效，避免被焦点调度队列的防抖吞掉。
        final ok = TvFocusController.instance.focusFirstWhere(_inPlaybar);
        if (!ok) {
          TvFocusController.instance.scheduleFocusWhere(_inPlaybar);
        }
      });
    });
  }

  /// 网络媒体封面：优先用 Song 已带的 albumArt；否则按代理 URL 里的封面地址
  /// 异步下载并回填。失败 / 无封面时保持占位，不阻断播放。
  void _ensureArtwork(Song? song) {
    if (song == null) return;
    final embedded = song.albumArt;
    if (embedded != null && embedded.isNotEmpty) return;
    final path = song.filePath;
    if (!RemoteMediaRegistry.isNetwork(path)) return;
    if (_artworkSongPath == path && _networkArtwork != null) return;
    if (_artworkLoadingPath == path) return;
    _artworkLoadingPath = path;
    unawaited(() async {
      final bytes = await RemoteMediaRegistry.artworkFor(path);
      if (!mounted) return;
      if (bytes != null && bytes.isNotEmpty) {
        setState(() {
          _networkArtwork = bytes;
          _artworkSongPath = path;
        });
      }
      _artworkLoadingPath = null;
    }());
  }

  /// 方向键由页面内的 [_PlayPageDirectionalAction] 通过
  /// TvDirectionalFocusIntent 直接接管（不依赖按逻辑键名匹配，避免某些遥控器
  /// / 手柄 / 模拟器把 UP 映射成不同 logicalKey 时漏接）。
  /// 这里只负责「任意按键唤醒控件栏」与「焦点无效时兜底」，始终不吞键。
  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    _handleUserInteraction(_autoHideEnabled);
    final focus = FocusManager.instance.primaryFocus;
    if (!TvFocusController.isValidFocus(focus)) {
      final context = focus?.context;
      // 抽屉 / 对话框里的有效焦点不打扰；只有焦点真的落空才拉回控制栏。
      if (context == null || !context.mounted || !_inPlaybar(context)) {
        TvFocusController.instance.restoreFocusNow();
      }
    }
    return false;
  }

  void _startTimer() {
    _cancelTimer();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _isHidden = true;
        });
      }
    });
  }

  void _cancelTimer() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _handleUserInteraction(bool autoHideEnabled) {
    if (!autoHideEnabled) return;
    _cancelTimer();
    if (_isHidden) {
      setState(() {
        _isHidden = false;
      });
      // 控件栏隐藏时按钮会退出语义树、焦点随之落空。唤醒后立刻同步把焦点
      // 放回控制栏，保证「按任意键 → 控件栏出现 → 方向键可继续操作」连贯，
      // 不会出现整页无高亮或 OK 误触旧页面按钮。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) TvFocusController.instance.focusFirstWhere(_inPlaybar);
      });
    }
    _startTimer();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_keyHandler);
    TvFocusController.instance.registerRestoreHandler(null);
    _cancelTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    // 恢复上游原版行为：所有平台一致，播放页无操作 5 秒后隐藏标题栏与
    // 播放控件栏，仅保留封面与歌词，提升视听体验。
    // 移植时一度加过 `&& !TvDevice.isTv` 门控把它关掉；现在遥控器 / 键盘
    // 已能通过 HardwareKeyboard 监听随时唤醒，隐藏不再导致控件不可达。
    final autoHideEnabled = settings.autoHidePlayPageComponents;
    _autoHideEnabled = autoHideEnabled;

    // 监听设置变化
    if (autoHideEnabled != _lastSettingValue) {
      _lastSettingValue = autoHideEnabled;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (autoHideEnabled) {
          _startTimer();
        } else {
          _cancelTimer();
          if (mounted && _isHidden) {
            setState(() {
              _isHidden = false;
            });
          }
        }
      });
    }

    // 获取窗口宽高比
    final size = MediaQuery.of(context).size;
    final aspectRatio = size.aspectRatio;
    final isPortrait = aspectRatio <= 1.0; // 竖屏判断

    // 计算窗口分辨率缩放系数：与桌面端同基准（1150x620）按面积平滑缩放，
    // 并反向补偿 Android/TV 全局 UI 缩放对固定尺寸的二次缩小。这样在任意
    // 分辨率、任意「界面缩放」设置下，封面 / 标题 / 歌词 / 控件栏的视觉大小
    // 都与桌面端一致，不会再出现整体偏小、控件栏过细的问题。
    final double scale = playPageScale(context);

    // Android/TV 全局视觉缩放系数。桌面端没有 UiScaleScope 节点，返回 1.0，
    // 因此下面所有归一运算在桌面端都是恒等变换，行为完全不变。
    final double visual = UiScaleScope.of(context).clamp(0.5, 1.5);

    // Android 系统「字体大小」会通过 MediaQuery.textScaler 二次放大所有文字；
    // 桌面端没有这一层。播放页的字号由应用内「歌词显示设置」精确控制，
    // 这里把系统缩放压制到 1.0 上限（调小仍保留），避免电视端整体偏大。
    // 这是「让同一个设置值在两端视觉一致」，而不是改小任何设置默认值。
    final double systemTextScale =
        MediaQuery.textScalerOf(context).scale(16) / 16.0;

    // 播放页方向键就近接管：Shortcuts 必须放在 Actions 之下（同 TvFocusScope
    // 的结构），控件栏内方向键完全由 _PlayPageArrowAction 处理；抽屉 / 浮层
    // 里返回 ignored，事件继续冒泡到全局 TvDirectionalFocusAction。
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(systemTextScale.clamp(0.8, 1.0)),
      ),
      child: Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowUp):
            _PlayPageArrowIntent(TraversalDirection.up),
        SingleActivator(LogicalKeyboardKey.arrowDown):
            _PlayPageArrowIntent(TraversalDirection.down),
        SingleActivator(LogicalKeyboardKey.arrowLeft):
            _PlayPageArrowIntent(TraversalDirection.left),
        SingleActivator(LogicalKeyboardKey.arrowRight):
            _PlayPageArrowIntent(TraversalDirection.right),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _PlayPageArrowIntent: _PlayPageArrowAction(),
        },
        child: Listener(
      onPointerDown: (_) => _handleUserInteraction(autoHideEnabled),
      onPointerMove: (_) => _handleUserInteraction(autoHideEnabled),
      onPointerHover: (_) => _handleUserInteraction(autoHideEnabled),
      onPointerSignal: (_) => _handleUserInteraction(autoHideEnabled),
      child: MouseRegion(
        cursor: _isHidden ? SystemMouseCursors.none : MouseCursor.defer,
        onHover: (_) => _handleUserInteraction(autoHideEnabled),
        child: Scaffold(
          endDrawer: const PlayingQueueDrawer(),
          body: BackgroundBlurWidget(
            child: Column(
              children: [
                // 标题栏
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: _isHidden ? 0.0 : 1.0,
                  child: IgnorePointer(
                    ignoring: _isHidden,
                    child: Builder(
                      builder: (BuildContext context) {
                        return AppWindowTitleBar(
                          onSettingsPressed: () {
                            Scaffold.of(context).openDrawer();
                            TvFocusController.instance
                                .scheduleFocusInDrawer();
                          },
                        );
                      },
                    ),
                  ),
                ),
                // 主内容区域
                Expanded(
                  child: isPortrait
                      ? // 竖屏：显示歌词和底部播放控制
                        Column(
                          children: [
                            // 歌词区域
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.all(20 * scale),
                                child: Center(
                                  child: Builder(
                                    builder: (context) {
                                      final playlistNotifier = context
                                          .watch<PlaylistContentNotifier>();
                                      final currentLyrics =
                                          playlistNotifier.currentLyrics;
                                      if (currentLyrics.isEmpty) {
                                        return const Center(
                                          child: Text(
                                            '无歌词数据',
                                            style: TextStyle(
                                              fontSize: 20,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        );
                                      }
                                      return StreamBuilder<int>(
                                        stream: playlistNotifier
                                            .lyricLineIndexStream,
                                        initialData: playlistNotifier
                                            .currentLyricLineIndex,
                                        builder: (context, snapshot) {
                                          // 歌词行是 TextButton，原本每行都能拿焦点。
                                          // 遥控器会把初始焦点落在歌词上、按左右又丢焦点；
                                          // 这里让歌词退出 D-pad 焦点链（鼠标 / 触摸点击
                                          // seek 不受影响），焦点只落在播放控件上。
                                          return ExcludeFocus(
                                            child: LyricsView(
                                              maxLinesPerLyric: context
                                                  .watch<SettingsProvider>()
                                                  .maxLinesPerLyric,
                                              onTapLine: (index) {
                                                playlistNotifier
                                                    .seekToLyricLine(index);
                                              },
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                            // 底部播放控制栏
                            AnimatedOpacity(
                              duration: const Duration(milliseconds: 300),
                              opacity: _isHidden ? 0.0 : 1.0,
                              child: IgnorePointer(
                                ignoring: _isHidden,
                                child: const PortraitPlaybar(),
                              ),
                            ),
                          ],
                        )
                      : // 横屏：保留原有布局
                        Row(
                          children: [
                            SizedBox(width: 80 * scale),
                            // 左侧歌曲信息和播放控制区域
                            Expanded(
                              flex: 2,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  top: 10 * scale,
                                  bottom: 55 * scale,
                                ),
                                child: Center(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // 歌曲信息
                                      Consumer<PlaylistContentNotifier>(
                                        builder: (context, playlistNotifier, child) {
                                          final currentSong =
                                              playlistNotifier.currentSong;
                                          // B 站 / 网盘歌曲只带封面 URL，这里按需下载回填。
                                          _ensureArtwork(currentSong);
                                          final embedded = currentSong?.albumArt;
                                          final Uint8List? coverArt =
                                              (embedded != null &&
                                                      embedded.isNotEmpty)
                                                  ? embedded
                                                  : (_artworkSongPath ==
                                                          currentSong?.filePath
                                                      ? _networkArtwork
                                                      : null);
                                          return LayoutBuilder(
                                            builder: (context, constraints) {
                                              final w = constraints.maxWidth;
                                              // 基于窗口分辨率缩放系数计算封面大小，同时不超过父容器宽度
                                              final double baseImageSize =
                                                  310.0 * scale;
                                              final double imageSize = math.min(
                                                w,
                                                baseImageSize,
                                              );

                                              // 歌曲名 / 作曲家：这是最重要的视觉对齐项。
                                              // 桌面端 1150x620 基准下 imageSize=310，
                                              // (310*0.05).clamp(20,32)=20、(310*0.03).clamp(14,28)=14，
                                              // 实际都落在 clamp 下限 20 / 14。
                                              // 电视端不再用 imageSize 联动（1080p 上封面被放大后
                                              // 会把字号顶到 26~32，正是「名字太大」的根因），
                                              // 改为固定桌面基准 20 / 14「视觉像素」，再按
                                              // 1/visualScale 转成逻辑像素，视觉恒定与电脑端一致。
                                              // 桌面端 visualScale=1.0，等价于上游原版。
                                              final double titleFontSize =
                                                  20.0 / visual;
                                              final double artistFontSize =
                                                  14.0 / visual;

                                              final borderRadius =
                                                  BorderRadius.circular(12);
                                              const Widget fallback = Icon(
                                                Icons.music_note,
                                                size: 72,
                                                color: Colors.black12,
                                              );

                                              return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  SizedBox(
                                                    width: imageSize,
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .stretch,
                                                      children: [
                                                        SizedBox(
                                                          height: 45 * scale,
                                                        ),
                                                        // 歌曲标题
                                                        AnimatedAlign(
                                                          duration:
                                                              const Duration(
                                                                milliseconds:
                                                                    500,
                                                              ),
                                                          curve:
                                                              Curves.easeInOut,
                                                          alignment: _isHidden
                                                              ? Alignment
                                                                    .centerLeft
                                                              : Alignment
                                                                    .center,
                                                          child: AnimatedPadding(
                                                            duration:
                                                                const Duration(
                                                                  milliseconds:
                                                                      500,
                                                                ),
                                                            curve: Curves
                                                                .easeInOut,
                                                            padding:
                                                                EdgeInsets.only(
                                                                  left:
                                                                      _isHidden
                                                                      ? 2.0 *
                                                                            scale
                                                                      : 0.0,
                                                                ),
                                                            child: Text(
                                                              currentSong
                                                                      ?.title ??
                                                                  '未知歌曲',
                                                              style: TextStyle(
                                                                fontSize:
                                                                    titleFontSize,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                              textAlign:
                                                                  _isHidden
                                                                  ? TextAlign
                                                                        .left
                                                                  : TextAlign
                                                                        .center,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              maxLines: 1,
                                                              softWrap: false,
                                                            ),
                                                          ),
                                                        ),
                                                        // 艺术家
                                                        AnimatedAlign(
                                                          duration:
                                                              const Duration(
                                                                milliseconds:
                                                                    500,
                                                              ),
                                                          curve:
                                                              Curves.easeInOut,
                                                          alignment: _isHidden
                                                              ? Alignment
                                                                    .centerLeft
                                                              : Alignment
                                                                    .center,
                                                          child: AnimatedPadding(
                                                            duration:
                                                                const Duration(
                                                                  milliseconds:
                                                                      500,
                                                                ),
                                                            curve: Curves
                                                                .easeInOut,
                                                            padding:
                                                                EdgeInsets.only(
                                                                  left:
                                                                      _isHidden
                                                                      ? 2.0 *
                                                                            scale
                                                                      : 0.0,
                                                                ),
                                                            child: Text(
                                                              currentSong !=
                                                                      null
                                                                  ? context
                                                                            .watch<
                                                                              SettingsProvider
                                                                            >()
                                                                            .showAlbumName
                                                                        ? '${currentSong.artist} - ${currentSong.album}'
                                                                        : currentSong
                                                                              .artist
                                                                  : '未知歌手',
                                                              style: TextStyle(
                                                                fontSize:
                                                                    artistFontSize,
                                                                color:
                                                                    Theme.of(
                                                                          context,
                                                                        )
                                                                        .colorScheme
                                                                        .onSurface
                                                                        .withValues(
                                                                          alpha:
                                                                              0.7,
                                                                        ),
                                                              ),
                                                              textAlign:
                                                                  _isHidden
                                                                  ? TextAlign
                                                                        .left
                                                                  : TextAlign
                                                                        .center,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .clip,
                                                              softWrap: false,
                                                            ),
                                                          ),
                                                        ),
                                                        SizedBox(
                                                          height: 6 * scale,
                                                        ),
                                                        // 专辑封面
                                                        SizedBox.square(
                                                          dimension: imageSize,
                                                          child: DecoratedBox(
                                                            decoration: BoxDecoration(
                                                              borderRadius:
                                                                  borderRadius,
                                                              boxShadow: [
                                                                BoxShadow(
                                                                  color: Colors
                                                                      .black
                                                                      .withValues(
                                                                        alpha:
                                                                            0.3,
                                                                      ),
                                                                  blurRadius:
                                                                      12,
                                                                  offset:
                                                                      const Offset(
                                                                        0,
                                                                        2,
                                                                      ),
                                                                ),
                                                              ],
                                                            ),
                                                            child: ClipRRect(
                                                              borderRadius:
                                                                  borderRadius,
                                                              child: AspectRatio(
                                                                aspectRatio: 1,
                                                                child:
                                                                    (coverArt !=
                                                                            null &&
                                                                        coverArt
                                                                            .isNotEmpty)
                                                                    ? Image.memory(
                                                                        coverArt,
                                                                        // 按方形容器等比裁切缩放；B 站封面
                                                                        // 多为 16:9，cover 保证不变形。
                                                                        fit: BoxFit
                                                                            .cover,
                                                                        cacheWidth:
                                                                            (imageSize *
                                                                                    2)
                                                                                .round(),
                                                                        filterQuality:
                                                                            FilterQuality
                                                                                .medium,
                                                                        errorBuilder:
                                                                            (
                                                                              _,
                                                                              __,
                                                                              ___,
                                                                            ) =>
                                                                                fallback,
                                                                      )
                                                                    : const ColoredBox(
                                                                        color: Colors
                                                                            .black12,
                                                                        child: Center(
                                                                          child:
                                                                              fallback,
                                                                        ),
                                                                      ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  SizedBox(height: 8 * scale),
                                                  // 播放控制区域
                                                  AnimatedOpacity(
                                                    duration: const Duration(
                                                      milliseconds: 300,
                                                    ),
                                                    opacity: _isHidden
                                                        ? 0.0
                                                        : 1.0,
                                                    child: IgnorePointer(
                                                      ignoring: _isHidden,
                                                      child: const Playbar(),
                                                    ),
                                                  ),
                                                ],
                                              );
                                            },
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // 歌词区域
                            Expanded(
                              flex: 3,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left: 80 * scale,
                                  right: 80 * scale,
                                  top: 20 * scale,
                                  bottom: 40 * scale,
                                ),
                                child: Center(
                                  child: Builder(
                                    builder: (context) {
                                      final playlistNotifier = context
                                          .watch<PlaylistContentNotifier>();
                                      final currentLyrics =
                                          playlistNotifier.currentLyrics;
                                      if (currentLyrics.isEmpty) {
                                        return const Center(
                                          child: Text(
                                            '无歌词数据',
                                            style: TextStyle(
                                              fontSize: 20,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        );
                                      }
                                      return StreamBuilder<int>(
                                        stream: playlistNotifier
                                            .lyricLineIndexStream,
                                        initialData: playlistNotifier
                                            .currentLyricLineIndex,
                                        builder: (context, snapshot) {
                                          // 歌词行是 TextButton，原本每行都能拿焦点。
                                          // 遥控器会把初始焦点落在歌词上、按左右又丢焦点；
                                          // 这里让歌词退出 D-pad 焦点链（鼠标 / 触摸点击
                                          // seek 不受影响），焦点只落在播放控件上。
                                          return ExcludeFocus(
                                            child: LyricsView(
                                              maxLinesPerLyric: context
                                                  .watch<SettingsProvider>()
                                                  .maxLinesPerLyric,
                                              onTapLine: (index) {
                                                playlistNotifier
                                                    .seekToLyricLine(index);
                                              },
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          drawer: const LyricsSettingsDrawer(),
        ),
      ),
        ),
      ),
      ),
    );
  }
}
