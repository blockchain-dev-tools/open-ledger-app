import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';

/// One inset surface card holding tappable [rows] separated by indented
/// hairlines — the same grouped language as the Settings list.
class ActionGroup extends StatelessWidget {
  final ColorTokens c;
  final List<Widget> rows;

  const ActionGroup({super.key, required this.c, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(R.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              Divider(
                height: 1,
                thickness: 0.5,
                // Align the divider with the title text (after the icon).
                indent: 54,
                color: c.border.withAlpha(140),
              ),
          ],
        ],
      ),
    );
  }
}
