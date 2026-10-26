import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_card.dart';

/// Row under the mnemonic input: word counter on the left, validation
/// indicator on the right (shown only once a check has run).
///
/// In neo (light) the counter becomes an outlined chip and the validation
/// indicator an outlined pastel pill (mirroring the History status badge);
/// dark keeps the original muted chrome.
class MnemonicStatusRow extends StatelessWidget {
  final String wordCount;

  /// Word total the counter is measured against: 12 until the input grows past
  /// it, then 24 (both are valid BIP-39 lengths).
  final int targetWordCount;
  final bool hasChecked;
  final bool isValid;

  const MnemonicStatusRow({
    super.key,
    required this.wordCount,
    required this.targetWordCount,
    required this.hasChecked,
    required this.isValid,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;
    final statusColor = isValid ? c.primary : c.error;

    return Row(
      children: [
        // Word counter
        NeoCard(
          lifted: false,
          // Dark keeps the original surface chip with a hairline border.
          legacyEdge: c.border.withAlpha(100),
          legacyEdgeWidth: 1,
          legacyRadius: R.sm,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              l10n.wordsCount(int.parse(wordCount), targetWordCount),
              style: TextStyle(
                color: c.mutedText(180),
                fontSize: 13,
                fontWeight: c.neobrutalism ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),

        const Spacer(),

        // Validation indicator
        if (hasChecked)
          if (c.neobrutalism)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: statusColor.withAlpha(70),
                borderRadius: BorderRadius.circular(Neo.radius),
                border: Border.all(color: c.neoEdge, width: Neo.edge),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isValid ? Icons.check_circle : Icons.cancel,
                    size: 18,
                    color: statusColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isValid ? l10n.validMnemonic : l10n.invalidMnemonic,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isValid ? Icons.check_circle : Icons.cancel,
                  size: 20,
                  color: statusColor,
                ),
                const SizedBox(width: 6),
                Text(
                  isValid ? l10n.validMnemonic : l10n.invalidMnemonic,
                  style: TextStyle(
                    color: statusColor,
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
