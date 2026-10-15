import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../../utils/formatting.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/common/adaptive_action_button.dart';
import '../../../widgets/common/copy_to_clipboard.dart';
import '../../../widgets/common/neo_card.dart';
import '../../../widgets/common/neo_code_block.dart';

/// One full-width "Address" card: QR + outlined address block + full-width copy
/// button. The whole card is tappable to copy.
class AccountReceiveCard extends StatelessWidget {
  final String address;

  const AccountReceiveCard({super.key, required this.address});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;
    final screenWidth = MediaQuery.of(context).size.width;
    final qrSize = math.min(200.0, screenWidth - 96.0);
    void copy() => copyToClipboard(context, address);

    return NeoCard(
      clip: true,
      // Dark restores the original hairline card.
      legacyEdge: c.border.withAlpha(80),
      child: GestureDetector(
        key: const ValueKey('receive-card'),
        behavior: HitTestBehavior.opaque,
        onTap: copy,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.address,
                style: TextStyle(
                  color: c.text,
                  fontSize: 15,
                  fontWeight: c.neobrutalism
                      ? FontWeight.w700
                      : FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    // Black-on-white is REQUIRED for QR scannability —
                    // the only literal colors allowed on this screen.
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(
                      c.neobrutalism ? Neo.radius : R.lg,
                    ),
                    border: c.neobrutalism
                        ? Border.all(color: c.neoEdge, width: Neo.edge)
                        : null,
                  ),
                  child: QrImageView(
                    data: address,
                    version: QrVersions.auto,
                    size: qrSize,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Light mode puts the address in its own outlined block so it
              // reads as data to be checked, not prose to be skimmed.
              NeoCodeBlock(
                padding: const EdgeInsets.all(12),
                child: Text(
                  groupAddress(address),
                  style: TextStyle(
                    color: c.text,
                    fontSize: 15,
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AdaptiveActionButton(
                key: const ValueKey('copy-address'),
                label: l10n.copyAddress,
                icon: Icons.copy,
                legacyOutline: true,
                onTap: copy,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
