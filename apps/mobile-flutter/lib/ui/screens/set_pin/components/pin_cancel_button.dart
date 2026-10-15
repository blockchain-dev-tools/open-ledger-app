import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';

/// The underlined "Cancel" action that pops the screen.
class PinCancelButton extends StatelessWidget {
  final VoidCallback onTap;

  const PinCancelButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;
    final neo = c.neobrutalism;

    return GestureDetector(
      key: const Key('pin-cancel'),
      onTap: onTap,
      child: Text(
        l10n.cancel,
        style: TextStyle(
          // Neo inverts the muted grey link to a heavy black one; dark keeps
          // the original thin grey underline.
          color: c.mutedText(120),
          fontSize: 14,
          fontWeight: neo ? FontWeight.w700 : FontWeight.normal,
          decoration: TextDecoration.underline,
          decorationColor: neo ? c.neoEdge : c.text.withAlpha(80),
          decorationThickness: neo ? 2 : null,
        ),
      ),
    );
  }
}
