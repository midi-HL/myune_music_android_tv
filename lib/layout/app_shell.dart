import 'package:flutter/material.dart';

import '../tv/tv_device.dart';
import '../tv/tv_navigation.dart';
import '../widgets/app_window_title_bar.dart';
import '../widgets/custom_background_layer.dart';
import 'main_view.dart';
import '../widgets/playbar.dart';
import '../widgets/playing_queue_drawer.dart';
import '../widgets/toast_overlay.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      key: tvScaffoldKey,
      backgroundColor: Colors.transparent,
      endDrawer: PlayingQueueDrawer(),
      body: Stack(
        children: [
          // 自定义背景图（未启用时为透明，不影响原有外观）
          Positioned.fill(child: CustomBackgroundImageLayer()),
          // 背景遮罩（普通遮罩 / 毛玻璃遮罩 / 无遮罩）
          // 未启用自定义背景图时该层会提供不透明的主题底色
          Positioned.fill(child: CustomBackgroundMaskLayer()),
          Material(
            color: Colors.transparent,
            child: Column(
              children: [
                AppWindowTitleBar(),
                Expanded(child: MainView()),
                Playbar(),
              ],
            ),
          ),
          ToastOverlay(),
        ],
      ),
    );

    // TV 上统一接管系统返回键：先逐级关闭抽屉 / 对话框 / 播放页，
    // 主界面再返回电视桌面。手机端行为完全不变。
    if (!TvDevice.isTv) return scaffold;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) TvBackHandler.handle();
      },
      child: scaffold,
    );
  }
}
