import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';
import 'neo_code_block.dart';

/// A block of machine-readable data — hex, signatures, an address.
///
/// Neo outlines it as data to be checked; dark keeps the flat filled block it
/// had before. Always full width, so a long hex string wraps inside the same
/// frame on every screen.
class NeoMonoBlock extends StatelessWidget {
  /// The data, already styled — usually a monospace `SelectableText`.
  final Widget child;

  /// Inner padding. Rows that live inside a denser card use a smaller one.
  final EdgeInsetsGeometry padding;

  const NeoMonoBlock({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    if (c.neobrutalism) {
      return SizedBox(
        width: double.infinity,
        child: NeoCodeBlock(padding: padding, child: child),
      );
    }

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: child,
    );
  }
}
