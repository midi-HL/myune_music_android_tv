import 'package:flutter/material.dart';

import '../widgets/ui_scale_scope.dart';

// TV 分支专用缩放：默认 1.0（不缩放），范围 0.8~1.3。
// 与手机端的 0.72 缩放完全隔离，互不影响。
//
// 说明：早期版本里的 TvSafeArea（过扫描安全边距）、TvFocusTraversalGroup、
// TvFocusFrame 和 applyTvFocusTheme 已按真机回归结论移除：
// - 标准 Android TV 不需要应用内过扫描留白；
// - Material / Android 原生已有自己的焦点高亮，再叠加自定义主题与全局
//   焦点框会造成双重高亮、整页被框住。
class TvUiScaler extends StatelessWidget {
  const TvUiScaler({required this.child, required this.scale, super.key});

  final Widget child;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final effective = scale.clamp(0.8, 1.3);
        final virtualWidth = constraints.maxWidth / effective;
        final virtualHeight = constraints.maxHeight / effective;
        return SizedBox.expand(
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: virtualWidth,
              maxWidth: virtualWidth,
              minHeight: virtualHeight,
              maxHeight: virtualHeight,
              child: UiScaleScope(
                visualScale: effective,
                child: Transform.scale(
                  scale: effective,
                  alignment: Alignment.topLeft,
                  transformHitTests: true,
                  child: SizedBox(
                    width: virtualWidth,
                    height: virtualHeight,
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
