import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../widgets/common/adaptive_action_button.dart';

/// The footer CTA that advances to Set-PIN.
///
/// Stateless — [onTap] is null while the screen has no words, which renders
/// the disabled state.
class EnigmaContinueButton extends StatelessWidget {
  final VoidCallback? onTap;

  const EnigmaContinueButton({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context)!.continueToSetPin;

    // The neo button has no disabled state, so the no-words case keeps the
    // original flat button even in light mode.
    return AdaptiveActionButton(label: label, onTap: onTap);
  }
}
