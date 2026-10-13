import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';

/// The verification prompt card with two checkmark rows ("I have written down
/// my seed phrase" / "I understand that losing these words ...").
///
/// Purely presentational — the lines are static content, not toggles.
class EnigmaVerificationCard extends StatelessWidget {
  const EnigmaVerificationCard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline, size: 18, color: c.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'I have written down my seed phrase',
                  style: TextStyle(
                    color: c.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.check_circle_outline, size: 18, color: c.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'I understand that losing these words '
                  'means losing access to my funds',
                  style: TextStyle(color: c.text.withAlpha(160), fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
