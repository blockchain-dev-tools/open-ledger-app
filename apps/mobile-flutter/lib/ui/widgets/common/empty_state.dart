import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';

/// The "nothing here yet" placeholder: a large muted glyph over one line of
/// explanation.
///
/// Covers the single-line shape only. The richer placeholders that pair an
/// icon with a title *and* a detail line (empty vault, account placeholder)
/// stay with their screens until a third screen needs that shape too.
class EmptyState extends StatelessWidget {
  /// Glyph above the message.
  final IconData icon;

  /// The one line of explanation.
  final String message;

  /// Glyph size.
  final double iconSize;

  /// Message size.
  final double messageSize;

  /// Outer spacing — the placeholder owns its own room, since it usually sits
  /// alone in the body.
  final EdgeInsetsGeometry padding;

  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.iconSize = 56,
    this.messageSize = 14,
    this.padding = const EdgeInsets.symmetric(vertical: 48),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return Padding(
      padding: padding,
      child: Column(
        children: [
          Icon(icon, size: iconSize, color: c.text.withAlpha(60)),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.text.withAlpha(140), fontSize: messageSize),
          ),
        ],
      ),
    );
  }
}
