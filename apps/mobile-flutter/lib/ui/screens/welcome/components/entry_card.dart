import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_card.dart';

/// A styled card for a wallet entry action.
///
/// Displays an icon, title, description, and chevron. Tapping invokes
/// [onTap] for navigation.
class EntryCard extends StatelessWidget {
  final IconData? icon;
  final Widget Function(Color color)? iconBuilder;
  final String title;
  final String description;
  final VoidCallback onTap;

  const EntryCard({
    super.key,
    this.icon,
    this.iconBuilder,
    required this.title,
    required this.description,
    required this.onTap,
  }) : assert(icon != null || iconBuilder != null,
            'Either icon or iconBuilder must be provided');

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final neo = c.neobrutalism;

    return Semantics(
      label: title,
      button: true,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: NeoCard(
          clip: true,
          // Light outlines the card in brand ink with a hard offset shadow;
          // dark falls back to the original hairline-outlined flat card.
          legacyEdge: c.border.withAlpha(80),
          legacyEdgeWidth: 1,
          legacyRadius: R.lg,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                // ── Icon ───────────────────────────────────────────────
                if (neo)
                  NeoCard(
                    lifted: false,
                    fill: c.actionFill,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: iconBuilder != null
                            ? iconBuilder!(c.brandInk)
                            : Icon(icon, color: c.brandInk, size: 24),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(R.sm),
                    ),
                    child: iconBuilder != null
                        ? iconBuilder!(c.primary)
                        : Icon(icon, color: c.primary, size: 24),
                  ),
                const SizedBox(width: 16),

                // ── Text ───────────────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 16,
                          fontWeight: neo ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          color: c.mutedText(140),
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // ── Chevron ────────────────────────────────────────────
                Icon(
                  Icons.chevron_right,
                  color: neo ? c.brandInk : c.text.withAlpha(80),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
