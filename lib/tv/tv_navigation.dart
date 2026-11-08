import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

      // 抽屉不是 Navigator route：navigator.maybePop() 会被 AppShell 的
      // PopScope(canPop:false) 拦成空操作，必须显式关闭，效果等同抽屉的 ✕。
      if (_closeOpenDrawer()) return;

      final navigator = tvRootNavigatorKey.currentState;
      if (navigator == null) {
        await SystemNavigator.pop();
        return;
      }

      // 用 popCount 判断「真的关掉了一个 route」。PopScope 拦截 maybePop
      // 时不会触发 didPop，所以不能依赖 maybePop 的返回值。
      final before = TvFocusNavigatorObserver.popCount;
      await navigator.maybePop();
      if (TvFocusNavigatorObserver.popCount > before) return;

      // 已在主界面：按 Android TV 惯例返回电视桌面。
      await SystemNavigator.pop();
    } finally {
      _handling = false;
    }
  }

  static bool _closeOpenDrawer() {
    final scaffold = tvScaffoldKey.currentState;
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
