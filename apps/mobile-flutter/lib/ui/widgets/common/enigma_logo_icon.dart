import 'package:flutter/material.dart';

/// Enigma wallet logo icon — pen nib (left) + vertical key (right), no frame.
/// Renders at any size; strokes scale with [size].
///
/// Geometry is defined on a 24×24 design grid and scaled via [size].
class EnigmaLogoIcon extends StatelessWidget {
  final Color color;
  final double size;
  final double strokeWidth;

  const EnigmaLogoIcon({
    super.key,
    required this.color,
    this.size = 24,
    this.strokeWidth = 1.6,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _EnigmaLogoPainter(
          color: color,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _EnigmaLogoPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _EnigmaLogoPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24; // scale from 24×24 design grid
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Pen nib (left): diamond, compact and pulled toward the key
    final nib = Path()
      ..moveTo(9.1 * s, 7.4 * s)
      ..lineTo(11.3 * s, 12 * s)
      ..lineTo(9.1 * s, 16.6 * s)
      ..lineTo(6.9 * s, 12 * s)
      ..close();
    canvas.drawPath(nib, paint);

    // Nib centerline M9.1 12 L9.1 16.6
    canvas.drawLine(
      Offset(9.1 * s, 12 * s),
      Offset(9.1 * s, 16.6 * s),
      paint,
    );

    // Key bow (top ring): circle cx=14.9 cy=8.6 r=1.9
    canvas.drawCircle(
      Offset(14.9 * s, 8.6 * s),
      1.9 * s,
      paint,
    );

    // Key shaft M14.9 10.5 V16.6
    canvas.drawLine(
      Offset(14.9 * s, 10.5 * s),
      Offset(14.9 * s, 16.6 * s),
      paint,
    );

    // Key tooth 1 (mid) M14.9 12.9 H16.6
    canvas.drawLine(
      Offset(14.9 * s, 12.9 * s),
      Offset(16.6 * s, 12.9 * s),
      paint,
    );

    // Key tooth 2 (bottom) M14.9 16.6 H17.1
    canvas.drawLine(
      Offset(14.9 * s, 16.6 * s),
      Offset(17.1 * s, 16.6 * s),
      paint,
    );
  }

  @override
  bool shouldRepaint(_EnigmaLogoPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
