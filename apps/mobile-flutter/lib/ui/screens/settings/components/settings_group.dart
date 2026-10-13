import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';
import 'group_header.dart';

/// A section of the settings list: an uppercase label above a single
/// rounded card containing [rows] separated by indented hairline dividers.
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
        // No border: the card edge is defined by surface vs. groupedBg.
        // Corner radius 10 matches the iOS inset-grouped card.
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                rows[i],
                if (i < rows.length - 1)
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    // Align the divider with the title text (after the icon).
                    indent: 52,
                    color: c.border.withAlpha(140),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
