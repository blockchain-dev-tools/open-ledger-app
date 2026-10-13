import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';

/// Paints the reference grid from neobrutalism.dev behind [child]: 1px rules on
/// both axes every [Neo.gridStep], in [ColorTokens.gridLine].
///
/// Light-mode chrome only, like the rest of the neo language — when
/// [ColorTokens.neobrutalism] is false [child] is returned untouched, so dark
/// keeps its plain background.
///
/// The painter runs behind [child], so whatever the child paints opaque on top
/// (cards, the tab bar) covers the grid. Wrap the body rather than the whole
/// `Scaffold` — the grid then stays put while a list inside it scrolls.
class GridBackground extends StatelessWidget {
  final Widget child;

  const GridBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    if (!c.neobrutalism) return child;

    return CustomPaint(
      painter: _GridPainter(color: c.gridLine, step: Neo.gridStep),
      child: child,
    );
  }
}

class _GridPainter extends CustomPainter {
  final Color color;
  final double step;

  const _GridPainter({required this.color, required this.step});

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color
      ..strokeWidth = 1;

    // The half-pixel offset puts the 1px stroke on a device-pixel centre
    // instead of straddling two, which is what keeps it a crisp hairline at
    // 1×, 2× and 3× device pixel ratios.
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x + 0.5, 0), Offset(x + 0.5, size.height), line);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y + 0.5), Offset(size.width, y + 0.5), line);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.step != step;
}
