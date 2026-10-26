import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_button.dart';

/// "Scan QR" action for the import-mnemonic top area.
///
/// Mirrors `PasteButton`: light mode renders the neo quiet button, dark keeps
/// the original outlined button.
class QrScanButton extends StatelessWidget {
  final VoidCallback onPressed;

  const QrScanButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;

    if (c.neobrutalism) {
      return NeoButton(
        key: const Key('qr-scan-btn'),
        label: l10n.scanQrCode,
        icon: Icons.qr_code_scanner,
        quiet: true,
        expanded: true,
        onTap: onPressed,
      );
    }

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const Key('qr-scan-btn'),
        onPressed: onPressed,
        icon: Icon(Icons.qr_code_scanner, size: 18, color: c.primary),
        label: Text(
          l10n.scanQrCode,
          style: TextStyle(
            color: c.primary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: c.primary.withAlpha(100)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.lg),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}
