import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';

/// The top-of-page header block: a shield icon, the "your Enigma seed phrase"
/// title and the "write down 24 words" subtitle, all centred.
///
/// Purely presentational — it holds no state.
class EnigmaHeader extends StatelessWidget {
  const EnigmaHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.shield_outlined, size: 56, color: c.primary),
        const SizedBox(height: 20),
        Text(
          l10n.yourEnigmaSeedPhrase,
          style: TextStyle(
            color: c.text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          l10n.writeDown24Words,
          style: TextStyle(
            color: c.text.withAlpha(160),
            fontSize: 14,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
