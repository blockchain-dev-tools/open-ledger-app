import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';

/// The top-of-screen header block: lock icon, phase title and its subtitle.
///
/// The [title] and [subtitle] strings are resolved by the parent screen (they
/// depend on the mode and the current phase); this widget only owns the layout
/// and styling.
class PinHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const PinHeader({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Icon ────────────────────────────────────────────
        Icon(Icons.lock_outline, size: 64, color: c.primary.withAlpha(120)),

        const SizedBox(height: 20),

        // ── Title ───────────────────────────────────────────
        Text(
          title,
          style: TextStyle(
            color: c.text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),

        const SizedBox(height: 8),

        // ── Subtitle ────────────────────────────────────────
        Text(
          subtitle,
          style: TextStyle(color: c.text.withAlpha(140), fontSize: 14),
        ),
      ],
    );
  }
}
