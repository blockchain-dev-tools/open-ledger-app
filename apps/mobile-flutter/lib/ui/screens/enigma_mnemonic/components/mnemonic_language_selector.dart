import 'package:flutter/material.dart';

import '../../../../data/bip39_wordlist.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/mnemonic/mnemonic_language_picker.dart';

/// The display-language selector row: a label plus a tappable field that opens
/// the mnemonic-language sheet, which re-derives the mnemonic for the chosen
/// [Bip39WordlistLanguage].
///
/// Stateless — the selected [language] and the [onChanged] callback are owned
/// by the parent screen.
class MnemonicLanguageSelector extends StatelessWidget {
  final Bip39WordlistLanguage language;
  final ValueChanged<Bip39WordlistLanguage> onChanged;

  const MnemonicLanguageSelector({
    super.key,
    required this.language,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return Row(
      children: [
        Text(
          AppLocalizations.of(context)!.displayLanguage,
          style: TextStyle(color: c.text.withAlpha(160), fontSize: 13),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MnemonicLanguageTrigger(
            language: language,
            dense: true,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
