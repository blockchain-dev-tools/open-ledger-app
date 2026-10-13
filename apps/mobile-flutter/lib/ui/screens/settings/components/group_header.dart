import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';

/// iOS-style group label above a settings card: 12pt regular,
/// secondary-label gray, sentence case.
///
/// Flush with the card's left edge (the parent list already applies the
/// 16pt gutter) — an extra 16pt here pushed the label to x=32, off the
/// grid shared by the app-bar title and the card edge.
///
/// In neo (light) the label turns black and bold, matching the chunky
/// section labels elsewhere on the grouped background.
class GroupHeader extends StatelessWidget {
  final ColorTokens c;
  final String title;

  const GroupHeader({super.key, required this.c, required this.title});

  @override
  Widget build(BuildContext context) {
    final neo = c.neobrutalism;
    return Padding(
      padding: EdgeInsets.only(bottom: neo ? 8 : 7),
      child: Text(
        title,
        style: neo
            ? TextStyle(
                fontSize: 12,
                color: c.text,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              )
            : TextStyle(fontSize: 12, color: c.text.withAlpha(110)),
      ),
    );
  }
}
