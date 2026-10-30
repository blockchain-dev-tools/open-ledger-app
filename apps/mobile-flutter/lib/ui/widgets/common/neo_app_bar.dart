import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';

/// Builds an [AppBar] carrying the neo title-bar chrome.
///
/// Light mode turns the bar into a white block closed by a hard rule, so it
/// reads as the page's top edge over the tinted body. Dark keeps the seamless
/// bar the screen had before — every neo-only property falls back to the theme
/// (`elevation` 0, `scrolledUnderElevation` 2, no rule).
///
/// Every neo surface with a title bar uses this instead of repeating the
/// `c.neobrutalism ? … : …` branches, so the rule cannot drift between screens.
///
/// [darkBackground] is the colour dark mode keeps — pass the screen's previous
/// bar colour. It defaults to [ColorTokens.surface], the theme's own AppBar
/// colour, which makes dark a no-op for screens that never overrode the bar.
/// [ruleWidth] lets the app's main shell draw a heavier rule than the card
/// outlines below it.
AppBar neoAppBar({
  required ColorTokens c,
  Widget? title,
  Widget? leading,
  bool automaticallyImplyLeading = true,
  List<Widget>? actions,
  Color? darkBackground,
  double ruleWidth = Neo.edge,
  double? titleSpacing,
}) {
  final neo = c.neobrutalism;

  return AppBar(
    backgroundColor: neo ? c.surface : (darkBackground ?? c.surface),
    elevation: neo ? 0 : null,
    scrolledUnderElevation: neo ? 0 : null,
    shape: neo
        ? Border(bottom: BorderSide(color: c.neoEdge, width: ruleWidth))
        : null,
    title: title,
    leading: leading,
    automaticallyImplyLeading: automaticallyImplyLeading,
    actions: actions,
    titleSpacing: titleSpacing,
  );
}
