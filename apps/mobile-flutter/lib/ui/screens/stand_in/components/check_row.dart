import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_card.dart';

/// A confirmation checkbox row (mirrors the mnemonic "I've written it down").
///
/// In neo (light) the row is a [NeoCard] and the box fills with the brand lime
/// when ticked; dark keeps the original hairline card and lime primary box.
class CheckRow extends StatelessWidget {
  final ColorTokens c;
  final String label;
  final bool checked;
  final VoidCallback onTap;

  const CheckRow({
    super.key,
    required this.c,
    required this.label,
    required this.checked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final neo = c.neobrutalism;
    final content = Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(
              color: neo ? c.neoEdge : (checked ? c.primary : c.border),
              width: neo ? Neo.edge : 2,
            ),
            color: checked
                ? (neo ? c.actionFill : c.primary)
                : Colors.transparent,
          ),
          child: checked
              ? Icon(
                  Icons.check,
                  size: 16,
                  color: neo ? c.brandInk : c.onPrimary,
                )
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: neo ? c.text : c.text.withAlpha(200),
              fontSize: 14,
            ),
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: content,
          ),
        ),
      );
    }
    // Dark keeps the original hairline-outlined flat card.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: c.border.withAlpha(100)),
        ),
        child: content,
      ),
    );
  }
}
