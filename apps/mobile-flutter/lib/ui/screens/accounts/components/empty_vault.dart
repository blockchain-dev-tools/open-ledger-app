import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_card.dart';

/// Empty-Vault placeholder shown when there is no active wallet.
class EmptyVault extends StatelessWidget {
  const EmptyVault({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NeoCard(
              // Dark falls back to the original translucent rounded tile.
              legacyEdgeWidth: 0,
              legacyRadius: R.xl,
              legacyBackground: c.text.withAlpha(12),
              child: SizedBox(
                width: 72,
                height: 72,
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 34,
                  color: c.text.withAlpha(70),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(context)!.noAccounts,
              style: TextStyle(
                color: c.text.withAlpha(140),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create or import a wallet to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.text.withAlpha(90),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
