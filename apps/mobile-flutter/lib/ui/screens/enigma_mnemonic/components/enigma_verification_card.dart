import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_card.dart';

/// The verification prompt card with two checkmark rows ("I have written down
/// my seed phrase" / "I understand that losing these words ...").
///
/// Purely presentational — the lines are static content, not toggles.
class EnigmaVerificationCard extends StatelessWidget {
  const EnigmaVerificationCard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return NeoCard(
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
                Icons.check_circle_outline,
                size: 18,
                color: c.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'I have written down my seed phrase',
                  style: TextStyle(
                    color: c.text,
                    fontSize: 13,
                    fontWeight: c.neobrutalism
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 18,
                color: c.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'I understand that losing these words '
                  'means losing access to my funds',
                  style: TextStyle(color: c.text.withAlpha(160), fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
