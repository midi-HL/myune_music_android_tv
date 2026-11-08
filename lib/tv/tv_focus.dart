import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 10-foot UI 的过扫描安全区：按屏幕比例留白，避免电视裁切边缘内容。
class TvSafeArea extends StatelessWidget {
  const TvSafeArea({
    required this.child,
    this.overscan = 0.05,
    super.key,
  });

  final Widget child;
  final double overscan;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final fraction = overscan.clamp(0.0, 0.1);
    final horizontal = media.size.width * fraction;
    final vertical = media.size.height * fraction;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical) +
          media.padding,
      child: MediaQuery.removePadding(
        context: context,
        removeLeft: true,
        removeRight: true,
        removeTop: true,
        removeBottom: true,
        child: child,
      ),
    );
  }
}

// TV 分支专用缩放：默认 1.0（不缩放），范围 0.8~1.3。
// 与手机端的 0.72 缩放完全隔离，互不影响。
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
        );
      },
    );
  }
}

class TvFocusTraversalGroup extends StatelessWidget {
  const TvFocusTraversalGroup({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: child,
    );
  }
}

// 给原本不可聚焦的控件（GestureDetector / 自定义 InkWell 等）补一层焦点。
class TvFocusFrame extends StatefulWidget {
  const TvFocusFrame({
    required this.child,
    this.onActivate,
    this.borderRadius = 10,
    super.key,
  });

  final Widget child;
  final VoidCallback? onActivate;
  final double borderRadius;

  @override
  State<TvFocusFrame> createState() => _TvFocusFrameState();
}

class _TvFocusFrameState extends State<TvFocusFrame> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Focus(
      onFocusChange: (value) {
        if (_focused != value) setState(() => _focused = value);
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && widget.onActivate != null) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter ||
              key == LogicalKeyboardKey.select) {
            widget.onActivate!();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: _focused
              ? Border.all(color: primary, width: 2.5)
              : Border.all(color: Colors.transparent, width: 2.5),
          color: _focused
              ? primary.withValues(alpha: 0.14)
              : Colors.transparent,
        ),
        child: widget.child,
      ),
    );
  }
}

// TV 分支的主题强化：让 Material 控件自带的焦点态在远距观看时清晰可见。
// 只覆盖焦点相关属性，配色与字号仍来自 ThemeProvider。
ThemeData applyTvFocusTheme(ThemeData base) {
  final primary = base.colorScheme.primary;
  final focusShape = WidgetStateProperty.resolveWith<OutlinedBorder?>((states) {
    if (states.contains(WidgetState.focused)) {
      return RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: primary, width: 2.5),
      );
    }
    return null;
  });
  final focusOverlay = WidgetStateProperty.resolveWith<Color?>((states) {
    if (states.contains(WidgetState.focused)) {
      return primary.withValues(alpha: 0.22);
    }
    return null;
  });
  final buttonStyle = ButtonStyle(
    shape: focusShape,
    overlayColor: focusOverlay,
  );
  return base.copyWith(
    focusColor: primary.withValues(alpha: 0.26),
    hoverColor: primary.withValues(alpha: 0.12),
    iconButtonTheme: IconButtonThemeData(style: buttonStyle),
    elevatedButtonTheme: ElevatedButtonThemeData(style: buttonStyle),
    filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle),
    textButtonTheme: TextButtonThemeData(style: buttonStyle),
    segmentedButtonTheme: SegmentedButtonThemeData(style: buttonStyle),
  );
}
