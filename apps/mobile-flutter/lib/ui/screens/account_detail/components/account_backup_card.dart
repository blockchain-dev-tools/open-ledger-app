import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/wallet_accounts.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_card.dart';

/// The "Backup" section: exports **this** account's private key as a QR.
///
/// Single-account scope lives here; the mnemonic and the all-accounts key list
/// stay in Settings → Backup & Export, which the trailing hint names so the
/// account page does not read as the only backup path.
class AccountBackupCard extends StatelessWidget {
  final ChainAccount account;

  const AccountBackupCard({super.key, required this.account});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NeoCard(
          clip: true,
          // Dark restores the original hairline card.
          legacyEdge: c.border.withAlpha(80),
          child: GestureDetector(
            key: const ValueKey('export-private-key'),
            behavior: HitTestBehavior.opaque,
            onTap: () => context.push('/export-private-key', extra: account),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.vpn_key_outlined,
                    size: 20,
                    color: c.neobrutalism ? c.accent : c.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.exportPrivateKey,
                          style: TextStyle(
                            color: c.text,
                            fontSize: 15,
                            fontWeight: c.neobrutalism
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          l10n.exportPrivateKeySubtitle,
                          style: TextStyle(
                            color: c.text.withAlpha(120),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: c.text.withAlpha(100),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Clears the block's own offset shadow before the hint text; the legacy
        // card has none, so it keeps the tighter original gap.
        SizedBox(height: c.neobrutalism ? 14.0 : 10.0),
        Text(
          l10n.exportEntryHint,
          style: TextStyle(color: c.text.withAlpha(100), fontSize: 12),
        ),
      ],
    );
  }
}
