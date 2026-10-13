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

    return GestureDetector(
      key: const Key('pin-cancel'),
      onTap: onTap,
      child: Text(
        l10n.cancel,
        style: TextStyle(
          color: c.text.withAlpha(120),
          fontSize: 14,
          decoration: TextDecoration.underline,
          decorationColor: c.text.withAlpha(80),
        ),
      ),
    );
  }
}
