import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';
import '../stand_in_style.dart';

/// A tappable row inside an [ActionGroup] — matches the Settings row
/// metrics (24px icon, 17pt title, hairline-divided) instead of the old
/// standalone card per action.
///
/// In neo (light) the neutral icon/title/chevron tones go full black and the
/// title gains weight; dark keeps the original muted greys.
class ActionRow extends StatelessWidget {
  final ColorTokens c;
  final IconData icon;
  final String label;
  final String? value;
  final bool destructive;
  final VoidCallback onTap;

  const ActionRow({
    super.key,
    required this.c,
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final neo = c.neobrutalism;
    final fg = destructive ? c.error : c.text;
    final secondary = standInSecondaryText(c, Theme.of(context).brightness);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Icon(
              icon,
              size: 24,
              color: destructive
                  ? c.error
                  : c.mutedText(160),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 17,
                fontWeight: neo ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (value != null)
              Expanded(
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: neo ? c.text : secondary,
                    fontSize: 17,
                  ),
                ),
              )
            else
              const Spacer(),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: c.mutedText(80),
            ),
          ],
        ),
      ),
    );
  }
}
