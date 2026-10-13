import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';

/// iOS-style group label above a settings card: 12pt regular,
/// secondary-label gray, sentence case.
///
/// Flush with the card's left edge (the parent list already applies the
/// 16pt gutter) — an extra 16pt here pushed the label to x=32, off the
/// grid shared by the app-bar title and the card edge.
class GroupHeader extends StatelessWidget {
  final ColorTokens c;
  final String title;

  const GroupHeader({super.key, required this.c, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        title,
        style: TextStyle(fontSize: 12, color: c.text.withAlpha(110)),
      ),
    );
  }
}
