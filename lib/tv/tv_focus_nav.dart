import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tv_device.dart';

// Android TV 焦点导航层。
//
// 设计约束（依据真机回归结论）：
// 1. 方向键按屏幕几何位置做「严格方向」查找：按左只在当前控件左侧的空间里
//    找最近控件，按右只在右侧，上/下同理；找不到就不移动。绝不退化成
//    ReadingOrderTraversalPolicy.next()/previous()，否则「左右」会表现为
//    「上下」，与视觉直觉相反。
// 2. 不绘制任何自定义高亮框。Material / Android 原生已有自己的焦点高亮，
//    再叠加一层青色描边会出现双重高亮、甚至把整个页面框住。
// 3. 冷启动、路由切换、抽屉 / 浮层打开时把焦点落到真实可聚焦控件上，
//    并优先选择面积较小的叶子控件，避免焦点落在整页容器上。
// 4. 进度条一类会吞掉四个方向键的 Slider 不参与焦点遍历（见
//    TvPointerOnlySlider），只保留鼠标 / 触控拖动。

class TvDirectionalFocusIntent extends Intent {
  const TvDirectionalFocusIntent(this.direction);

  final TraversalDirection direction;
}

class TvDirectionalFocusAction extends Action<TvDirectionalFocusIntent> {
  @override
  Object? invoke(TvDirectionalFocusIntent intent) {
    final manager = FocusManager.instance;
    final node = manager.primaryFocus;

    if (node == null || node == manager.rootScope || node.context == null) {
      TvFocusController.instance.scheduleEnsureFocus();
      return KeyEventResult.handled;
    }

    // 输入框的方向键由 EditableText 自己的 Shortcuts 处理光标移动，
    // 这里必须明确放行，返回 null 会被 Shortcuts 当成 handled 吞掉按键。
    if (_isEditableFocus(node)) return KeyEventResult.ignored;

    TvFocusController.instance.moveFocus(intent.direction, node);
    return KeyEventResult.handled;
  }

  static bool _isEditableFocus(FocusNode node) {
    final context = node.context;
    if (context == null) return false;
    final widget = context.widget;
    if (widget is EditableText ||
        widget is TextField ||
        widget is TextFormField) {
      return true;
    }
    var found = false;
    context.visitAncestorElements((element) {
      final candidate = element.widget;
      if (candidate is EditableText ||
          candidate is TextField ||
          candidate is TextFormField) {
        found = true;
        return false;
      }
      if (candidate is Scaffold || candidate is Dialog) return false;
      return true;
    });
    return found;
  }
}

class _FocusCandidate {
  const _FocusCandidate(this.node, this.rect);

  final FocusNode node;
  final Rect rect;
}

class TvFocusController {
  TvFocusController._();

  static final TvFocusController instance = TvFocusController._();

  BuildContext? rootContext;
  bool _scheduled = false;

  void scheduleEnsureFocus() => _schedule(null);

  void scheduleFocusForRoute(Route<dynamic> route) =>
      _schedule((context) => ModalRoute.of(context) == route);

  void scheduleFocusInDrawer() => _schedule(
        (context) => context.findAncestorWidgetOfExactType<Drawer>() != null,
      );

  void scheduleFocusWhere(bool Function(BuildContext) where) =>
      _schedule(where);

  void openEndDrawerAndFocus(VoidCallback openDrawer) {
    openDrawer();
    scheduleFocusInDrawer();
  }

  void _schedule(bool Function(BuildContext)? where) {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      // 抽屉 / 弹窗有入场动画，等两帧再取焦点树。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _apply(where);
      });
    });
  }

  void _apply(bool Function(BuildContext)? where) {
    final manager = FocusManager.instance;
    final candidates = collectCandidates(manager.rootScope);
    if (candidates.isEmpty) return;

    bool matches(FocusNode node) {
      final context = node.context;
      if (context == null || !context.mounted) return false;
      if (where == null) return true;
      try {
        return where(context);
      } catch (_) {
        return false;
      }
    }

    if (where != null) {
      final matched = candidates.where((c) => matches(c.node)).toList();
      if (matched.isNotEmpty) {
        _pickLeaf(matched).requestFocus();
        return;
      }
      // 目标控件尚未出现时退化为通用初始焦点，不留空焦点。
    }

    final current = manager.primaryFocus;
    final invalid = current == null ||
        current == manager.rootScope ||
        current.context == null ||
        !current.context!.mounted;
    if (!invalid) return;
    _pickLeaf(candidates).requestFocus();
  }

  // 选面积最小的可聚焦控件，避免焦点落到整页容器上导致「整个界面被框住」。
  static FocusNode _pickLeaf(List<_FocusCandidate> candidates) {
    _FocusCandidate? best;
    double bestArea = double.infinity;
    for (final candidate in candidates) {
      final area = candidate.rect.width * candidate.rect.height;
      if (area <= 0) continue;
      if (area < bestArea) {
        bestArea = area;
        best = candidate;
      }
    }
    return (best ?? candidates.first).node;
  }

  // 严格几何方向导航：只看目标方向那一侧的空间，不做阅读顺序兜底。
  bool moveFocus(TraversalDirection direction, FocusNode current) {
    final currentRect = rectOf(current);
    if (currentRect == null) return false;

    final screen = screenSize();
    final candidates = collectCandidates(FocusManager.instance.rootScope);
    final cur = currentRect.center;
    final scope = current.enclosingScope;
    const double epsilon = 2.0;

    _FocusCandidate? best;
    double bestScore = double.infinity;

    for (final candidate in candidates) {
      if (candidate.node == current) continue;
      // 只在同一模态层内移动，避免焦点跑到抽屉 / 弹窗背后的控件上。
      if (candidate.node.enclosingScope != scope) continue;
      if (!candidate.rect.overlaps(Offset.zero & screen)) continue;
      // 跳过整页级大容器。
      if (candidate.rect.width >= screen.width * 0.92 &&
          candidate.rect.height >= screen.height * 0.88) {
        continue;
      }
      // 跳过完全包住当前控件的祖先容器。
      if (candidate.rect.contains(cur) &&
          (candidate.rect.width > currentRect.width + 8 ||
              candidate.rect.height > currentRect.height + 8)) {
        continue;
      }

      final center = candidate.rect.center;
      late double primary;
      late double secondary;
      switch (direction) {
        case TraversalDirection.left:
          if (center.dx >= cur.dx - epsilon) continue;
          primary = cur.dx - center.dx;
          secondary = (center.dy - cur.dy).abs();
          break;
        case TraversalDirection.right:
          if (center.dx <= cur.dx + epsilon) continue;
          primary = center.dx - cur.dx;
          secondary = (center.dy - cur.dy).abs();
          break;
        case TraversalDirection.up:
          if (center.dy >= cur.dy - epsilon) continue;
          primary = cur.dy - center.dy;
          secondary = (center.dx - cur.dx).abs();
          break;
        case TraversalDirection.down:
          if (center.dy <= cur.dy + epsilon) continue;
          primary = center.dy - cur.dy;
          secondary = (center.dx - cur.dx).abs();
          break;
      }

      // 主方向距离为主，副方向偏移作为惩罚，避免斜着跳到很远的对角控件。
      final score = primary + secondary * 2.0;
      if (score < bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    if (best == null) return false;
    best.node.requestFocus();
    return true;
  }

  static List<_FocusCandidate> collectCandidates(FocusNode root) {
    final out = <_FocusCandidate>[];
    _collect(root, out, 0);
    return out;
  }

  // 用 children 而非 traversalChildren：FocusScopeNode 在
  // canRequestFocus=false 时 traversalChildren 为空，会漏掉抽屉 / 浮层控件。
  static void _collect(
    FocusNode node,
    List<_FocusCandidate> out,
    int depth,
  ) {
    if (depth > 24) return;
    for (final child in node.children) {
      if (child is FocusScopeNode) {
        _collect(child, out, depth + 1);
        continue;
      }
      final rect = rectOf(child);
      if (rect != null && child.canRequestFocus && !child.skipTraversal) {
        out.add(_FocusCandidate(child, rect));
      }
      _collect(child, out, depth + 1);
    }
  }

  static Rect? rectOf(FocusNode node) {
    final context = node.context;
    if (context == null || !context.mounted) return null;
    final object = context.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) {
      return null;
    }
    return object.localToGlobal(Offset.zero) & object.size;
  }

  static Size screenSize() {
    final view = ui.PlatformDispatcher.instance.views.first;
    final dpr = view.devicePixelRatio <= 0 ? 1.0 : view.devicePixelRatio;
    return view.physicalSize / dpr;
  }
}

class TvFocusNavigatorObserver extends NavigatorObserver {
  TvFocusNavigatorObserver();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    TvFocusController.instance.scheduleFocusForRoute(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) {
      TvFocusController.instance.scheduleFocusForRoute(previousRoute);
    } else {
      TvFocusController.instance.scheduleEnsureFocus();
    }
  }
}

// 非 Navigator route 的浮层（音量竖条等）用这个栈登记关闭回调，
// 返回键优先关闭最上层浮层，再走 Navigator / 退出。
class TvOverlayRegistry {
  TvOverlayRegistry._();

  static final TvOverlayRegistry instance = TvOverlayRegistry._();

  final List<VoidCallback> _closers = <VoidCallback>[];

  bool get hasOverlay => _closers.isNotEmpty;

  void add(VoidCallback close) {
    if (!_closers.contains(close)) _closers.add(close);
  }

  void remove(VoidCallback close) => _closers.remove(close);

  bool closeTop() {
    if (_closers.isEmpty) return false;
    _closers.removeLast()();
    return true;
  }
}

// 给原本不可聚焦的控件补一层 Focus，并把 OK / Enter / 空格统一转成 onActivate。
class TvFocusable extends StatelessWidget {
  const TvFocusable({
    required this.child,
    this.onActivate,
    this.autofocus = false,
    this.focusNode,
    this.debugLabel,
    super.key,
  });

  final Widget child;
  final VoidCallback? onActivate;
  final bool autofocus;
  final FocusNode? focusNode;
  final String? debugLabel;

  @override
  Widget build(BuildContext context) {
    final focusedChild = Focus(
      focusNode: focusNode,
      autofocus: autofocus,
      debugLabel: debugLabel,
      child: child,
    );
    if (onActivate == null) return focusedChild;
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (ActivateIntent intent) {
            onActivate!();
            return true;
          },
        ),
      },
      child: focusedChild,
    );
  }
}

// 让 Slider 只响应鼠标 / 触控，不参与键盘焦点遍历。
// Flutter 的 Slider 会把上下左右四个方向键全部映射成「调整数值」，焦点一旦
// 落上去，方向键就被它独占，无法再移动到任何其它控件（真机复现：按上/左/下
// 焦点完全不动，按右只会把进度从 00:00 推到 00:07）。
// TV 上进度条改为纯指针操作；快进 / 快退由遥控器媒体键与手柄扳机键承担。
class TvPointerOnlySlider extends StatelessWidget {
  const TvPointerOnlySlider({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!TvDevice.isTv) return child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      descendantsAreFocusable: false,
      descendantsAreTraversable: false,
      child: child,
    );
  }
}

class TvFocusScope extends StatefulWidget {
  const TvFocusScope({required this.child, super.key});

  final Widget child;

  @override
  State<TvFocusScope> createState() => _TvFocusScopeState();
}

class _TvFocusScopeState extends State<TvFocusScope> {
  @override
  void initState() {
    super.initState();
    TvFocusController.instance.scheduleEnsureFocus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    TvFocusController.instance.rootContext = context;
  }

  @override
  Widget build(BuildContext context) {
    // Actions 必须放在 Shortcuts 之上：Shortcuts 会从 primaryFocus.context
    // 向上查找 Actions，放在下层会找不到自定义动作。
    return Actions(
      actions: <Type, Action<Intent>>{
        TvDirectionalFocusIntent: TvDirectionalFocusAction(),
      },
      child: Shortcuts(
        shortcuts: <ShortcutActivator, Intent>{
          const SingleActivator(LogicalKeyboardKey.arrowUp):
              const TvDirectionalFocusIntent(TraversalDirection.up),
          const SingleActivator(LogicalKeyboardKey.arrowDown):
              const TvDirectionalFocusIntent(TraversalDirection.down),
          const SingleActivator(LogicalKeyboardKey.arrowLeft):
              const TvDirectionalFocusIntent(TraversalDirection.left),
          const SingleActivator(LogicalKeyboardKey.arrowRight):
              const TvDirectionalFocusIntent(TraversalDirection.right),
        },
        child: FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: widget.child,
        ),
      ),
    );
  }
}
