import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_button.dart';
import '../../../widgets/common/neo_card.dart';
import '../../../widgets/common/primary_button.dart';
import '../stand_in_style.dart';

/// Import tab — paste a 12-word phrase, live-validate it, then continue to the
/// two-pass PIN entry.
class ImportTab extends StatelessWidget {
  final ColorTokens c;
  final AppLocalizations l10n;

  final TextEditingController controller;

  /// Whether the field has been touched (non-empty) — drives the validation row.
  final bool checked;

  /// Whether the current input parses to a valid 12-word phrase.
  final bool valid;

  /// Number of parsed words, shown as `n / 12`.
  final int wordCount;

  final ValueChanged<String> onChanged;
  final VoidCallback onContinue;

  const ImportTab({
    super.key,
    required this.c,
    required this.l10n,
    required this.controller,
    required this.checked,
    required this.valid,
    required this.wordCount,
    required this.onChanged,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = standInSecondaryText(c, Theme.of(context).brightness);
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.standInCreateTitle,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.importMnemonicHint,
                  style: TextStyle(color: secondary, fontSize: 13),
                ),
                const SizedBox(height: 16),
                NeoCard(
                  clip: true,
                  // Light outlines the field in the validation colour (brand ink
                  // until touched, then green / red); dark restores the original
                  // 1.5px hairline border.
                  edge: !checked ? c.neoEdge : (valid ? c.accent : c.error),
                  legacyEdge: !checked
                      ? c.border
                      : (valid ? c.primary : c.error),
                  legacyEdgeWidth: 1.5,
                  legacyRadius: R.lg,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      key: const Key('standin-mnemonic-input'),
                      controller: controller,
                      onChanged: onChanged,
                      maxLines: null,
                      style: TextStyle(color: c.text, fontSize: 15, height: 1.6),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'word1 word2 word3 ...',
                        hintStyle: TextStyle(
                          color: c.text.withAlpha(80),
                          fontSize: 15,
                        ),
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      autocorrect: false,
                      enableSuggestions: false,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      '$wordCount / 12',
                      style: TextStyle(color: secondary, fontSize: 13),
                    ),
                    const Spacer(),
                    if (checked)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            valid ? Icons.check_circle : Icons.cancel,
                            size: 18,
                            color: valid
                                ? c.accent
                                : c.error,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            valid ? l10n.validMnemonic : l10n.invalidMnemonic,
                            style: TextStyle(
                              color: valid
                                  ? c.accent
                                  : c.error,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: c.neobrutalism && valid
              ? NeoButton(
                  key: const Key('standin-import-continue'),
                  label: l10n.continueButton,
                  expanded: true,
                  onTap: onContinue,
                )
              : PrimaryButton(
                  key: const Key('standin-import-continue'),
                  label: l10n.continueButton,
                  onTap: valid ? onContinue : null,
                ),
        ),
      ],
    );
  }
}
