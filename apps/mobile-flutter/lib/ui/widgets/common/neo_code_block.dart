import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';

/// An outlined container for machine-readable data (addresses, public keys).
///
/// Light mode wraps [child] in a [Neo.edge]-px brand-ink outline so the payload
/// reads as data to be checked rather than prose to be skimmed; dark mode
/// returns [child] untouched, restoring the original bare text.
class NeoCodeBlock extends StatelessWidget {
  final Widget child;

  /// Padding applied inside the outline. Ignored in dark mode, where no
  /// outline is drawn.
  final EdgeInsetsGeometry padding;

  const NeoCodeBlock({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    if (!c.neobrutalism) return child;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(Neo.radius),
        border: Border.all(color: c.neoEdge, width: Neo.edge),
      ),
      child: child,
    );
  }
}
