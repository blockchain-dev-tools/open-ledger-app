import 'package:flutter/material.dart';

/// A lightweight, OKX-wallet-style toast.
///
/// Renders a dark, semi-transparent pill at the top-center of the screen,
/// hugging its content, with a green circle whose check mark is knocked out
/// (transparent) + short message. Slides down + fades in, then fades out
/// after [duration].
///
/// Unlike [SnackBar], this is overlay-based so it floats freely and never
/// stretches to full width or attaches to the scaffold edge.
///
/// ```dart
/// AppToast.show(context, message: 'Address copied');
/// ```
class AppToast {
  AppToast._();

  /// Shows a toast and returns immediately. The toast auto-dismisses.
  static void show(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(milliseconds: 1500),
  }) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastView(
        message: message,
        duration: duration,
        onDismiss: () {
          if (entry.mounted) entry.remove();
        },
      ),
    );
    overlay.insert(entry);
  }
}

class _ToastView extends StatefulWidget {
  final String message;
  final Duration duration;
  final VoidCallback onDismiss;

  const _ToastView({
    required this.message,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.35),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    _ctrl.forward();
    Future.delayed(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _ctrl.reverse();
    if (mounted) widget.onDismiss();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ignore pointer events so the toast never blocks taps behind it.
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          // Float below the status bar / app bar.
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 16,
          ),
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(217),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CustomPaint(
                      size: Size(16, 16),
                      painter: _KnockoutCheckPainter(Color(0xFF4CD964)),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a solid [color] circle with the check mark knocked out — the check
/// is a hole through which the dark pill background shows.
///
/// Uses [PathOperation.xor] (circle XOR check) rather than `BlendMode.clear`,
/// so the transparency is real geometry and renders identically on web,
/// mobile, and desktop without saveLayer quirks.
class _KnockoutCheckPainter extends CustomPainter {
  final Color color;

  const _KnockoutCheckPainter(this.color);

  // Material Icons.check glyph outline in a 24×24 box.
  static const List<(double, double)> _checkPoints24 = [
    (9.0, 16.17),
    (4.83, 12.0),
    (3.41, 13.41),
    (9.0, 19.0),
    (21.0, 7.0),
    (19.59, 5.59),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final circle = Path()
      ..addOval(Rect.fromCircle(center: Offset(r, r), radius: r));

    final scale = size.width / 24;
    final check = Path();
    for (var i = 0; i < _checkPoints24.length; i++) {
      final (x, y) = _checkPoints24[i];
      final px = x * scale;
      final py = y * scale;
      if (i == 0) {
        check.moveTo(px, py);
      } else {
        check.lineTo(px, py);
      }
    }
    check.close();

    // Check is fully inside the circle, so XOR leaves a check-shaped hole.
    final glyph = Path.combine(PathOperation.xor, circle, check);
    canvas.drawPath(glyph, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _KnockoutCheckPainter oldDelegate) =>
      oldDelegate.color != color;
}
