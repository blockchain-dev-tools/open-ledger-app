import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';

/// Row under the mnemonic input: word counter on the left, validation
/// indicator on the right (shown only once a check has run).
class MnemonicStatusRow extends StatelessWidget {
  final String wordCount;
  final bool hasChecked;
  final bool isValid;

  const MnemonicStatusRow({
    super.key,
    required this.wordCount,
    required this.hasChecked,
    required this.isValid,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;

    return Row(
      children: [
        // Word counter
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(color: c.border.withAlpha(100)),
          ),
          child: Text(
            l10n.wordsCount(int.parse(wordCount)),
            style: TextStyle(
              color: c.text.withAlpha(180),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),

        const Spacer(),

        // Validation indicator
        if (hasChecked)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isValid ? Icons.check_circle : Icons.cancel,
                size: 20,
                color: isValid ? c.primary : c.error,
              ),
              const SizedBox(width: 6),
              Text(
                isValid ? l10n.validMnemonic : l10n.invalidMnemonic,
                style: TextStyle(
                  color: isValid ? c.primary : c.error,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
