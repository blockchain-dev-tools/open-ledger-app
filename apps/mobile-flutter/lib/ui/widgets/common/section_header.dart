import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';

/// A small uppercase section header label, used to group related UI elements.
///
/// Extracted from [SettingsScreen] which used it as a private `_sectionHeader`
/// method. Can be reused in other screens with grouped content.
///
/// ```dart
/// SectionHeader(title: 'General')
/// SectionHeader(title: 'Security')
/// ```
class SectionHeader extends StatelessWidget {
  /// The section title (rendered in uppercase automatically).
  final String title;

  /// Optional subtitle displayed below the title.
  final String? subtitle;

  /// Optional icon displayed to the left of the title.
  final IconData? icon;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: c.text.withAlpha(100)),
            const SizedBox(width: 6),
          ],
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: c.text.withAlpha(100),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
