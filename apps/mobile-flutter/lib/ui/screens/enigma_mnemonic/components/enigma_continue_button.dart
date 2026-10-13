import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
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
    return PrimaryButton(
      label: AppLocalizations.of(context)!.continueToSetPin,
      onTap: onTap,
    );
  }
}
