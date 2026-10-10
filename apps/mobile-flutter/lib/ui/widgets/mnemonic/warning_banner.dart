import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';

/// A red-tinted warning banner used to display security-sensitive messages.
///
/// Shared by [GenerateMnemonicScreen], [EnigmaMnemonicScreen], and
/// [BackupSeedScreen] — all three had near-identical implementations
/// with minor text content differences.
///
/// ```dart
/// WarningBanner(
///   message: 'Never share your seed phrase! Anyone with these words '
///            'can access your funds.',
/// )
/// ```
class WarningBanner extends StatelessWidget {
  /// The warning message text to display.
  final String message;

  /// The icon shown to the left of the message.
  ///
  /// Default: [Icons.warning_amber_rounded].
  final IconData icon;

  /// Icon size in logical pixels.
  ///
  /// Default: 22.
  final double iconSize;

  /// Text size in logical pixels.
  ///
  /// Default: 13.
  final double fontSize;

  /// Whether the text should be bold.
  ///
  /// Default: `false`.
  final bool bold;

  const WarningBanner({
    super.key,
    required this.message,
    this.icon = Icons.warning_amber_rounded,
    this.iconSize = 22.0,
    this.fontSize = 13.0,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: c.error.withAlpha(18),
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: c.error.withAlpha(60)),
      ),
      child: Row(
        children: [
          Icon(icon, color: c.error, size: iconSize),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: c.error,
                fontSize: fontSize,
                height: 1.4,
                fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
