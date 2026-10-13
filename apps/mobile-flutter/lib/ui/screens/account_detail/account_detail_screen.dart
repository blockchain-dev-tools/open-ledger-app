import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/wallet_accounts.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/section_header.dart';
import 'components/account_backup_card.dart';
import 'components/account_detail_placeholder.dart';
import 'components/account_details_card.dart';
import 'components/account_identity_header.dart';
import 'components/account_receive_card.dart';

/// Shows account details in three levels: identity header, a "Details" card
/// (derivation path + collapsible public key), and an "Address" card
/// (QR + address + copy).
///
/// Receives [ChainAccount] via [GoRouterState.extra] (passed from
/// the accounts tab). Falls back to a placeholder view when no extra is
/// provided (e.g. direct deep-link to `/account/:id`).
///
/// Signing is triggered by BLE-connected wallet clients (OKX Wallet, etc.)
/// via APDU commands — no in-app "Sign" button.
///
/// Each block lives in `components/`; this file only assembles the page.
///
/// Ported from the original TypeScript implementation.
class AccountDetailScreen extends StatelessWidget {
  const AccountDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;

    // Resolve account from GoRouter extra (passed by the accounts tab).
    final state = GoRouterState.of(context);
    final account =
        state.extra is ChainAccount ? state.extra as ChainAccount : null;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        // Match the body background — the theme's AppBar uses c.surface,
        // which renders as a lighter band above the c.bg page body.
        backgroundColor: c.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        // Light mode separates the neo title bar from the body with a hard 2px
        // rule instead of a soft elevation shadow; dark keeps the original
        // seamless bar.
        shape: c.neobrutalism
            ? Border(
                bottom: BorderSide(color: c.neoEdge, width: Neo.edge),
              )
            : null,
        // Pull the title closer to the back button (default leading width is
        // 56 + titleSpacing 16, which reads as a wide empty gap).
        titleSpacing: 0,
        title: Text(
          l10n.accountDetail,
          style: TextStyle(
            color: c.text,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.text),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            }
          },
        ),
      ),
      body: account == null
          ? const AccountDetailPlaceholder()
          : _buildContent(context, c, account),
    );
  }

  /// Full account detail body: identity → details → address → backup.
  Widget _buildContent(
    BuildContext context,
    ColorTokens c,
    ChainAccount account,
  ) {
    final l10n = AppLocalizations.of(context)!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Identity header ──────────────────────────────────────
          AccountIdentityHeader(
            chain: account.chain,
            index: account.accountIndex,
          ),

          const SizedBox(height: 24),

          // ── Details section ──────────────────────────────────────
          SectionHeader(title: l10n.details),
          const SizedBox(height: 8),
          AccountDetailsCard(account: account),

          const SizedBox(height: 28),

          // ── Address card (QR + address + copy) ───────────────────
          AccountReceiveCard(address: account.address),

          const SizedBox(height: 28),

          // ── Backup section (single-account private key export) ───
          SectionHeader(title: l10n.backupSection),
          const SizedBox(height: 8),
          AccountBackupCard(account: account),
        ],
      ),
    );
  }
}
