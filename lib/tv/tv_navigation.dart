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

  // Android KEYCODE_BACK 走 PopScope，手柄 B / 键盘 Esc 走输入事件通道。
  // 同一时间窗内只处理一次，避免两种通道同时到达时出现双跳。
  static Future<void> handle() async {
    final now = DateTime.now();
    final last = _lastHandled;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 320)) {
      return;
    }
    _lastHandled = now;

    // 音量竖条等 OverlayEntry 不是 Navigator route，返回键先关它们。
    if (TvOverlayRegistry.instance.closeTop()) return;

    final navigator = tvRootNavigatorKey.currentState;
    if (navigator == null) return;

    // 抽屉、对话框、播放页都是 Navigator 上的 route，优先逐级关闭。
    final popped = await navigator.maybePop();
    if (popped) return;

    // 已在主界面：按 Android TV 惯例返回电视桌面。
    await SystemNavigator.pop();
  }
}
