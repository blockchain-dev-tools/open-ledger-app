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

    return Text(message, style: TextStyle(color: c.error, fontSize: 14));
  }
}
