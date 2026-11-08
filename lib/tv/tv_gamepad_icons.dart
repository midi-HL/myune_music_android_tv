import 'package:flutter/material.dart';

// 手柄图标只影响「显示」，不影响按键映射：Xbox 与 PlayStation 的
// A/B/X/Y 与 ✕/○/□/△ 在 Android 上共用同一组 BUTTON_* 键值。
enum TvGamepadIconStyle { auto, xbox, playStation }

enum TvGamepadButton { a, b, x, y, l1, r1, l2, r2, start, select }

const Map<TvGamepadIconStyle, String> tvGamepadIconStyleLabels =
    <TvGamepadIconStyle, String>{
      TvGamepadIconStyle.auto: '自动识别',
      TvGamepadIconStyle.xbox: 'Xbox',
      TvGamepadIconStyle.playStation: 'PlayStation',
    };

TvGamepadIconStyle tvGamepadIconStyleFromName(String? name) {
  for (final value in TvGamepadIconStyle.values) {
    if (value.name == name) return value;
  }
  return TvGamepadIconStyle.auto;
}

TvGamepadIconStyle resolveGamepadIconStyle(
  TvGamepadIconStyle preference,
  String deviceName,
) {
  if (preference != TvGamepadIconStyle.auto) return preference;
  final name = deviceName.toLowerCase();
  const psMarkers = <String>[
    'dualsense',
    'dualshock',
    'playstation',
    'sony',
    'wireless controller',
    'ps4',
    'ps5',
  ];
  for (final marker in psMarkers) {
    if (name.contains(marker)) return TvGamepadIconStyle.playStation;
  }
  return TvGamepadIconStyle.xbox;
}

String gamepadButtonLabel(
  TvGamepadButton button,
  TvGamepadIconStyle style,
) {
  final ps = style == TvGamepadIconStyle.playStation;
  switch (button) {
    case TvGamepadButton.a:
      return ps ? '✕' : 'A';
    case TvGamepadButton.b:
      return ps ? '○' : 'B';
    case TvGamepadButton.x:
      return ps ? '□' : 'X';
    case TvGamepadButton.y:
      return ps ? '△' : 'Y';
    case TvGamepadButton.l1:
      return ps ? 'L1' : 'LB';
    case TvGamepadButton.r1:
      return ps ? 'R1' : 'RB';
    case TvGamepadButton.l2:
      return ps ? 'L2' : 'LT';
    case TvGamepadButton.r2:
      return ps ? 'R2' : 'RT';
    case TvGamepadButton.start:
      return ps ? 'OPTIONS' : 'MENU';
    case TvGamepadButton.select:
      return ps ? 'SHARE' : 'VIEW';
  }
}

class TvGamepadGlyph extends StatelessWidget {
  const TvGamepadGlyph({
    required this.button,
    required this.style,
    this.size = 30,
    super.key,
  });

  final TvGamepadButton button;
  final TvGamepadIconStyle style;
  final double size;

  static const Color _xboxA = Color(0xFF5DBA47);
  static const Color _xboxB = Color(0xFFE0483C);
  static const Color _xboxX = Color(0xFF2E7DD1);
  static const Color _xboxY = Color(0xFFE9B629);

  bool get _isFaceButton =>
      button == TvGamepadButton.a ||
      button == TvGamepadButton.b ||
      button == TvGamepadButton.x ||
      button == TvGamepadButton.y;

  Color _xboxColor() {
    switch (button) {
      case TvGamepadButton.a:
        return _xboxA;
      case TvGamepadButton.b:
        return _xboxB;
      case TvGamepadButton.x:
        return _xboxX;
      case TvGamepadButton.y:
        return _xboxY;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPs = style == TvGamepadIconStyle.playStation;
    final accent = Theme.of(context).colorScheme.primary;

    if (!_isFaceButton) {
      return Container(
        height: size,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size / 2),
          border: Border.all(color: accent.withValues(alpha: 0.6)),
        ),
        child: Text(
          gamepadButtonLabel(button, style),
          style: TextStyle(fontSize: 11, color: accent),
        ),
      );
    }

    if (!isPs) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: _xboxColor(), shape: BoxShape.circle),
        child: Text(
          gamepadButtonLabel(button, style),
          style: const TextStyle(
            fontSize: 14,
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PsGlyphPainter(button: button, color: accent),
      ),
    );
  }
}

class _PsGlyphPainter extends CustomPainter {
  const _PsGlyphPainter({required this.button, required this.color});

  final TvGamepadButton button;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide * 0.34;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (button) {
      case TvGamepadButton.a:
        canvas.drawLine(
          Offset(center.dx - r, center.dy - r),
          Offset(center.dx + r, center.dy + r),
          paint,
        );
        canvas.drawLine(
          Offset(center.dx + r, center.dy - r),
          Offset(center.dx - r, center.dy + r),
          paint,
        );
        break;
      case TvGamepadButton.b:
        canvas.drawCircle(center, r, paint);
        break;
      case TvGamepadButton.x:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: center, width: r * 2, height: r * 2),
            const Radius.circular(2),
          ),
          paint,
        );
        break;
      case TvGamepadButton.y:
        final path = Path()
          ..moveTo(center.dx, center.dy - r)
          ..lineTo(center.dx + r, center.dy + r * 0.8)
          ..lineTo(center.dx - r, center.dy + r * 0.8)
          ..close();
        canvas.drawPath(path, paint);
        break;
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(_PsGlyphPainter oldDelegate) =>
      oldDelegate.button != button || oldDelegate.color != color;
}
