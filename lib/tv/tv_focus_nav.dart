import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Android TV 焦点导航层。
//
// 背景：Flutter 在 Android 上把方向键绑定到 DirectionalFocusIntent，但
// DirectionalFocusAction 使用 primaryFocus?.inDirection(...)。应用冷启动时
// primaryFocus 是 rootScope，没有任何可遍历的控件，方向键因此完全空转，
// 侧边栏 / 播放栏 / 播放页 / 弹窗全部不可达。
//
// 本层提供四件事：
// 1. 显式接管方向键并驱动 ReadingOrderTraversalPolicy.inDirection（带兜底）。
// 2. 启动、路由切换、抽屉打开时自动把焦点落到真实控件上。
// 3. 全局可见焦点框，不依赖各控件自己的 focused 样式。
// 4. 浮层栈，返回键优先关闭音量条一类的 OverlayEntry。

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

    // 输入框的方向键由 EditableText 自己的 Shortcuts 处理光标移动；
    // 这里不抢，也不重复移动焦点。
    if (_isEditableFocus(node)) {
      return null;
    }

    final policy = FocusTraversalGroup.maybeOf(node.context!);
    if (policy == null) {
      TvFocusController.instance.scheduleEnsureFocus();
      return KeyEventResult.handled;
    }

    final moved = policy.inDirection(node, intent.direction);
    if (!moved) {
      // 某些布局（列表末端、浮层）方向查找会失败，退化为按阅读顺序前进/后退。
      if (intent.direction == TraversalDirection.down ||
          intent.direction == TraversalDirection.right) {
        policy.next(node);
      } else {
        policy.previous(node);
      }
    }
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

class TvFocusController {
  TvFocusController._();

  static final TvFocusController instance = TvFocusController._();

  BuildContext? rootContext;
  bool _scheduled = false;

  void scheduleEnsureFocus() => _schedule(null, false);

  void scheduleFocusForRoute(Route<dynamic> route) =>
      _schedule((context) => ModalRoute.of(context) == route, true);

  void scheduleFocusInDrawer() => _schedule(
        (context) => context.findAncestorWidgetOfExactType<Drawer>() != null,
        true,
      );

  void scheduleFocusWhere(bool Function(BuildContext) where) =>
      _schedule(where, true);

  void openEndDrawerAndFocus(VoidCallback openDrawer) {
    openDrawer();
    scheduleFocusInDrawer();
  }

  void _schedule(bool Function(BuildContext)? where, bool force) {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      // 抽屉 / 弹窗有入场动画，等两帧再取焦点树。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _apply(where, force);
      });
    });
  }

  void _apply(bool Function(BuildContext)? where, bool force) {
    final manager = FocusManager.instance;
    final nodes = <FocusNode>[];
    _collect(manager.rootScope, nodes, 0);

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

    if (where != null || force) {
      for (final node in nodes) {
        if (matches(node)) {
          node.requestFocus();
          return;
        }
      }
      if (where != null) return;
    }

    final current = manager.primaryFocus;
    final invalid = current == null ||
        current == manager.rootScope ||
        current.context == null ||
        !current.context!.mounted;
    if (!invalid) return;

    final context = rootContext;
    FocusNode? first;
    if (context != null && context.mounted) {
      final policy = FocusTraversalGroup.maybeOf(context);
      first = policy?.findFirstFocus(manager.rootScope);
    }
    if (first != null && first != manager.rootScope && first.context != null) {
      first.requestFocus();
      return;
    }
    for (final node in nodes) {
      if (node.context != null && node.context!.mounted) {
        node.requestFocus();
        return;
      }
    }
  }

  // 用 children 而非 traversalChildren：FocusScopeNode 在
  // canRequestFocus=false 时 traversalChildren 为空，会漏掉抽屉 / 浮层控件。
  static void _collect(FocusNode node, List<FocusNode> out, int depth) {
    if (depth > 24) return;
    for (final child in node.children) {
      if (child is FocusScopeNode) {
        _collect(child, out, depth + 1);
        continue;
      }
      if (child.context != null &&
          child.context!.mounted &&
          child.canRequestFocus &&
          !child.skipTraversal) {
        out.add(child);
      }
      _collect(child, out, depth + 1);
    }
  }
}

class TvFocusNavigatorObserver extends NavigatorObserver {
  const TvFocusNavigatorObserver();

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

// 给原本不可聚焦的控件（GestureDetector / MouseRegion / 自定义绘制区）
// 补一层 Focus，并把 OK / Enter / 空格统一转成 onActivate。
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
    // Actions 必须放在 Shortcuts 之上：Shortcuts 会从自身 context 或
    // primaryFocus.context 向上查找 Actions，放在下层会找不到自定义动作。
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
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              widget.child,
              const Positioned.fill(child: TvFocusHighlight()),
            ],
          ),
        ),
      ),
    );
  }
}

// 全局焦点框：跟随 primaryFocus 的真实 RenderBox，任何控件都看得见焦点。
class TvFocusHighlight extends StatefulWidget {
  const TvFocusHighlight({super.key});

  @override
  State<TvFocusHighlight> createState() => _TvFocusHighlightState();
}

class _TvFocusHighlightState extends State<TvFocusHighlight> {
  final ValueNotifier<Rect?> _rect = ValueNotifier<Rect?>(null);

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_refresh);
    WidgetsBinding.instance.addPersistentFrameCallback(_onFrame);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_refresh);
    WidgetsBinding.instance.removePersistentFrameCallback(_onFrame);
    _rect.dispose();
    super.dispose();
  }

  void _onFrame(Duration timestamp) => _refresh();

  void _refresh() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return;

    final node = FocusManager.instance.primaryFocus;
    final manager = FocusManager.instance;
    Rect? next;
    if (node != null && node != manager.rootScope && node.context != null) {
      final target = node.context!.findRenderObject();
      if (target is RenderBox && target.attached && target.hasSize) {
        final topLeft = box.globalToLocal(target.localToGlobal(Offset.zero));
        final bottomRight = box.globalToLocal(
          target.localToGlobal(target.size.bottomRight(Offset.zero)),
        );
        final rect = Rect.fromPoints(topLeft, bottomRight).inflate(5);
        final clipped = rect.intersect(Offset.zero & box.size);
        if (clipped.width >= 4 && clipped.height >= 4) next = clipped;
      }
    }
    if (_rect.value != next) _rect.value = next;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Rect?>(
      valueListenable: _rect,
      builder: (context, rect, _) {
        return IgnorePointer(
          child: CustomPaint(
            painter: rect == null ? null : _TvFocusPainter(rect),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

class _TvFocusPainter extends CustomPainter {
  const _TvFocusPainter(this.rect);

  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xCC000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFF66E0FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawRRect(
      rrect.deflate(3),
      Paint()
        ..color = const Color(0x2666E0FF)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_TvFocusPainter oldDelegate) => oldDelegate.rect != rect;
}
