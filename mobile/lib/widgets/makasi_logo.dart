import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Le monogramme « M » de Makasi AI.
class MakasiLogo extends StatelessWidget {
  const MakasiLogo({
    super.key,
    this.size = 40,
    this.badge = true,
    this.glow = false,
  });

  final double size;
  final bool badge;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    if (!badge) {
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _MakasiGlyphPainter(useGradient: true)),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: MakasiTheme.gradient,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: MakasiTheme.brandMid.withValues(alpha: 0.38),
                  blurRadius: size * 0.55,
                  offset: Offset(0, size * 0.16),
                ),
              ]
            : null,
      ),
      child: CustomPaint(
        painter: _MakasiGlyphPainter(strokeWidth: size * 0.105),
      ),
    );
  }
}

class _MakasiGlyphPainter extends CustomPainter {
  _MakasiGlyphPainter({this.strokeWidth = 2.4, this.useGradient = false});

  final double strokeWidth;
  final bool useGradient;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.25, size.height * 0.72)
      ..lineTo(size.width * 0.25, size.height * 0.29)
      ..lineTo(size.width * 0.5, size.height * 0.56)
      ..lineTo(size.width * 0.75, size.height * 0.29)
      ..lineTo(size.width * 0.75, size.height * 0.72);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white;

    if (useGradient) {
      paint.shader = MakasiTheme.gradient.createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MakasiGlyphPainter oldDelegate) =>
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.useGradient != useGradient;
}
