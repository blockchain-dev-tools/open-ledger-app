import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../../utils/formatting.dart';
import '../../../theme/color_tokens.dart';

/// The top-of-page identity block: chain icon, chain label and the
/// `Account <index>` badge.
///
/// Light mode renders the chain logo bare on the page tint, a heavy label and
/// a lime badge; dark keeps the original circular tinted icon, 16px label and
/// plain subtitle.
class AccountIdentityHeader extends StatelessWidget {
  final String chain;
  final int index;

  const AccountIdentityHeader({
    super.key,
    required this.chain,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;
    final neo = c.neobrutalism;

    return Row(
      children: [
        if (neo)
          // No outline and no fill in light/neo: the logo sits bare on the
          // pale-lime page tint. The 48px slot and 26px glyph keep the row's
          // height and the following 14px gap unchanged.
          SizedBox(
            width: 48,
            height: 48,
            child: SvgPicture.asset(
              chainIconAssetPath(chain),
              width: 26,
              height: 26,
              fit: BoxFit.contain,
            ),
          )
        else
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(20),
            ),
            child: SvgPicture.asset(
              chainIconAssetPath(chain),
              width: 22,
              height: 22,
              fit: BoxFit.contain,
            ),
          ),
        SizedBox(width: neo ? 14.0 : 12.0),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.chainLabel(chain),
              style: TextStyle(
                color: c.text,
                fontSize: neo ? 20.0 : 16.0,
                fontWeight: neo ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            SizedBox(height: neo ? 6.0 : 2.0),
            if (neo)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  // Light/neo: lime fill so the badge reads as a brand chip.
                  color: c.actionFill,
                  borderRadius: BorderRadius.circular(Neo.radius),
                  border: Border.all(color: c.neoEdge, width: Neo.edge),
                ),
                child: Text(
                  l10n.accountWithIndex(index),
                  style: TextStyle(
                    // Black label on the lime fill.
                    color: c.brandInk,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              Text(
                l10n.accountWithIndex(index),
                style: TextStyle(color: c.text.withAlpha(120), fontSize: 13),
              ),
          ],
        ),
      ],
    );
  }
}
