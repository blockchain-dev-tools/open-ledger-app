import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';
import '../stand_in_style.dart';

/// The section label above a group of [OptionCard]s — one style shared by
/// the intro (wizard) and the configured mode picker.
///
/// In neo (light) the label turns solid black and bold, matching the chunky
/// section labels elsewhere on the grouped background.
class SectionTitle extends StatelessWidget {
  final ColorTokens c;
  final String title;

  const SectionTitle({super.key, required this.c, required this.title});

  @override
  Widget build(BuildContext context) {
    final neo = c.neobrutalism;
    return Text(
      title,
      style: TextStyle(
        color: neo
            ? c.text
            : standInSecondaryText(c, Theme.of(context).brightness),
        fontSize: 14,
        fontWeight: neo ? FontWeight.w700 : FontWeight.w600,
      ),
    );
  }
}
