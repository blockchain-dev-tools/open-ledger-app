import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../widgets/common/primary_button.dart';

/// The primary "Import" footer action; disabled until the mnemonic validates.
class ImportButton extends StatelessWidget {
  final bool isValid;
  final VoidCallback onTap;

  const ImportButton({super.key, required this.isValid, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PrimaryButton(
      label: AppLocalizations.of(context)!.import,
      onTap: isValid ? onTap : null,
    );
  }
}
