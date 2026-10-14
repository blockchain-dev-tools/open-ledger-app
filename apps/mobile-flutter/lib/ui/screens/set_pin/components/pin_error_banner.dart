import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';

/// The inline error line shown under the PIN dots on a mismatch or failure.
class PinErrorBanner extends StatelessWidget {
  final String message;

  const PinErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    // Dark keeps the original loose red line untouched.
    if (!c.neobrutalism) {
      return Text(message, style: TextStyle(color: c.error, fontSize: 14));
    }

    // Light draws the message as an outlined pastel chip so it reads as a hard
    // neo block rather than loose text.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.error.withAlpha(30),
        borderRadius: BorderRadius.circular(Neo.radius),
        border: Border.all(color: c.neoEdge, width: Neo.edge),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: c.error,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
