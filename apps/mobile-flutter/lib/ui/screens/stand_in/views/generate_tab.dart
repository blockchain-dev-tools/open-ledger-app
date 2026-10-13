import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/common/primary_button.dart';
import '../../../widgets/mnemonic/mnemonic_word_grid.dart';
import '../../../widgets/mnemonic/warning_banner.dart';
import '../components/check_row.dart';
import '../stand_in_style.dart';

/// Generate tab — a freshly generated phrase rendered in a word grid, gated by
/// the "I've written it down" confirmation before continuing.
class GenerateTab extends StatelessWidget {
  final ColorTokens c;
  final AppLocalizations l10n;

  /// The generated words (empty until the tab is first selected).
  final List<String> words;

  /// Whether the write-down confirmation is ticked.
  final bool confirmed;

  final VoidCallback onToggleConfirmed;
  final VoidCallback onContinue;

  const GenerateTab({
    super.key,
    required this.c,
    required this.l10n,
    required this.words,
    required this.confirmed,
    required this.onToggleConfirmed,
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
                const SizedBox(height: 14),
                WarningBanner(message: l10n.generateMnemonicWarning),
                const SizedBox(height: 18),
                if (words.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      l10n.noMnemonicGenerated,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: secondary, fontSize: 13),
                    ),
                  )
                else
                  MnemonicWordGrid(words: words, columns: 3),
                const SizedBox(height: 20),
                CheckRow(
                  key: const ValueKey('standin-written-down'),
                  c: c,
                  label: l10n.iveWrittenItDown,
                  checked: confirmed,
                  onTap: onToggleConfirmed,
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: PrimaryButton(
            key: const Key('standin-generate-continue'),
            label: l10n.continueButton,
            onTap: confirmed ? onContinue : null,
          ),
        ),
      ],
    );
  }
}
