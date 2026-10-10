import 'package:flutter/material.dart';

/// Wraps a child widget with a horizontal shake animation when [shaking]
/// is `true`.
///
/// The animation uses [TweenAnimationBuilder] with an elastic-out curve,
/// translating horizontally from 8px back to 0 over 300ms.
///
/// Shared by [SetPinScreen], [UnlockScreen], and [BackupSeedScreen].
///
/// ```dart
/// PinShakeWrapper(
///   shaking: _shaking,
///   child: PinDotIndicator(length: 6, filledCount: _pin.length),
/// )
/// ```
class PinShakeWrapper extends StatelessWidget {
  /// Whether the shake animation is active.
  final bool shaking;

  /// The widget to animate.
  final Widget child;

  const PinShakeWrapper({
    super.key,
    required this.shaking,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(
        begin: shaking ? 8.0 : 0.0,
        end: 0.0,
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.elasticOut,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(value, 0),
          child: child,
        );
      },
      child: child,
    );
  }
}
