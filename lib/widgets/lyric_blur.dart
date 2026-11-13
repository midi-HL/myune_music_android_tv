import 'dart:math' as math;

import 'package:flutter/widgets.dart';

// 单个 Shadow 的 blurRadius 与真实高斯 sigma 的近似换算系数。
// 性能优先：歌词模糊始终只用**一层** Shadow，不使用 ImageFilter.blur
// 之类的真高斯模糊（画面动态时每帧重算，弱电视扛不住）。
// 原实现还有「sigma <= 0.5 折成 0」的死区，导致刚离开当前行的歌词
// 完全不糊；这里去掉死区、给一个最小柔化半径，只是数值改动，无额外绘制。
const double _kRadiusToSigmaFactor = 0.57735;

// 最小可见半径：即使刚离开当前行，也要有一层轻微柔化。
const double _kMinVisibleRadius = 1.6;

const Duration kLyricBlurTransitionDuration = Duration(milliseconds: 240);

const Curve kLyricBlurTransitionCurve = Curves.easeOutCubic;

// 量化步长调粗：sigma 每变化 1/8 才重建一次，减少换行时的补间重建次数，
// 在弱设备上滚动 / 切行更流畅；视觉上几乎无差别。
const double _kSigmaGridPerUnit = 8.0;

double quantizeLyricBlurSigma(double sigma) =>
    (sigma * _kSigmaGridPerUnit).roundToDouble() / _kSigmaGridPerUnit;

TextStyle buildLyricTextStyle({
  required Color lineColor,
  required double fontSize,
  required FontWeight fontWeight,
  required double blurSigma,
}) {
  final double radius = lyricShadowRadiusForSigma(blurSigma);
  if (radius > 0.0) {
    // 单层 Shadow。曾试过三层叠加模拟高斯，但每个阴影都要额外一次
    // 模糊绘制，在四核 1+4G 电视上会明显掉帧；性能优先，保持单层。
    return TextStyle(
      fontSize: fontSize,
      height: 1.2,
      color: const Color(0x00000000),
      shadows: <Shadow>[Shadow(color: lineColor, blurRadius: radius)],
      fontWeight: fontWeight,
    );
  }
  return TextStyle(
    fontSize: fontSize,
    height: 1.2,
    color: lineColor,
    fontWeight: fontWeight,
  );
}

/// sigma -> Shadow.blurRadius。只要有 sigma 就给一层最小柔化，
/// 不再出现「distance 近的行完全不模糊」的断层。
double lyricShadowRadiusForSigma(double sigma) {
  if (sigma <= 0.0) return 0.0;
  return math.max(
    _kMinVisibleRadius,
    (sigma + 0.6) / _kRadiusToSigmaFactor,
  );
}

class AnimatedLyricBlur extends StatelessWidget {
  const AnimatedLyricBlur({
    super.key,
    required this.targetSigma,
    required this.builder,
    this.duration = kLyricBlurTransitionDuration,
    this.curve = kLyricBlurTransitionCurve,
  });

  final double targetSigma;

  /// 用当前显示中的 sigma 构建内容
  final Widget Function(double sigma) builder;

  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: targetSigma, end: targetSigma),
      duration: duration,
      curve: curve,
      builder: (BuildContext context, double sigma, Widget? _) =>
          builder(quantizeLyricBlurSigma(sigma)),
    );
  }
}
