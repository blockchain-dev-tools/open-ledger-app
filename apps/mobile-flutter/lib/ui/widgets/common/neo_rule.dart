import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';

/// The rule neo draws between stacked blocks: [Neo.edge] px of
/// [ColorTokens.neoEdge], or twice that for the heavier rule under a title
/// ([heavy]).
///
/// Every neo rule in the app comes from here so its weight and colour live in
/// one place. Dark mode keeps the hairline the screen used before the neo
/// experiment — the plain [ColorTokens.border] rule unless [legacy] says
/// otherwise, since a few lists inset and thin theirs.
///
/// ```dart
/// Column(children: [header, neoRule(c), body])
/// ```
Widget neoRule(
  ColorTokens c, {
  bool heavy = false,
  double? indent,
  Widget? legacy,
}) {
  if (!c.neobrutalism) {
    return legacy ?? Divider(height: 1, color: c.border, indent: indent);
  }
  final width = heavy ? Neo.edge * 2 : Neo.edge;
  return Divider(
    height: width,
    thickness: width,
    color: c.neoEdge,
    indent: indent,
  );
}
