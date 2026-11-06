import 'package:flutter/material.dart';

class AndroidUiScaleScope extends InheritedWidget {
  const AndroidUiScaleScope({required this.scale, required super.child});

  final double scale;

  static double? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AndroidUiScaleScope>()
        ?.scale;
  }

  @override
  bool updateShouldNotify(AndroidUiScaleScope oldWidget) =>
      oldWidget.scale != scale;
}

class AndroidUiScaler extends StatelessWidget {
  const AndroidUiScaler({required this.child, required this.scale});

  final Widget child;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 在更大的逻辑画布上布局，再整体视觉缩小。这样不需要修改系统 DPI，
        // 固定的桌面字号/尺寸也会按同一比例变小，且点击坐标随变换一起缩放。
        final effectiveScale = scale.clamp(0.55, 1.0);
        final virtualWidth = constraints.maxWidth / effectiveScale;
        final virtualHeight = constraints.maxHeight / effectiveScale;
        return SizedBox.expand(
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: virtualWidth,
              maxWidth: virtualWidth,
              minHeight: virtualHeight,
              maxHeight: virtualHeight,
              child: Transform.scale(
                scale: effectiveScale,
                alignment: Alignment.topLeft,
                transformHitTests: true,
                child: SizedBox(
                  width: virtualWidth,
                  height: virtualHeight,
                  child: AndroidUiScaleScope(scale: effectiveScale, child: child),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 对已经自行按窗口尺寸计算 scale 的全屏页面（如播放页）撤销一次全局缩放，
/// 避免两次 scale 叠加导致元素过小、命中区域与视觉位置错位。
class AndroidScaleCompensator extends StatelessWidget {
  const AndroidScaleCompensator({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scale = AndroidUiScaleScope.maybeOf(context);
    if (scale == null || scale >= 1.0) return child;
    return OverflowBox(
      alignment: Alignment.topLeft,
      minWidth: MediaQuery.of(context).size.width / scale,
      maxWidth: MediaQuery.of(context).size.width / scale,
      minHeight: MediaQuery.of(context).size.height / scale,
      maxHeight: MediaQuery.of(context).size.height / scale,
      child: Transform.scale(
        scale: 1.0 / scale,
        alignment: Alignment.topLeft,
        transformHitTests: true,
        child: SizedBox(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          child: child,
        ),
      ),
    );
  }
}

