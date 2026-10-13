import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';
import '../stand_in_style.dart';

/// A selectable mode card: title + description with a leading check.
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
    final accent = danger ? c.error : c.primary;
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? accent : Colors.transparent,
                border: Border.all(
                  color: selected ? accent : c.border,
                  width: 2,
                ),
              ),
              child: selected
                  ? Icon(Icons.check, size: 14, color: c.onPrimary)
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
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: standInSecondaryText(
                        c,
                        Theme.of(context).brightness,
                      ),
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
