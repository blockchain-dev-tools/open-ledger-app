import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';

/// A 3×4 number pad grid (1–9, empty, 0, backspace) for PIN entry.
///
/// Shared by [SetPinScreen], [UnlockScreen], and [BackupSeedScreen].
/// All three previously had near-identical implementations; this widget
/// unifies them with configurable sizing and key prefixes.
///
/// ```dart
/// PinNumberPad(
///   onDigit: (d) => _onDigitTap(d),
///   onBackspace: _onBackspaceTap,
///   keyPrefix: 'pin',
///   disabled: _lockedOut,
/// )
/// ```
class PinNumberPad extends StatelessWidget {
  /// Called when a digit button (0–9) is tapped.
  final void Function(int digit) onDigit;

  /// Called when the backspace button is tapped.
  final VoidCallback onBackspace;

  /// Prefix for widget keys: `$keyPrefix-btn-$digit` and `$keyPrefix-backspace`.
  ///
  /// Defaults to `'pin'`.
  final String keyPrefix;

  /// When `true`, all buttons are non-interactive (no callbacks invoked).
  final bool disabled;

  /// The width/height of each number pad button in logical pixels.
  ///
  /// Default: 72.
  final double buttonSize;

  /// Horizontal and vertical spacing between buttons.
  ///
  /// Default: 12.
  final double spacing;

  const PinNumberPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.keyPrefix = 'pin',
    this.disabled = false,
    this.buttonSize = 72.0,
    this.spacing = 12.0,
  });

  @override
  Widget build(BuildContext context) {
    // Layout: 3 columns, 4 rows
    //   Row 1: 1  2  3
    //   Row 2: 4  5  6
    //   Row 3: 7  8  9
    //   Row 4: -  0  ⌫
    return SizedBox(
      width: buttonSize * 3 + spacing * 2,
      child: Wrap(
        spacing: spacing,
        runSpacing: spacing,
        alignment: WrapAlignment.center,
        children: [
          // Rows 1-3: digits 1–9
          for (int i = 1; i <= 9; i++)
            _NumButton(
              digit: i,
              size: buttonSize,
              keyPrefix: keyPrefix,
              onTap: disabled ? null : () => onDigit(i),
            ),

          // Row 4: empty spacer, 0, backspace
          SizedBox(width: buttonSize, height: buttonSize),
          _NumButton(
            digit: 0,
            size: buttonSize,
            keyPrefix: keyPrefix,
            onTap: disabled ? null : () => onDigit(0),
          ),
          _BackspaceButton(
            size: buttonSize,
            keyPrefix: keyPrefix,
            onTap: disabled ? null : onBackspace,
          ),
        ],
      ),
    );
  }
}

/// A single digit button in the number pad.
class _NumButton extends StatelessWidget {
  final int digit;
  final double size;
  final String keyPrefix;
  final VoidCallback? onTap;

  const _NumButton({
    required this.digit,
    required this.size,
    required this.keyPrefix,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return GestureDetector(
      key: ValueKey('$keyPrefix-btn-$digit'),
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: c.border.withAlpha(100)),
        ),
        alignment: Alignment.center,
        child: Text(
          '$digit',
          style: TextStyle(
            color: c.text,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// The backspace / delete button in the number pad.
class _BackspaceButton extends StatelessWidget {
  final double size;
  final String keyPrefix;
  final VoidCallback? onTap;

  const _BackspaceButton({
    required this.size,
    required this.keyPrefix,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return GestureDetector(
      key: Key('$keyPrefix-backspace'),
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: c.border.withAlpha(100)),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.backspace_outlined,
          size: 28,
          color: c.text.withAlpha(180),
        ),
      ),
    );
  }
}
