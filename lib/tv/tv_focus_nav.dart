import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
//    TvPointerOnlySlider），只保留鼠标 / 触控拖动；设置里的滑块改用
//    TvAdjustableSlider，遥控器可调值且能用垂直方向键离开。
// 5. 只有抽屉 / 对话框 / 菜单这类浮层内部才限制移动范围；主界面允许
//    跨越左侧栏、内容区、底部播放栏等不同 FocusScope 按几何方向移动。

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
      TvFocusController.instance.restoreFocusNow();
      return KeyEventResult.handled;
    }

    // 焦点落在「看得到坐标、看不到界面」的节点上（Navigator 保活的旧页面、
    // Offstage 页签、页面切换动画中的离屏 route）时，几何导航会直接失效：
    // 按方向键毫无反应，而 OK 仍会激活那个隐藏控件（实测会误触发旧页面的
    // 收藏按钮，弹出「已收藏 / 已取消收藏」）。先把焦点拉回当前可见页面。
    if (TvFocusController.rectOf(node) == null) {
      TvFocusController.instance.restoreFocusNow();
      return KeyEventResult.handled;
    }

    // 输入框的方向键由 EditableText 自己的 Shortcuts 处理光标移动，
    // 这里必须明确放行，返回 null 会被 Shortcuts 当成 handled 吞掉按键。
    if (_isEditableFocus(node)) return KeyEventResult.ignored;

    // 设置类滑块优先：TvDirectionalFocusAction 是每次方向键必然触发的唯一
    // 入口（焦点移动本就由它驱动）。按注册的滑块 FocusNode / rect 匹配，
    // 命中则交给滑块自己：调值方向调值、其余方向按几何移开焦点。这样不受
    // Flutter 焦点节点身份或按键分发顺序影响（MuMu 实测：focused 语义节点
    // 常是包着滑块的整行容器，靠 debugLabel 或内层 Shortcuts 都会漏）。
    if (TvFocusController.instance.handleSliderKey(intent.direction, node)) {
      TvFocusController.instance.restoreFocusNow();
      return KeyEventResult.handled;
    }

    // 严格几何方向优先；若该方向上确实没有同行 / 同列候选，再放宽对齐
    // 约束重试一次（方向仍然严格不变），避免焦点卡在死角里按不动。
    if (!TvFocusController.instance.moveFocus(
      intent.direction,
      node,
      lockZone: true,
    )) {
      TvFocusController.instance.moveFocus(
        intent.direction,
        node,
        relaxed: true,
        lockZone: true,
      );
    }
    // 两个方向都找不到候选（例如控制栏第一个按钮再按 UP）时，同步把焦点
    // 保持在 / 拉回一个可见控件，绝不留下空焦点。
    TvFocusController.instance.restoreFocusNow();
    return KeyEventResult.handled;
  }

  static bool _isEditableFocus(FocusNode node) =>
      TvFocusController.isEditableFocus(node);
}

class _FocusCandidate {
  const _FocusCandidate(this.node, this.rect);

  final FocusNode node;
  final Rect rect;
}

/// 屏幕上的导航区域。rail / content 同属上层（左右并排），bottomBar 是下层。
/// 上下键采用「同区优先、边界溢出」，左右键允许自由跨区。
enum _NavZone { rail, content, bottomBar }

/// 设置滑块注册项：TvAdjustableSlider 把自己的 FocusNode 与方向键处理函数
/// 登记进来。TvDirectionalFocusAction 是每次方向键必然触发的唯一入口，
/// 在这里按 rect 匹配「焦点是否落在滑块行」，避免依赖 Flutter 焦点节点身份
/// 或按键分发顺序（实测语义树 focused 常是包着滑块的整行容器，而不是
/// 滑块自身的 Focus 节点，靠 debugLabel 判断会漏）。
class _SliderRegistration {
  const _SliderRegistration(this.node, this.handler);

  final FocusNode node;

  /// 返回 true 表示这个方向键已被滑块处理（调值或移开焦点）。
  final bool Function(TraversalDirection direction, FocusNode current) handler;
}

class TvFocusController {
  TvFocusController._();

  static final TvFocusController instance = TvFocusController._();

  BuildContext? rootContext;
  bool _scheduled = false;
  bool _pendingForce = false;

  /// 当前页面可注册自己的「焦点恢复目标」。播放页用它把焦点拉回控制栏，
  /// 避免全局 _pickLeaf 跳到底层迷你播放条 / 保活旧页面等不该聚焦的节点。
  bool Function()? _restoreHandler;

  void registerRestoreHandler(bool Function()? handler) {
    _restoreHandler = handler;
  }

  /// 播放页注册了页面级 Shortcuts 接管时，全局兜底应放行，不重复驱动。
  bool get hasRestoreHandler => _restoreHandler != null;

  /// 输入框（含祖先里的 EditableText / TextField / TextFormField）。方向键
  /// 必须放行给框架做光标移动，不能被焦点导航吞掉。
  static bool isEditableFocus(FocusNode? node) {
    if (node == null) return false;
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

  /// 同步恢复焦点：焦点本来就有效时**不要动它**（否则会覆盖 moveFocus
  /// 刚完成的移动，方向键就永远跳回第一个按钮）；只有真的落空 / 不可见时，
  /// 才用当前页面注册的目标拉回，失败再退回全局可见候选。
  bool restoreFocusNow() {
    final manager = FocusManager.instance;
    if (isValidFocus(manager.primaryFocus)) return true;
    final handler = _restoreHandler;
    if (handler != null) {
      try {
        if (handler()) return true;
      } catch (_) {}
    }
    return ensureValidFocus();
  }

  final List<_SliderRegistration> _sliders = <_SliderRegistration>[];

  void registerSlider(
    FocusNode node,
    bool Function(TraversalDirection, FocusNode) handler,
  ) {
    _sliders.removeWhere((r) => r.node == node);
    _sliders.add(_SliderRegistration(node, handler));
  }

  void unregisterSlider(FocusNode node) {
    _sliders.removeWhere((r) => r.node == node);
  }

  /// 若当前 primaryFocus 属于某个设置滑块，交给它处理方向键并返回 true。
  /// 匹配规则：节点相同，或当前节点矩形包含滑块矩形中心且宽度不小于滑块的
  /// 六成（覆盖「整行容器持有焦点」的情形）。
  bool handleSliderKey(TraversalDirection direction, FocusNode current) {
    if (_sliders.isEmpty) return false;
    for (final r in _sliders) {
      if (r.node == current) {
        return r.handler(direction, current);
      }
    }
    final cur = rectOf(current);
    if (cur == null) return false;
    for (final r in _sliders) {
      final s = rectOf(r.node);
      if (s == null) continue;
      if (cur.contains(s.center) && cur.width >= s.width * 0.6) {
        return r.handler(direction, current);
      }
    }
    return false;
  }

  void scheduleEnsureFocus() => _schedule(null);

  // 抽屉 / 浮层关闭后，里面的焦点节点随之销毁，主动重新选一个可聚焦控件，
  // 否则下一次方向键又会因为 primaryFocus 落空而空转。
  void scheduleRestoreFocus() => _schedule(null, force: true);

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

  bool Function(BuildContext)? _pendingWhere;

  void _schedule(bool Function(BuildContext)? where, {bool force = false}) {
    // 同一帧里多个来源同时请求恢复焦点时，保留「最后一次带目标」的请求，
    // 而不是被 _scheduled 直接丢掉（播放页初始焦点曾被这样吞掉）。
    _pendingWhere = where ?? _pendingWhere;
    _pendingForce = _pendingForce || force;
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 抽屉 / 弹窗有入场动画，等两帧再取焦点树。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduled = false;
        final pendingForce = _pendingForce;
        final pendingWhere = _pendingWhere;
        _pendingForce = false;
        _pendingWhere = null;
        _apply(pendingWhere, force: pendingForce);
      });
    });
  }

  /// 焦点是否是一个「用户看得见、按 OK 有意义」的具体控件。
  /// 整页级容器（宽 >= 85% 或高 >= 80% 屏幕）虽然 rectOf 有效，但把焦点
  /// 放在上面只会表现为整页无高亮，必须当作无效重新恢复。
  static bool isValidFocus(FocusNode? focus) {
    if (focus == null || focus == FocusManager.instance.rootScope) return false;
    final context = focus.context;
    if (context == null || !context.mounted) return false;
    final rect = rectOf(focus);
    if (rect == null) return false;
    return !isPageContainerLike(rect, screenSize());
  }

  /// 是否「不该作为焦点落点」的布局容器。
  ///
  /// 曾用「宽 >= 85% **或** 高 >= 80%」一刀切，结果把全宽但很矮的列表项
  /// （歌手 / 全部歌曲 / B 站列表，宽约 90%、高约 13%）误判成整页容器：
  /// `moveFocus` 跳过它们、`isValidFocus` 又把已落上去的焦点拉回，表现为
  /// 按下键直接跳过整个主内容区，落到下方播放控制栏。
  ///
  /// 现在只排除两类真正的容器：
  ///  * 整页容器：同时占据大部分宽和高（>= 92% / >= 88%）；
  ///  * 细长侧栏：高 >= 80% 但宽 <= 25%（左侧导航整列）。
  /// 全宽列表项、抽屉表单行都必须保留。
  static bool isPageContainerLike(Rect rect, Size screen) {
    if (rect.width <= 0 || rect.height <= 0) return true;
    final bool pageLike = rect.width >= screen.width * 0.92 &&
        rect.height >= screen.height * 0.88;
    final bool tallRail = rect.height >= screen.height * 0.80 &&
        rect.width <= screen.width * 0.25;
    return pageLike || tallRail;
  }

  /// 屏幕区域划分（用于上下方向的「同区优先、边界溢出」）。侧栏在最左
  /// ~77px，底部播放控制栏在最下 ~58px，主内容区就是红线画的那块。
  /// 用控件中心点归类；中心点落在底部栏时优先判为 bottomBar。
  static _NavZone zoneOf(Offset center, Size screen) {
    if (center.dy >= screen.height - 62) return _NavZone.bottomBar;
    if (center.dx <= 80) return _NavZone.rail;
    return _NavZone.content;
  }

  /// 同步保证「当前焦点一定是一个可见控件」。
  ///
  /// 方向键走到边界（例如控制栏第一个按钮再按 UP）时两个方向的
  /// moveFocus 都会失败；若此时控件正好因自动隐藏等原因失去语义，
  /// 焦点会变成 rootScope / 落到不可见节点，表现为整页无高亮，下一次 OK
  /// 还可能激活旧页面按钮。这里在每次方向键处理前后各兜一次，确保
  /// 遥控器 / 手柄任何时刻都有明确落点。
  bool ensureValidFocus() {
    final manager = FocusManager.instance;
    if (isValidFocus(manager.primaryFocus)) return true;
    final candidates = collectCandidates(manager.rootScope);
    if (candidates.isEmpty) return false;
    _pickLeaf(candidates).requestFocus();
    return true;
  }

  /// 同步把焦点放到满足 [where] 的候选里视觉最靠前的一个。
  /// 用于「页面刚打开 / 控件栏刚从隐藏恢复」这类必须立刻生效的场景，
  /// 不受 _schedule 两帧延迟影响。
  bool focusFirstWhere(bool Function(BuildContext) where) {
    final matched = collectCandidates(FocusManager.instance.rootScope)
        .where((candidate) {
      final context = candidate.node.context;
      if (context == null || !context.mounted) return false;
      try {
        return where(context);
      } catch (_) {
        return false;
      }
    }).toList();
    if (matched.isEmpty) return false;
    _pickLeaf(matched).requestFocus();
    return true;
  }

  /// 只在满足 [inScope] 的候选之间做「同一行左右移动」。
  ///
  /// 上下方向**保持当前焦点不动**；焦点不在集合内时落到第一个。
  /// 供播放页这类「只有一行控件、上方没有任何可聚焦内容」的页面接管方向键：
  /// 全局几何导航在 UP 找不到候选时会把焦点交还框架，触发恢复 / 守卫连锁，
  /// 实测会落到无语义容器上（整页无高亮、后续方向键全部失效）。
  bool stepWithinScopedRow(
    TraversalDirection direction,
    bool Function(BuildContext) inScope,
  ) {
    final manager = FocusManager.instance;
    final screen = screenSize();
    final row = collectCandidates(manager.rootScope).where((c) {
      final context = c.node.context;
      if (context == null || !context.mounted) return false;
      if (isPageContainerLike(c.rect, screen)) return false;
      try {
        return inScope(context);
      } catch (_) {
        return false;
      }
    }).toList()
      ..sort((a, b) {
        final rowDiff = (a.rect.top - b.rect.top).abs();
        if (rowDiff > 12.0) return a.rect.top.compareTo(b.rect.top);
        return a.rect.left.compareTo(b.rect.left);
      });
    if (row.isEmpty) return false;
    final current = manager.primaryFocus;
    final index = row.indexWhere((c) => c.node == current);
    if (index < 0) {
      row.first.node.requestFocus();
      return true;
    }
    if (direction == TraversalDirection.left && index > 0) {
      row[index - 1].node.requestFocus();
    } else if (direction == TraversalDirection.right &&
        index < row.length - 1) {
      row[index + 1].node.requestFocus();
    }
    // up / down：什么都不做，焦点保持在这一行的按钮上。
    return true;
  }

  void _apply(bool Function(BuildContext)? where, {bool force = false}) {
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
    if (!invalid && !force) return;
    _pickLeaf(candidates).requestFocus();
  }

  // 初始 / 恢复焦点：按「视觉上从上到下、从左到右」选第一个叶子控件。
  // 旧实现选全局面积最小的控件，实际会落到某个小图标（星标 / 翻页箭头）
  // 上，与界面主次不符；同时整页级容器要先剔除，避免「整个界面被框住」。
  static FocusNode _pickLeaf(List<_FocusCandidate> candidates) {
    final screen = screenSize();
    final usable = candidates.where((c) {
      if (c.rect.width <= 0 || c.rect.height <= 0) return false;
      // 只排除整页容器 / 细长侧栏；全宽但很矮的列表项必须保留。
      if (isPageContainerLike(c.rect, screen)) return false;
      return true;
    }).toList();
    if (usable.isEmpty) return candidates.first.node;
    usable.sort((a, b) {
      const double rowTolerance = 12.0;
      final rowDiff = (a.rect.top - b.rect.top).abs();
      if (rowDiff > rowTolerance) return a.rect.top.compareTo(b.rect.top);
      return a.rect.left.compareTo(b.rect.left);
    });
    return usable.first.node;
  }

  // 严格几何方向导航：只看目标方向那一侧的空间，不做阅读顺序兜底。
  // [relaxed] 为 true 时取消「同行 / 同列」加权（严格方向仍保留），
  // 用于严格模式找不到任何候选时的第二次兜底，避免焦点卡死。
  bool moveFocus(
    TraversalDirection direction,
    FocusNode current, {
    bool relaxed = false,
    FocusNode? exclude,
    bool lockZone = false,
  }) {
    final currentRect = rectOf(current);
    if (currentRect == null) {
      // 起点不可见时不要空转：拉回当前页面，避免焦点卡在旧页面节点上。
      TvFocusController.instance.scheduleRestoreFocus();
      return false;
    }

    final screen = screenSize();
    final candidates = collectCandidates(FocusManager.instance.rootScope);
    final cur = currentRect.center;
    const double epsilon = 2.0;
    // 垂直方向要求「实质垂直位移」：底部播放栏里的控件中心 y 只差几像素，
    // 用 epsilon=2 会把同一行左侧的 mini 封面当成「上方候选」，按 UP 就在
    // 控制栏内部横跳，而不是回到主内容区。左右键仍用 epsilon。
    const double verticalMinDelta = 12.0;
    final bool vertical = direction == TraversalDirection.up ||
        direction == TraversalDirection.down;

    // 上下方向采用「同区优先、边界溢出」，而不是 v1.6.1 的硬锁区。
    //  * 第一轮只在当前区域内找候选，保留 v1.6.1 的修复：全宽内容行的
    //    中心 x 与侧栏小图标差很多，旧评分会让它输给「垂直更近但属于
    //    侧栏」的图标，按 DOWN 直接跳过整个红线主内容区、落到侧栏或
    //    底部播放控制栏。
    //  * 第二轮仅当同区域在该方向上确实没有候选时，才允许沿垂直方向
    //    溢出到相邻层，恢复遥控器应有的直觉（v1.6.1 硬锁区把区域间的
    //    自然往返也封死了，实测只能靠左右键绕行）。
    //  * 左右键不锁区（zone == null），保证从侧栏按 RIGHT 能进主内容区。
    final _NavZone? zone =
        lockZone && vertical ? zoneOf(cur, screen) : null;

    // rail / content 同属上层（左右并排），bottomBar 是下层。垂直溢出只
    // 允许 上层 --DOWN--> 下层、下层 --UP--> 上层；rail <-> content 是
    // 左右关系，上下键禁止互跨，否则会重现「按 DOWN 跳到左侧栏」的回归。
    bool overflowAllowed(_NavZone candidateZone) {
      if (zone == null) return true;
      if (direction == TraversalDirection.down) {
        return zone != _NavZone.bottomBar &&
            candidateZone == _NavZone.bottomBar;
      }
      if (direction == TraversalDirection.up) {
        return zone == _NavZone.bottomBar &&
            candidateZone != _NavZone.bottomBar;
      }
      return true;
    }

    // 抽屉 / 对话框 / 弹出菜单打开时把焦点锁在该浮层内部；主界面则允许
    // 跨越左侧栏、内容区、底部播放栏等不同的 FocusScope —— 早期版本用
    // enclosingScope 硬隔离，导致「红圈 / 绿圈像两个图层、焦点互相过不去」。
    final activeLayer = _activeModalLayer(current, candidates);

    // 允许焦点落到可滚动内容里暂时被裁切的控件（上下各放宽一屏），
    // 随后用 Scrollable.ensureVisible 把它滚进可视区。
    final scrollReach = Rect.fromLTRB(
      -screen.width * 0.1,
      -screen.height,
      screen.width * 1.1,
      screen.height * 2,
    );

    // 单次严格几何查找。sameZoneOnly=true 时只看本区域；false 时只看
    // 允许溢出的相邻层（左右方向 zone==null，两个标志等价，不过滤）。
    _FocusCandidate? search({required bool sameZoneOnly}) {
      _FocusCandidate? localBest;
      double localScore = double.infinity;

      for (final candidate in candidates) {
        if (candidate.node == current || candidate.node == exclude) continue;
        if (zone != null) {
          final candidateZone = zoneOf(candidate.rect.center, screen);
          final same = candidateZone == zone;
          if (sameZoneOnly) {
            if (!same) continue;
          } else if (same || !overflowAllowed(candidateZone)) {
            continue;
          }
        }
        final layer = _modalLayerOf(candidate.node);
        if (activeLayer != null) {
          if (layer != activeLayer) continue;
        } else if (layer != null) {
          continue;
        }
        if (!candidate.rect.overlaps(scrollReach)) continue;
        // 只跳过整页容器 / 细长侧栏；全宽列表项（歌手 / B站 / 全部歌曲
        // 的内容行）必须保留，否则按 DOWN 会跳过整个主内容区。
        if (isPageContainerLike(candidate.rect, screen)) {
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
            if (center.dy >= cur.dy - verticalMinDelta) continue;
            primary = cur.dy - center.dy;
            secondary = (center.dx - cur.dx).abs();
            break;
          case TraversalDirection.down:
            if (center.dy <= cur.dy + verticalMinDelta) continue;
            primary = center.dy - cur.dy;
            secondary = (center.dx - cur.dx).abs();
            break;
        }

        // 设置类滑块是横向长条（中心点落在轨道中点），从上方/下方的按钮
        // 做垂直导航时中心点水平差会被放大 3.5 倍，长条永远被同列窄按钮
        // 挤掉。仅对这一类候选：垂直方向且当前控件水平投影落在轨道范围
        // 内时把副轴偏移按 0 计，让「正上/正下」由垂直距离决定。
        if (candidate.node.debugLabel == 'tv-adjustable-slider' &&
            vertical &&
            cur.dx >= candidate.rect.left - epsilon &&
            cur.dx <= candidate.rect.right + epsilon) {
          secondary = 0;
        }

        // 「同一视觉行 / 同一视觉列」优先：左右移动时垂直方向要有实质
        // 重叠，上下移动时水平方向要有实质重叠。同行 / 同列的相邻控件
        // 只用中心点偏移做轻度惩罚，跨行 / 跨列额外加权并加固定惩罚，
        // 避免从「播放全部」向下斜跳到旁侧列表、或从工具栏按右跳到
        // 另一个页签的控件。
        final bool horizontal =
            direction == TraversalDirection.left ||
            direction == TraversalDirection.right;
        final double overlap = horizontal
            ? math.min(currentRect.bottom, candidate.rect.bottom) -
                math.max(currentRect.top, candidate.rect.top)
            : math.min(currentRect.right, candidate.rect.right) -
                math.max(currentRect.left, candidate.rect.left);
        final double axisExtent = horizontal
            ? math.min(currentRect.height, candidate.rect.height)
            : math.min(currentRect.width, candidate.rect.width);
        final bool aligned =
            axisExtent > 0 && overlap >= axisExtent * 0.5;
        final double secondaryWeight =
            relaxed ? 2.0 : (aligned ? 1.2 : 3.5);
        final double crossPenalty =
            relaxed || aligned ? 0.0 : axisExtent;
        final score = primary + secondary * secondaryWeight + crossPenalty;
        if (score < localScore) {
          localScore = score;
          localBest = candidate;
        }
      }
      return localBest;
    }

    final _FocusCandidate? chosen = zone == null
        ? search(sameZoneOnly: false)
        : (search(sameZoneOnly: true) ?? search(sameZoneOnly: false));

    if (chosen == null) {
      // 到边界时**什么都不要做**：Flutter 默认会把焦点留在当前控件。
      // 曾在这里调用 current.requestFocus() 试图「按回」焦点，但它会触发
      // FocusManager 通知 -> guardian/restore 连锁，在控件栏动画期间反而
      // 把焦点弄丢（真机复现：按 UP 后整页无焦点、后续方向键全部失效）。
      // 静默返回 false，由 Action 末尾的 restoreFocusNow 判断是否需要兜底。
      return false;
    }
    chosen.node.requestFocus();
    _ensureVisible(chosen.node);
    return true;
  }

  // 浮层标识：Drawer 不是 Navigator route，按 widget 判定；
  // Dialog / 菜单 / BottomSheet 都是 PopupRoute，用 route 对象判定。
  // 播放页与内层 Navigator 的页面是 PageRoute，不算浮层，主界面可自由跨越。
  static Object? _modalLayerOf(FocusNode node) {
    final context = node.context;
    if (context == null || !context.mounted) return null;
    final drawer = context.findAncestorWidgetOfExactType<Drawer>();
    if (drawer != null) return drawer;
    final route = ModalRoute.of(context);
    if (route is PopupRoute) return route;
    return null;
  }

  static Object? _activeModalLayer(
    FocusNode current,
    List<_FocusCandidate> candidates,
  ) {
    final own = _modalLayerOf(current);
    if (own != null) return own;
    // 浮层刚打开、焦点还留在主界面时，也要把焦点拉回浮层内。
    for (final candidate in candidates.reversed) {
      final layer = _modalLayerOf(candidate.node);
      if (layer != null) return layer;
    }
    return null;
  }

  // 焦点移到被裁切的可选项时，自动把它滚进可视区（音效弹窗 / 长列表）。
  static void _ensureVisible(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = node.context;
      if (context == null || !context.mounted) return;
      try {
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } catch (_) {
        // 不在可滚动容器里时无需滚动。
      }
    });
  }

  static List<_FocusCandidate> collectCandidates(FocusNode root) {
    final out = <_FocusCandidate>[];
    _collect(root, out, 0);
    return out;
  }

  // 返回当前可聚焦控件对应的 context，供返回键查找抽屉所属 Scaffold。
  static List<BuildContext> focusableContexts() {
    final out = <BuildContext>[];
    for (final candidate in collectCandidates(FocusManager.instance.rootScope)) {
      final context = candidate.node.context;
      if (context != null && context.mounted) out.add(context);
    }
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
    // ExcludeFocus（以及 Focus(descendantsAreFocusable:false)）会让整棵子树
    // 退出焦点链。IndexedStack 的离屏子页虽然仍参与 layout，RenderBox 与
    // 可见页坐标完全重叠；若不排除，几何导航会把离屏页的控件也当成候选，
    // 表现为「按右跳到另一个页签」「栏目顺序混乱」。
    if (!node.descendantsAreFocusable || !node.descendantsAreTraversable) {
      return;
    }
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

    // 全局可见性判定：焦点树里会残留大量「看得到坐标、看不到界面」的节点。
    // 若不过滤，几何导航会把它们当成候选，表现为跨页乱跳 / 顺序混乱。
    // 1) Navigator 保活的旧页面、页面切换动画期间的离屏 route：
    //    只有当前 route 的节点才是真实可见的控件（对话框 / 抽屉本身是
    //    当前 route，正常保留；主界面在弹窗期间由 _activeModalLayer 排除）。
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return null;
    // 2) Offstage / Visibility(visible:false) 的整棵子树。
    final offstage = context.findAncestorWidgetOfExactType<Offstage>();
    if (offstage != null && offstage.offstage) return null;
    final visibility = context.findAncestorWidgetOfExactType<Visibility>();
    if (visibility != null && !visibility.visible) return null;

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

  // 返回键需要区分「确实关掉了一个 route」和 AppShell 里 PopScope 的
  // canPop:false 空操作：maybePop() 被 PopScope 拦截时会返回 true 却不触发
  // didPop，只有本计数增加才说明对话框 / 播放页真的出栈了。
  static int popCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    TvFocusController.instance.scheduleFocusForRoute(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
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
    // 所有 Android 设备都要包：大量电视盒子是普通 Android（isTv=false），
    // 但同样只靠遥控器十字键操作。若在此处 return child，裸 Slider 会吞掉
    // 四向键，方向键几何导航就会卡死在进度条上。这个 Focus 只禁用键盘焦点，
    // 鼠标 / 触控拖动完全不受影响。
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      descendantsAreFocusable: false,
      descendantsAreTraversable: false,
      child: child,
    );
  }
}

// 原生式焦点高亮：聚焦时给控件叠加一层半透明背景（类似 NavigationRail 的
// indicator），不画描边框、不改写全局主题。用于侧边栏项、底部专辑封面等
// 原本没有明显焦点态的控件。
class TvFocusHighlight extends StatefulWidget {
  const TvFocusHighlight({
    this.builder,
    this.child,
    this.onActivate,
    this.autofocus = false,
    this.debugLabel,
    this.focusNode,
    super.key,
  }) : assert(builder != null || child != null,
            'TvFocusHighlight needs either builder or child');

  /// 自定义聚焦外观（侧边栏要同时区分 selected / focused）。
  final Widget Function(BuildContext context, bool focused)? builder;

  /// 不传 builder 时用它，并自动叠加默认原生式背景高亮。
  final Widget? child;
  final VoidCallback? onActivate;
  final bool autofocus;
  final String? debugLabel;

  /// 外部传入时由调用方持有并在 dispose 中释放，用于数据加载完成后
  /// 精确 requestFocus（autofocus 只在控件首次创建时生效）。
  final FocusNode? focusNode;

  @override
  State<TvFocusHighlight> createState() => _TvFocusHighlightState();
}

class _TvFocusHighlightState extends State<TvFocusHighlight> {
  late final FocusNode _node;
  late final bool _ownsNode;

  @override
  void initState() {
    super.initState();
    _ownsNode = widget.focusNode == null;
    _node = widget.focusNode ?? FocusNode(debugLabel: widget.debugLabel);
    _node.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChange);
    if (_ownsNode) _node.dispose();
    super.dispose();
  }

  Widget _buildContent(BuildContext context, bool focused) {
    if (widget.builder != null) return widget.builder!(context, focused);
    // 默认原生式高亮：一层半透明主色背景 + 圆角，不画任何描边框。
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: focused
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.30)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: widget.child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final focused = Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      // 内部按钮自带的 Focus 节点退出焦点链，避免同一位置出现两个候选。
      descendantsAreFocusable: false,
      descendantsAreTraversable: false,
      child: _buildContent(context, _node.hasFocus),
    );
    if (widget.onActivate == null) return focused;
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (ActivateIntent intent) {
            widget.onActivate!();
            return true;
          },
        ),
      },
      child: focused,
    );
  }
}

// 设置类滑块：遥控器可达、可调值，同时「非调值方向」的方向键必须能离开，
// 否则会像进度条一样把四个方向键全部吞掉（真机复现：聚焦「界面缩放」后
// 按 ←/→/↑/↓ 数值不变、焦点也不动，遥控器卡死）。
// 水平滑块：←/→ 调值，↑/↓ 移开焦点；竖直滑块反之。
// 传入的 Slider 保持原样，鼠标 / 触控拖动依旧可用。
//
// 注意：本组件不能加 `if (!TvDevice.isTv) return child` 门控。普通 Android
// 设备（含 MuMu / 手机 + 外接键盘或遥控器）上 main.dart 不挂载 TvFocusScope，
// 裸露的 Flutter Slider 会把四向键吞掉却又不移动焦点；这里必须始终包装，
// 并自己用 TvFocusController 做「移开焦点」，不依赖 TvFocusScope 是否挂载。
class TvAdjustableSlider extends StatefulWidget {
  const TvAdjustableSlider({
    required this.child,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.onChangeEnd,
    this.vertical = false,
    super.key,
  });

  final Widget child;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final bool vertical;

  @override
  State<TvAdjustableSlider> createState() => _TvAdjustableSliderState();
}

class _TvAdjustableSliderState extends State<TvAdjustableSlider> {
  late final FocusNode _node;

  @override
  void initState() {
    super.initState();
    _node = FocusNode(debugLabel: 'tv-adjustable-slider');
    // 注册到唯一会触发的方向键入口（TvDirectionalFocusAction）。
    TvFocusController.instance.registerSlider(_node, _handleDirection);
  }

  @override
  void didUpdateWidget(TvAdjustableSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 值/回调随 setState 变化时重新注册，保证 handler 读到最新参数。
    TvFocusController.instance.registerSlider(_node, _handleDirection);
  }

  @override
  void dispose() {
    TvFocusController.instance.unregisterSlider(_node);
    _node.dispose();
    super.dispose();
  }

  bool _handleDirection(TraversalDirection direction, FocusNode current) {
    final bool isAdjust = widget.vertical
        ? (direction == TraversalDirection.up ||
            direction == TraversalDirection.down)
        : (direction == TraversalDirection.left ||
            direction == TraversalDirection.right);
    if (isAdjust) {
      final bool increase = widget.vertical
          ? direction == TraversalDirection.up
          : direction == TraversalDirection.right;
      _adjust(increase);
      return true;
    }
    // 非调值方向：按几何把焦点移到相邻控件（严格 + 放宽兜底）。
    // 必须排除滑块自身的 FocusNode：moveFocus 里「横向长条可达性」特判会把
    // 副轴偏移置 0，若语义焦点是包着滑块的整行容器，滑块节点就会成为最近的
    // 「正上/正下」候选，导致按 UP/DOWN 又落回滑块（实测 UP 离开失败）。
    if (!TvFocusController.instance.moveFocus(
      direction,
      current,
      exclude: _node,
    )) {
      TvFocusController.instance.moveFocus(
        direction,
        current,
        relaxed: true,
        exclude: _node,
      );
    }
    return true;
  }

  void _adjust(bool increase) {
    final min = widget.min;
    final max = widget.max;
    if (max <= min) return;
    final divisions = widget.divisions;
    final step = (max - min) / (divisions ?? 20);
    var next = (widget.value + (increase ? step : -step)).clamp(min, max);
    if (divisions != null && divisions > 0) {
      next = min + ((next - min) / step).round() * step;
      next = next.clamp(min, max);
    }
    if ((next - widget.value).abs() > 1e-9) {
      widget.onChanged(next);
      widget.onChangeEnd?.call(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 方向键统一由注册到 TvDirectionalFocusAction 的 handler 处理，这里不再
    // 放 onKeyEvent / 内层 Shortcuts（避免多路径重复调值或抢焦点）。
    // Slider 内部会吞键的 Focus / Shortcuts 退出焦点链；鼠标 / 触控不受影响。
    return Focus(
      focusNode: _node,
      canRequestFocus: true,
      skipTraversal: false,
      descendantsAreFocusable: false,
      descendantsAreTraversable: false,
      child: widget.child,
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
    // TV 上强制使用传统键盘焦点高亮：Material 控件只在
    // FocusHighlightMode.traditional 下显示焦点态，否则遥控器移到侧边栏 /
    // 专辑封面时看起来完全没有任何高亮。highlightMode 是只读属性，
    // 改由可写的 highlightStrategy 固定策略，避免随触摸输入切回 touch 模式。
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    // 焦点一旦落到不可见节点（旧页面 / Offstage 页签 / 动画中的离屏 route），
    // 立刻拉回当前页面。这样 OK 永远不会激活一个用户看不见的按钮 ——
    // 实测这个场景会误触发旧页面的收藏开关。
    FocusManager.instance.addListener(_guardPrimaryFocus);
    // Shortcuts 是从 primaryFocus.context 向上查找 Actions。焦点一旦落到
    // rootScope（页面切换、抽屉刚打开且没有 autofocus 控件），rootScope
    // 没有 context，方向键完全不会触发 TvDirectionalFocusAction；而
    // _guardPrimaryFocus 只在「焦点发生变化」时触发，rootScope 静止不动
    // 就形成死锁：按任何方向键都没反应。这里在按键层做一次兜底落焦。
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    TvFocusController.instance.scheduleEnsureFocus();
    // 冷启动首帧常常还没有任何可聚焦控件，_apply 会因候选为空提前返回，
    // 焦点就一直停在整页根节点上（实测首键 DOWN/UP 无反应、RIGHT 能动）。
    // 应用稳定后再做一次幂等落焦：焦点已有效时 ensureValidFocus 不改动，
    // 不会抢播放页控制栏或用户已经操作的焦点。
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (mounted) TvFocusController.instance.ensureValidFocus();
    });
  }

  static TraversalDirection? _directionOf(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowUp) return TraversalDirection.up;
    if (key == LogicalKeyboardKey.arrowDown) return TraversalDirection.down;
    if (key == LogicalKeyboardKey.arrowLeft) return TraversalDirection.left;
    if (key == LogicalKeyboardKey.arrowRight) return TraversalDirection.right;
    return null;
  }

  /// 方向键兜底：统一驱动所有页面的方向键，不依赖 Shortcuts 从
  /// primaryFocus.context 向上查找 Actions。
  ///
  /// 播放页曾注册页面级 Shortcuts/Actions 接管（只处理控制栏），一旦放行
  /// 给它，抽屉 / 对话框里的焦点不在控制栏，那个 Action 返回 ignored 把
  /// 按键吞掉，抽屉就完全不能用遥控器操作（实测歌词显示设置抽屉 6 帧不动）。
  /// 现在这里接管全部：输入框放行给框架做光标、设置滑块交给滑块处理器、
  /// 其余走几何导航（上下键同区优先、边界溢出），并吞掉按键避免页面级
  /// Action 二次驱动。
  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final direction = _directionOf(event.logicalKey);
    if (direction == null) return false;

    final manager = FocusManager.instance;
    final focus = manager.primaryFocus;
    // 1) 输入框方向键交给框架做光标移动，不能吞。
    if (TvFocusController.isEditableFocus(focus)) return false;

    final valid = focus != null &&
        focus != manager.rootScope &&
        TvFocusController.isValidFocus(focus);
    if (!valid) {
      // 2) 焦点落空 / 不可见：同步落焦到第一个可见控件，只落位不移动。
      TvFocusController.instance.restoreFocusNow();
      return true;
    }

    // 3) 设置类滑块：调值方向交给滑块，离开方向由滑块自己调几何导航。
    if (TvFocusController.instance.handleSliderKey(direction, focus)) {
      TvFocusController.instance.restoreFocusNow();
      return true;
    }

    // 4) 几何导航（严格 + relaxed 两次）。上下键「同区优先、边界溢出」：
    //    区域内有候选时不跨区，走到边界才允许跨到相邻层。
    if (!TvFocusController.instance.moveFocus(
      direction,
      focus,
      lockZone: true,
    )) {
      TvFocusController.instance.moveFocus(
        direction,
        focus,
        relaxed: true,
        lockZone: true,
      );
    }
    TvFocusController.instance.restoreFocusNow();
    return true;
  }

  void _guardPrimaryFocus() {
    // 焦点落空、落到不可见节点或整页级容器时都要恢复：否则下一次 OK 会激活
    // 树里残留的旧页面按钮，实测会弹出「已收藏 / 已取消收藏」。
    if (!TvFocusController.isValidFocus(FocusManager.instance.primaryFocus)) {
      TvFocusController.instance.restoreFocusNow();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    FocusManager.instance.removeListener(_guardPrimaryFocus);
    super.dispose();
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
