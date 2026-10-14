import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_card.dart';
import '../stand_in_style.dart';

/// A selectable mode card: title + description with a leading check.
///
/// In neo (light) the card is a [NeoCard] — the selected card fills with the
/// brand lime and the leading dot turns solid black; dark keeps the original
/// accent-tinted flat card.
class OptionCard extends StatelessWidget {
  final ColorTokens c;
  final String title;
  final String description;
  final bool selected;
  final bool danger;
  final VoidCallback onTap;

  const OptionCard({
    super.key,
    required this.c,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final neo = c.neobrutalism;
    final accent = danger ? c.error : c.primary;
    final secondary = standInSecondaryText(c, Theme.of(context).brightness);

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Neo marks selection with a solid black dot, which reads on the
            // lime fill; the accent-ringed circle is legacy-only.
            color: selected
                ? (neo ? c.brandInk : accent)
                : Colors.transparent,
            border: Border.all(
              color: neo ? c.neoEdge : (selected ? accent : c.border),
              width: neo ? Neo.edge : 2,
            ),
          ),
          child: selected
              ? Icon(
                  Icons.check,
                  size: 14,
                  color: neo ? c.surface : c.onPrimary,
                )
              : null,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: c.text,
                  fontSize: 15,
                  fontWeight: neo ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  color: secondary,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (neo) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: NeoCard(
          clip: true,
          // The destructive option keeps the plain black outline so its hard
          // black shadow reads as one edge with it; the error signal moves to
          // the fill instead of the border. Non-destructive cards stay brand
          // ink (the same black in light).
          edge: danger ? c.neoEdge : c.brandInk,
          child: Container(
            padding: const EdgeInsets.all(16),
            // Destructive cards flatten the translucent error tint into an
            // opaque pale-red fill (the `WarningBanner` trick) so the page grid
            // cannot show through; selection still fills with the brand lime.
            color: selected
                ? c.actionFill
                : (danger
                    ? Color.alphaBlend(c.error.withAlpha(18), c.surface)
                    : c.surface),
            child: content,
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          // A 40 alpha fill reads as brighter than the neutral surface in
          // dark and as a soft tint over the grouped bg in light — the
          // border alone was doing all the work at 20.
          color: selected ? accent.withAlpha(40) : c.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(
            color: selected ? accent : c.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: content,
      ),
    );
  }
}
