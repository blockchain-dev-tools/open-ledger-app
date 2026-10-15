import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../widgets/common/adaptive_action_button.dart';

/// The primary "Import" footer action; disabled until the mnemonic validates.
///
/// The neo button has no disabled state, so an unvalidated phrase keeps the
/// original flat button even in light mode. Dark keeps the original throughout.
class ImportButton extends StatelessWidget {
  final bool isValid;
  final VoidCallback onTap;

  const ImportButton({super.key, required this.isValid, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context)!.import;

    return AdaptiveActionButton(label: label, onTap: isValid ? onTap : null);
  }
}
