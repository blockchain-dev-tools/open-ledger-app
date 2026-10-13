import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';

/// A confirmation checkbox row (mirrors the mnemonic "I've written it down").
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
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.sm),
                border: Border.all(
                  color: checked ? c.primary : c.border,
                  width: 2,
                ),
                color: checked ? c.primary : Colors.transparent,
              ),
              child: checked
                  ? Icon(Icons.check, size: 16, color: c.onPrimary)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: c.text.withAlpha(200), fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
