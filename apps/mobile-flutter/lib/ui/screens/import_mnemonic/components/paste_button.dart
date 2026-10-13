import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';

/// Full-width "paste from clipboard" action for the import-mnemonic screen.
class PasteButton extends StatelessWidget {
  final VoidCallback onPressed;

  const PasteButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const Key('paste-btn'),
        onPressed: onPressed,
        icon: Icon(Icons.content_paste, size: 18, color: c.primary),
        label: Text(
          l10n.pasteFromClipboard,
          style: TextStyle(
            color: c.primary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: c.primary.withAlpha(100)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.lg),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}
