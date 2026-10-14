import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_card.dart';

/// A pill-shaped tab selector for the mnemonic step.
///
/// In neo (light) each tab is a [NeoCard]; the selected tab fills with the
/// brand lime and carries the offset shadow so it reads as the raised key,
/// while the rest sit flat. Dark keeps the original pill.
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
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    if (neo) {
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: NeoCard(
            clip: true,
            lifted: selected,
            edge: selected ? c.brandInk : c.neoEdge,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              color: selected ? c.actionFill : c.surface,
              alignment: Alignment.center,
              child: content,
            ),
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
