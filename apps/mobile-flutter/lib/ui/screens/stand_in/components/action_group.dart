import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_card.dart';
import '../../../widgets/common/neo_rule.dart';

/// One inset surface card holding tappable [rows] separated by indented
/// hairlines — the same grouped language as the Settings list.
///
/// In neo (light) the card becomes a [NeoCard] — black outline, 6px corners and
/// a hard offset shadow — and the dividers become full-width black lines.
class ActionGroup extends StatelessWidget {
  final ColorTokens c;
  final List<Widget> rows;

  const ActionGroup({super.key, required this.c, required this.rows});

  @override
  Widget build(BuildContext context) {
    return NeoCard(
      clip: true,
      // Legacy chrome was a borderless surface card; dark restores exactly that.
      legacyEdgeWidth: 0,
      legacyRadius: R.lg,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              neoRule(
                c,
                legacy: Divider(
                  height: 1,
                  thickness: 0.5,
                  // Align the divider with the title text (after the icon).
                  indent: 54,
                  color: c.border.withAlpha(140),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
