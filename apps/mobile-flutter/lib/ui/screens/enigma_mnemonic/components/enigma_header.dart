import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_card.dart';

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
    final neo = c.neobrutalism;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Light mode frames the shield as an outlined block; the lime
        // [primary] washes out on white, so the glyph uses the deeper accent.
        if (neo)
          Center(
            child: NeoCard(
              lifted: false,
              child: SizedBox(
                width: 72,
                height: 72,
                child: Icon(Icons.shield_outlined, size: 34, color: c.accent),
              ),
            ),
          )
        else
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
