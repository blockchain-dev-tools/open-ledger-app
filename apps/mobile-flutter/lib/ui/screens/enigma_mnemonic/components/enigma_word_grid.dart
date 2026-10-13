import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/mnemonic/mnemonic_word_grid.dart';

/// The 4×6 mnemonic word grid, or an empty-state prompt when no words were
/// generated.
///
/// Stateless — it renders whatever [words] it is given.
class EnigmaWordGrid extends StatelessWidget {
  final List<String> words;

  const EnigmaWordGrid({super.key, required this.words});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    if (words.isNotEmpty) {
      return MnemonicWordGrid(
        words: words,
        columns: 4,
        fontSize: 12,
        childAspectRatio: 2.0,
        cellSpacing: 6.0,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 40, color: c.text.withAlpha(80)),
          const SizedBox(height: 12),
          Text(
            AppLocalizations.of(context)!.noMnemonicGenerated,
            style: TextStyle(
              color: c.text.withAlpha(120),
              fontSize: 14,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
