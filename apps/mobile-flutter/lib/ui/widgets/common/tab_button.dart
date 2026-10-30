import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';
import 'neo_card.dart';

/// One trigger inside a [TabStrip].
///
/// In neo (light) this is the trigger from the `tabs` component on
/// neobrutalism.dev: a 2px outlined block that fills with the brand lime
/// (with a black outline) only while selected, so the strip — not the tab —
/// carries the shadow. Dark keeps the pre-neo separated pills.
///
/// Always lays out inside an [Expanded], so the strip's tabs share one width.
class TabButton extends StatelessWidget {
  final ColorTokens c;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const TabButton({
    super.key,
    required this.c,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final neo = c.neobrutalism;

    // Three tabs share one 390pt row; CJK labels are wide, so the text
    // scales down rather than overflowing on narrow devices.
    final content = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        label,
        style: TextStyle(
          color: neo
              ? (selected ? c.brandInk : c.text)
              : (selected ? c.onPrimary : c.text.withAlpha(190)),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    if (neo) {
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            // 36 + the strip's 4px padding and 2px borders = a 48pt bar,
            // matching the reference's `h-12`.
            duration: const Duration(milliseconds: 120),
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? c.actionFill : const Color(0x00000000),
              borderRadius: BorderRadius.circular(Neo.radius),
              border: Border.all(
                color: selected ? c.neoEdge : const Color(0x00000000),
                width: Neo.edge,
              ),
            ),
            child: content,
          ),
        ),
      );
    }

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? c.primary : c.surface,
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: selected ? c.primary : c.border),
          ),
          alignment: Alignment.center,
          child: content,
        ),
      ),
    );
  }
}

/// A tab strip: the bordered, shadowed container the [TabButton]s sit in.
///
/// Follows the `tabs` component on neobrutalism.dev — one hard-edged,
/// offset-shadow box with 4px inner padding around the triggers, which is
/// what makes the row read as a single segmented control rather than
/// separate pills. Dark keeps the pre-neo row of separated pills.
class TabStrip extends StatelessWidget {
  final ColorTokens c;

  /// The [TabButton]s, in order. Each already expands to an equal share.
  final List<Widget> tabs;

  const TabStrip({super.key, required this.c, required this.tabs});

  @override
  Widget build(BuildContext context) {
    if (!c.neobrutalism) {
      return Row(
        children: [
          for (int i = 0; i < tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            tabs[i],
          ],
        ],
      );
    }

    return Padding(
      // Reserves the ledge the offset shadow occupies, so it never sits under
      // the content that follows the strip.
      padding: const EdgeInsets.only(right: Neo.lift, bottom: Neo.lift),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Neo.radius),
          border: Border.all(color: c.neoEdge, width: Neo.edge),
          boxShadow: neoShadow(c),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(children: tabs),
      ),
    );
  }
}
