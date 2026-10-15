import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';

/// A read-only `label left / value right` row, the value in monospace and
/// selectable.
///
/// The label keeps a fixed column ([labelWidth]) so stacked rows line up; the
/// value takes the rest and right-aligns against it. Rows whose label is sized
/// to its text, or whose value is not selectable, are a different shape and
/// stay with their screens.
class NeoDetailRow extends StatelessWidget {
  /// Row label, shown one step down from the value.
  final String label;

  /// Row value.
  final String value;

  /// Fixed label column width, or `null` to size the label to its text.
  final double? labelWidth;

  /// Font size for both label and value.
  final double fontSize;

  /// Makes the value selectable — the default, since these rows mostly carry
  /// addresses and hashes a user may want to copy by hand.
  final bool selectable;

  const NeoDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.labelWidth = 100,
    this.fontSize = 13,
    this.selectable = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    final labelStyle = TextStyle(
      color: c.mutedText(130),
      fontSize: fontSize,
      fontWeight: c.neobrutalism ? FontWeight.w600 : FontWeight.normal,
    );
    final valueStyle = TextStyle(
      color: c.text,
      fontSize: fontSize,
      fontFamily: 'monospace',
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (labelWidth == null)
          Text(label, style: labelStyle)
        else
          SizedBox(
            width: labelWidth,
            child: Text(label, style: labelStyle),
          ),
        const SizedBox(width: 8),
        Expanded(
          child: selectable
              ? SelectableText(
                  value,
                  style: valueStyle,
                  textAlign: TextAlign.right,
                )
              : Text(
                  value,
                  style: valueStyle,
                  textAlign: TextAlign.right,
                ),
        ),
      ],
    );
  }
}
