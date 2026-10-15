import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_card.dart';
import '../../../widgets/common/neo_rule.dart';
import 'group_header.dart';

/// A section of the settings list: an uppercase label above a single
/// rounded card containing [rows] separated by indented hairline dividers.
///
/// In neo (light) the card becomes a [NeoCard] — black outline, 6px corners
/// and a hard offset shadow — and the dividers become full-width black lines.
class SettingsGroup extends StatelessWidget {
  final ColorTokens c;
  final String header;
  final List<Widget> rows;

  const SettingsGroup({
    super.key,
    required this.c,
    required this.header,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupHeader(c: c, title: header),
        NeoCard(
          clip: true,
          // Legacy chrome was a borderless surface card (radius 10, no edge);
          // dark mode restores exactly that.
          legacyEdgeWidth: 0,
          legacyRadius: 10,
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
                      // Align the divider with the title (after the icon).
                      indent: 52,
                      color: c.border.withAlpha(140),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
