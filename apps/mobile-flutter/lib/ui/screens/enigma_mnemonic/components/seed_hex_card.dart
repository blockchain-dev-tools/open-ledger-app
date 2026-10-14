import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_card.dart';
import '../../../widgets/common/neo_code_block.dart';

/// The BIP-39 seed hex card: a titled, selectable hex string plus a note that
/// it was derived from the English mnemonic.
///
/// Stateless — the parent decides whether to render it at all.
class SeedHexCard extends StatelessWidget {
  final String seedHex;

  const SeedHexCard({super.key, required this.seedHex});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    final hex = SelectableText(
      seedHex,
      style: TextStyle(
        color: c.text.withAlpha(140),
        fontSize: 11,
        fontFamily: 'monospace',
        height: 1.5,
      ),
    );

    return NeoCard(
      clip: true,
      padding: const EdgeInsets.all(14),
      // Dark restores the original hairline card.
      legacyEdge: c.border,
      legacyRadius: R.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The lime [primary] washes out on the light surface, so the
              // glyph uses the deeper accent there.
              Icon(
                Icons.vpn_key_outlined,
                size: 16,
                color: c.neobrutalism ? c.accent : c.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'BIP-39 Seed (hex)',
                style: TextStyle(
                  color: c.text.withAlpha(180),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Light mode outlines the hex as data to be checked; dark keeps the
          // original bare text.
          if (c.neobrutalism)
            SizedBox(
              width: double.infinity,
              child: NeoCodeBlock(
                padding: const EdgeInsets.all(10),
                child: hex,
              ),
            )
          else
            hex,
          const SizedBox(height: 6),
          Text(
            AppLocalizations.of(context)!.seedDerivedFromEnglish,
            style: TextStyle(
              color: c.text.withAlpha(70),
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
