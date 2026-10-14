import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_button.dart';
import '../../../widgets/common/primary_button.dart';

/// The footer CTA that advances to Set-PIN.
///
/// Stateless — [onTap] is null while the screen has no words, which renders
/// the disabled state.
class EnigmaContinueButton extends StatelessWidget {
  final VoidCallback? onTap;

  const EnigmaContinueButton({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final label = AppLocalizations.of(context)!.continueToSetPin;

    // The neo button has no disabled state, so the no-words case keeps the
    // original flat button even in light mode.
    if (c.neobrutalism && onTap != null) {
      return NeoButton(label: label, expanded: true, onTap: onTap!);
    }
    return PrimaryButton(label: label, onTap: onTap);
  }
}
