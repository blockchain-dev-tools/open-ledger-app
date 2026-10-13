import 'package:flutter/material.dart';

import '../../../../data/bip39_wordlist.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';

/// The display-language selector row: a label plus a bordered dropdown that
/// re-derives the mnemonic for the chosen [Bip39WordlistLanguage].
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
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(color: c.border),
            ),
            child: DropdownButton<Bip39WordlistLanguage>(
              value: language,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              dropdownColor: c.surface,
              style: TextStyle(color: c.text, fontSize: 13),
              icon: Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: c.text.withAlpha(120),
              ),
              items: Bip39WordlistLanguage.values.map((lang) {
                return DropdownMenuItem(
                  value: lang,
                  child: Text(_localizedLanguageName(context, lang)),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  onChanged(value);
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Localized label for a BIP-39 wordlist language.
String _localizedLanguageName(
  BuildContext context,
  Bip39WordlistLanguage lang,
) {
  final l10n = AppLocalizations.of(context)!;
  switch (lang) {
    case Bip39WordlistLanguage.english:
      return l10n.languageEnglish;
    case Bip39WordlistLanguage.chineseSimplified:
      return l10n.languageChinese;
  }
}
