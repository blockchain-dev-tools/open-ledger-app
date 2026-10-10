import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';

/// A full-width primary action button with consistent theming.
///
/// Unifies the scattered button implementations across screens — some used
/// [ElevatedButton], others [GestureDetector] + [Container], with
/// inconsistent sizing and color logic.
///
/// Supports:
/// - Normal / disabled states (via `onTap == null`)
/// - Loading spinner
/// - Outline style (for destructive / secondary actions)
///
/// ```dart
/// PrimaryButton(label: 'Continue', onTap: _onContinue)
/// PrimaryButton(label: 'Reject', onTap: _onReject, outline: true, outlineColor: c.error)
/// ```
class PrimaryButton extends StatelessWidget {
  /// The button label text.
  final String label;

  /// Called when the button is tapped.
  ///
  /// When `null`, the button renders in a disabled style.
  final VoidCallback? onTap;

  /// Button height in logical pixels.
  ///
  /// Default: 52.
  final double height;

  /// When `true`, shows a [CircularProgressIndicator] instead of [label].
  final bool loading;

  /// Background color when enabled.
  ///
  /// Default: [ColorTokens.dark.primary].
  final Color? backgroundColor;

  /// Text color when enabled.
  ///
  /// Default: [ColorTokens.dark.onPrimary].
  final Color? textColor;

  /// When `true`, renders as an outline button (transparent background,
  /// colored border) suitable for secondary or destructive actions.
  final bool outline;

  /// Border color for outline mode.
  ///
  /// Default: [ColorTokens.dark.border].
  final Color? outlineColor;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onTap,
    this.height = 52.0,
    this.loading = false,
    this.backgroundColor,
    this.textColor,
    this.outline = false,
    this.outlineColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final enabled = onTap != null && !loading;

    final bg = outline
        ? Colors.transparent
        : (enabled ? (backgroundColor ?? c.primary) : c.surface);
    final border = outline
        ? Border.all(color: outlineColor ?? c.border, width: 1.5)
        : (enabled ? null : Border.all(color: c.border));
    final fg = enabled
        ? (textColor ?? (outline ? (outlineColor ?? c.primary) : c.onPrimary))
        : c.text.withAlpha(80);

    return SizedBox(
      width: double.infinity,
      height: height,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(R.lg),
            border: border,
          ),
          alignment: Alignment.center,
          child: loading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: fg,
                  ),
                )
              : Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}
