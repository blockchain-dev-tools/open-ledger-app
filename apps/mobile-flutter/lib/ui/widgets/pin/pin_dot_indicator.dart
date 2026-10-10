import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';

/// A row of circular PIN indicator dots.
///
/// Shows [length] dots; the first [filledCount] are filled with the primary
/// color, the rest are empty (surface fill with border outline).
///
/// Shared by [SetPinScreen], [UnlockScreen], and [BackupSeedScreen].
///
/// ```dart
/// PinDotIndicator(length: 6, filledCount: _pin.length)
/// ```
class PinDotIndicator extends StatelessWidget {
  /// Total number of dots to display.
  ///
  /// Default: 6 (standard 6-digit PIN).
  final int length;

  /// Number of dots to display as filled.
  final int filledCount;

  /// The diameter of each dot in logical pixels.
  ///
  /// Default: 16.
  final double dotSize;

  /// Horizontal margin between adjacent dots.
  ///
  /// Default: 6.
  final double dotMargin;

  /// Border width of each dot.
  ///
  /// Default: 2.
  final double borderWidth;

  const PinDotIndicator({
    super.key,
    required this.length,
    required this.filledCount,
    this.dotSize = 16.0,
    this.dotMargin = 6.0,
    this.borderWidth = 2.0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (i) {
        final filled = i < filledCount;
        return Container(
          margin: EdgeInsets.symmetric(horizontal: dotMargin),
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? c.primary : c.surface,
            border: Border.all(
              color: filled ? c.primary : c.border,
              width: borderWidth,
            ),
          ),
        );
      }),
    );
  }
}
