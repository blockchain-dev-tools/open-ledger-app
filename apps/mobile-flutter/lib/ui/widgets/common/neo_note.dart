import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';

/// A small informational note: a leading icon and a paragraph.
///
/// Light mode draws it as a neo block — an opaque [ColorTokens.actionFill]
/// lime fill closed by a hard [ColorTokens.neoEdge] outline at [Neo.edge] and
/// [Neo.radius] corners. The fill is opaque so the page's reference grid cannot
/// show through it, and the text turns [ColorTokens.brandInk] (the bright lime
/// washes out) with an [ColorTokens.accent] glyph.
///
/// Dark mode keeps the original translucent primary tint, so this only changes
/// light.
class NeoNote extends StatelessWidget {
  /// Paragraph rendered to the right of the icon.
  final String message;

  /// Leading glyph. Defaults to [Icons.info_outline].
  final IconData icon;

  /// Text size in logical pixels. Defaults to 13.
  final double fontSize;

  const NeoNote({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
    this.fontSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final neo = c.neobrutalism;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: neo ? c.actionFill : c.primary.withAlpha(18),
        borderRadius: BorderRadius.circular(neo ? Neo.radius : R.lg),
        border: Border.all(
          color: neo ? c.neoEdge : c.primary.withAlpha(60),
          width: neo ? Neo.edge : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: neo ? c.accent : c.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: neo ? c.brandInk : c.primary,
                fontSize: fontSize,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
