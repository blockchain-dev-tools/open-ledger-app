import 'package:flutter/material.dart';

import '../../../widgets/pin/pin_dot_indicator.dart';
import '../../../widgets/pin/pin_shake_wrapper.dart';

/// The row of PIN indicator dots, wrapped in the shake animation that fires on
/// a mismatch.
class PinDots extends StatelessWidget {
  /// Whether the shake animation is currently active.
  final bool shaking;

  /// Total number of dots to display.
  final int length;

  /// Number of dots to display as filled.
  final int filledCount;

  const PinDots({
    super.key,
    required this.shaking,
    required this.length,
    required this.filledCount,
  });

  @override
  Widget build(BuildContext context) {
    return PinShakeWrapper(
      shaking: shaking,
      child: PinDotIndicator(length: length, filledCount: filledCount),
    );
  }
}
