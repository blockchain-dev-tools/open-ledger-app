import 'package:flutter/material.dart';

import '../../../data/bip39_wordlist.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../common/neo_card.dart';
import '../common/neo_option_sheet.dart';

/// Localized display name for a BIP-39 wordlist language.
String mnemonicLanguageLabel(
  AppLocalizations l10n,
  Bip39WordlistLanguage lang,
) {
  switch (lang) {
    case Bip39WordlistLanguage.english:
      return l10n.languageEnglish;
    case Bip39WordlistLanguage.chineseSimplified:
      return l10n.languageChinese;
    case Bip39WordlistLanguage.japanese:
      return l10n.languageJapanese;
    case Bip39WordlistLanguage.korean:
      return l10n.languageKorean;
  }
}

/// Shows the BIP-39 wordlist picker as a bottom sheet, reporting the picked
/// language through [onSelected]. Runs on the shared neo option sheet.
void showMnemonicLanguageSheet(
  BuildContext context,
  Bip39WordlistLanguage current,
  ValueChanged<Bip39WordlistLanguage> onSelected,
) {
  final l10n = AppLocalizations.of(context)!;
  showNeoOptionSheet(
    context: context,
    title: l10n.mnemonicLanguage,
    options: [
      for (final lang in Bip39WordlistLanguage.values)
        (
          label: mnemonicLanguageLabel(l10n, lang),
          selected: lang == current,
          onSelect: () => onSelected(lang),
        ),
    ],
  );
}

/// A tappable field that shows the current BIP-39 wordlist language and opens
/// [showMnemonicLanguageSheet] on tap, reporting the pick through [onChanged].
///
/// Replaces the cramped inline `DropdownButton`: the sheet is easier to hit and
/// the four options never truncate. Neo-aware — light draws a neo block, dark
/// falls back to the original hairline field via [NeoCard]'s legacy chrome.
class MnemonicLanguageTrigger extends StatelessWidget {
  final Bip39WordlistLanguage language;
  final ValueChanged<Bip39WordlistLanguage> onChanged;

  /// Compact layout for the inline "Display Language" row (smaller text and
  /// padding) versus the full-width form field.
  final bool dense;

  const MnemonicLanguageTrigger({
    super.key,
    required this.language,
    required this.onChanged,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;
    final fontSize = dense ? 13.0 : 15.0;

    return GestureDetector(
      onTap: () => showMnemonicLanguageSheet(context, language, onChanged),
      child: NeoCard(
        legacyEdge: c.border,
        legacyRadius: dense ? R.sm : R.lg,
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 12 : 16,
          vertical: dense ? 7 : 14,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                mnemonicLanguageLabel(l10n, language),
                style: TextStyle(color: c.text, fontSize: fontSize),
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: fontSize + 7,
              color: c.text.withAlpha(120),
            ),
          ],
        ),
      ),
    );
  }
}
