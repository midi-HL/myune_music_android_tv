import 'package:flutter/material.dart';

/// Android 应用内密度调节。
///
/// 不包裹 Transform、不修改 MediaQuery.size / devicePixelRatio / viewInsets：
/// 那些值分别决定布局尺寸、物理像素换算与系统安全区，改动会造成黑边、
/// 拖拽浮层坐标漂移和命中错位。这里只通过 Navigator 上方的 Theme 与文本
/// 缩放影响所有页面、Dialog、Drawer 和 Overlay。
class AndroidUiScaler extends StatelessWidget {
  const AndroidUiScaler({required this.child, required this.scale, super.key});

  final Widget child;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final effectiveScale = scale.clamp(0.85, 1.15);
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final densityOffset = (effectiveScale - 1.0) * 2.0;
    final scaledTheme = theme.copyWith(
      visualDensity: VisualDensity(
        horizontal: densityOffset,
        vertical: densityOffset,
      ),
    );

    return Theme(
      data: scaledTheme,
      child: MediaQuery(
        data: media.copyWith(
          textScaler: TextScaler.linear(effectiveScale),
        ),
        child: child,
      ),
    );
  }
}
