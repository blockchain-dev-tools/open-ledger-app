import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';

/// A single settings row: leading icon, title, optional right-aligned
/// [value] and a chevron.
///
/// Tapping calls [onTap]. Rows without [onTap] render muted and inert.
/// [iconColor]/[titleColor] override the neutral defaults (use [c.error]
/// for the destructive Reset Wallet row).
class SettingsRow extends StatelessWidget {
  final ColorTokens c;
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? titleColor;
  final bool showChevron;

  /// Trailing icon override (e.g. an edit affordance for the BLE name row).
  /// Takes precedence over the default chevron.
  final IconData? actionIcon;

  const SettingsRow({
    super.key,
    required this.c,
    required this.icon,
    required this.title,
    this.value,
    this.onTap,
    this.iconColor,
    this.titleColor,
    this.showChevron = true,
    this.actionIcon,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final iconEffective = enabled
        ? (iconColor ?? c.text.withAlpha(160))
        : c.text.withAlpha(80);
    final titleEffective = enabled
        ? (titleColor ?? c.text)
        : c.text.withAlpha(120);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconEffective),
            const SizedBox(width: 14),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: titleEffective,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            // iOS-style trailing value: pinned to the right edge, ahead of
            // the chevron. The title keeps its natural width; the value
            // takes the remaining space and ellipsizes when too long.
            if (value != null)
              Expanded(
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: c.text.withAlpha(enabled ? 120 : 80),
                    fontSize: 15,
                  ),
                ),
              )
            else
              const Spacer(),
            if (enabled && actionIcon != null) ...[
              const SizedBox(width: 4),
              Icon(actionIcon, size: 16, color: c.text.withAlpha(80)),
            ] else if (enabled && showChevron) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 16, color: c.text.withAlpha(80)),
            ],
          ],
        ),
      ),
    );
  }
}
