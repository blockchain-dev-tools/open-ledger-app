import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';
import '../../../theme/widgets/brand_mark.dart';
import '../../../widgets/common/neo_card.dart';

/// About section: app identity block (icon, name, version, tagline).
///
/// Replaces the old pair of pseudo-rows (a "Version" row that looked
/// tappable and a redundant "Ledger compatible" check row) with one
/// non-interactive card. In neo (light) the card is a [NeoCard]; dark keeps
/// the flat pre-neo surface card.
class AboutCard extends StatelessWidget {
  final ColorTokens c;

  const AboutCard({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return NeoCard(
      legacyEdgeWidth: 0,
      legacyRadius: R.lg,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        children: [
          const BrandMark(size: 56),
          const SizedBox(height: 14),
          Text(
            l10n.appTitle,
            style: TextStyle(
              color: c.text,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${l10n.version} 1.0.0',
            style: TextStyle(color: c.text.withAlpha(120), fontSize: 13),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.welcomeSubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.text.withAlpha(140),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
