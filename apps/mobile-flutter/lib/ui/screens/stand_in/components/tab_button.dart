import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';

/// A pill-shaped tab selector for the mnemonic step.
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
          // Three tabs share one 390pt row; CJK labels are wide, so the text
          // scales down rather than overflowing on narrow devices.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                color: selected ? c.onPrimary : c.text.withAlpha(190),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
