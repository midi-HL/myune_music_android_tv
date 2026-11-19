import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../layout/navigation_notifier.dart';
import 'tv_focus_nav.dart';

// 根 Navigator 与 Scaffold 的全局键：输入层不依赖页面 context 即可
// 打开播放队列、播放页，或处理返回键。
final GlobalKey<NavigatorState> tvRootNavigatorKey =
    GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldState> tvScaffoldKey = GlobalKey<ScaffoldState>();

class TvBackHandler {
  TvBackHandler._();

  static DateTime? _lastHandled;
  static bool _handling = false;
  static final Map<String, bool Function()> _pageHandlers = {};

  static void registerPageHandler(String route, bool Function() handler) {
    _pageHandlers[route] = handler;
  }

  static void unregisterPageHandler(String route, bool Function() handler) {
    if (identical(_pageHandlers[route], handler)) _pageHandlers.remove(route);
  }

  static void openQueue() {
    if (TvFocusNavigatorObserver.currentRoute is PopupRoute) return;
    final focused = FocusManager.instance.primaryFocus;
    final contexts = <BuildContext>[
      if (focused?.context != null &&
          TvFocusController.rectOf(focused!) != null) focused!.context!,
      ...TvFocusController.focusableContexts(),
    ];
    for (final context in contexts) {
      final scaffold = Scaffold.maybeOf(context);
      if (scaffold != null && scaffold.widget.endDrawer != null) {
        scaffold.openEndDrawer();
        return;
      }
    }
    if (TvFocusNavigatorObserver.currentRoute?.isFirst ?? true) {
      tvScaffoldKey.currentState?.openEndDrawer();
    }
  }

  // Android KEYCODE_BACK 走 PopScope，手柄 B / 键盘 Esc 走输入事件通道。
  // 同一时间窗内只处理一次，避免两种通道同时到达时出现双跳。
  static Future<void> handle() async {
    if (_handling) return;
    final now = DateTime.now();
    final last = _lastHandled;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 320)) {
      return;
    }
    _lastHandled = now;
    _handling = true;
    try {
      // 音量竖条等 OverlayEntry 不是 Navigator route，返回键先关它们。
      if (TvOverlayRegistry.instance.closeTop()) return;

      final navigator = tvRootNavigatorKey.currentState;
      if (navigator == null) {
        await SystemNavigator.pop();
        return;
      }
      // 抽屉上方的确认对话框必须先关闭，避免先关掉其背后的抽屉。
      if (TvFocusNavigatorObserver.currentRoute is PopupRoute) {
        await navigator.maybePop();
        return;
      }
      // showMenu 默认使用内容页的内层 Navigator，不在根观察器的路由栈里。
      final focusedContext = FocusManager.instance.primaryFocus?.context;
      for (final context in <BuildContext>[
        if (focusedContext != null) focusedContext,
        ...TvFocusController.focusableContexts(),
      ]) {
        final route = ModalRoute.of(context);
        if (route is PopupRoute && route.isCurrent && route.navigator != null) {
          await route.navigator!.maybePop();
          return;
        }
      }
      if (_closeOpenDrawer()) return;
      if (navigator.canPop()) {
        // 尊重当前 route 自己的 PopScope；即使它阻止退出，也不退出应用。
        await navigator.maybePop();
        return;
      }
      final navigation = navigator.context.read<NavigationNotifier>();
      if (_pageHandlers[navigation.currentRoute]?.call() ?? false) return;
      if (navigation.canPop) {
        navigation.popRoute();
        TvFocusController.instance.scheduleRestoreFocus();
        return;
      }

      // 已在主界面：按 Android TV 惯例返回电视桌面。
      await SystemNavigator.pop();
    } finally {
      _handling = false;
    }
  }

  static bool _closeOpenDrawer() {
    final rootIsCurrent =
        TvFocusNavigatorObserver.currentRoute?.isFirst ?? true;
    final scaffold = rootIsCurrent ? tvScaffoldKey.currentState : null;
    if (scaffold != null) {
      if (scaffold.isEndDrawerOpen) {
        scaffold.closeEndDrawer();
        TvFocusController.instance.scheduleRestoreFocus();
        return true;
      }
      if (scaffold.isDrawerOpen) {
        scaffold.closeDrawer();
        TvFocusController.instance.scheduleRestoreFocus();
        return true;
      }
    }
    // 播放页 / 其它页面自己 Scaffold 上的歌词设置抽屉：从焦点树里找到
    // Drawer 内的 context，再取它所属的 ScaffoldState 关闭。
    for (final context in TvFocusController.focusableContexts()) {
      if (context.findAncestorWidgetOfExactType<Drawer>() == null) continue;
      final state = Scaffold.maybeOf(context);
      if (state == null) continue;
      if (state.isEndDrawerOpen) {
        state.closeEndDrawer();
        TvFocusController.instance.scheduleRestoreFocus();
        return true;
      }
      if (state.isDrawerOpen) {
        state.closeDrawer();
        TvFocusController.instance.scheduleRestoreFocus();
        return true;
      }
    }
    return false;
  }
}
