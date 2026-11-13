import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 把「整棵 UI 树被 Transform.scale 视觉缩放的倍数」传给后代。
///
/// 普通 Android / 电视盒子的 `_AndroidUiScaler`、真 TV 的 `TvUiScaler` 都是
/// 先在一个更大的逻辑画布上布局，再整体 `Transform.scale` 缩回去。这会让
/// 播放页里所有按 `scale` 计算的字号 / 封面 / 图标在视觉上再乘一次缩放系数，
/// 结果比桌面端明显偏小（0.72 倍缩放时约小 28%），控件栏也显得过细。
///
/// 播放页通过 [playPageScale] 做反向补偿即可恢复桌面端的视觉尺寸；其它页面
/// 不读取这个值，行为完全不变。桌面端没有这个节点，[of] 返回 1.0。
class UiScaleScope extends InheritedWidget {
  const UiScaleScope({
    super.key,
    required this.visualScale,
    required super.child,
  });

  /// 视觉缩放倍数：<1 表示整棵树被缩小，>1 表示被放大。
  final double visualScale;

  static double of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<UiScaleScope>();
    return scope?.visualScale ?? 1.0;
  }

  @override
  bool updateShouldNotify(UiScaleScope oldWidget) =>
      oldWidget.visualScale != visualScale;
}

/// 播放页专用布局缩放系数。
///
/// 与桌面端原版一致：按窗口面积相对 1150x620 基准开方缩放，保证任意分辨率
/// 下都能平滑过渡、不会出现跳变或溢出；再除以 [UiScaleScope] 暴露的视觉缩放，
/// 抵消 Android 全局缩放对固定尺寸的二次缩小。
///
/// 例：960x540 物理屏 + 0.72 全局缩放 -> base 0.853 / 0.72 = 1.185，
/// 封面 310*1.185 逻辑像素经 0.72 视觉缩放后 = 264px，与桌面端 264px 一致。
double playPageScale(BuildContext context) {
  final size = MediaQuery.of(context).size;
  final double width = size.width > 0 ? size.width : 1150.0;
  final double height = size.height > 0 ? size.height : 620.0;
  // 上限锁 1.0：1080p 电视按面积算会到 ~1.7，把封面 / 标题 / 歌词一起
  // 放大近 1.7 倍，明显大于桌面端 1150x620 基准（真机对比图里 TV 侧字号
  // 偏大的主因）。桌面窗口小于基准时仍按面积缩小，大于基准时不再继续放大。
  final double base = (math.sqrt(
    (width * height) / (1150.0 * 620.0),
  )).clamp(0.5, 1.0);
  final double visual = UiScaleScope.of(context).clamp(0.5, 1.5);
  return (base / visual).clamp(0.5, 3.0);
}
