import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/color_tokens.dart';
import 'app_toast.dart';

/// A styled copy-to-clipboard button with icon, label, and success snackbar.
///
/// Used by [AccountDetailScreen].
///
/// On tap, copies [text] to the system clipboard and shows a snackbar with
/// [successMessage].
///
/// ```dart
/// CopyButton(
///   text: '0x742d35Cc6634C0532925a3b844Bc9e7595f0bD18',
///   label: 'Copy Address',
///   successMessage: 'Address copied',
/// )
/// ```
class CopyButton extends StatelessWidget {
  /// The text to copy to the system clipboard on tap.
  final String text;

  /// The button label text.
  ///
  /// Default: `'Copy'`.
  final String? label;

  /// Snackbar message shown after successful copy.
  ///
  /// Default: `'Copied'`.
  final String? successMessage;

  /// Button height in logical pixels.
  ///
  /// Default: 44 (compact row style).
  final double height;

  const CopyButton({
    super.key,
    required this.text,
    this.label,
    this.successMessage,
    this.height = 44.0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: text));
        AppToast.show(
          context,
          message: successMessage ?? 'Copied',
        );
      },
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: c.primary.withAlpha(30),
          borderRadius: BorderRadius.circular(R.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.copy, size: 16, color: c.primary),
            const SizedBox(width: 6),
            Text(
              label ?? 'Copy',
              style: TextStyle(
                color: c.primary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
