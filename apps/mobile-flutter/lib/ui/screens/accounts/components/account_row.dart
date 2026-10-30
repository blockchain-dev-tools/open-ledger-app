import 'package:flutter/material.dart';

import '../../../../core/models/bitcoin_address_type.dart';
import '../../../../core/models/chain.dart';
import '../../../../core/models/wallet_accounts.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../../utils/formatting.dart';
import '../../../theme/color_tokens.dart';

/// One account row: truncated address with its derivation detail on a second
/// line, a copy affordance and a trailing chevron.
///
/// Purely presentational — tapping the row or the copy icon reports through
/// [onTap] / [onCopy]; the parent decides what happens.
class AccountRow extends StatelessWidget {
  final ChainAccount account;
  final VoidCallback onTap;
  final VoidCallback onCopy;

  const AccountRow({
    super.key,
    required this.account,
    required this.onTap,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;
    // Bitcoin's four address types are separate accounts; the row must say
    // which one this address belongs to, or `1…` and `bc1q…` look alike.
    final btcType = account.chain == Chain.bitcoin.id
        ? BitcoinAddressType.fromPath(account.derivationPath)
        : null;
    // Second line: the derivation path for every chain, prefixed with the
    // Bitcoin address type where there is one — the path alone does not say
    // which wallet the address can be imported into.
    final detail = btcType == null
        ? account.derivationPath
        : '${l10n.bitcoinAddressTypeLabel(btcType)} · ${account.derivationPath}';

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.borderStrong)),
        ),
        child: Row(
          children: [
            // ── Address ─────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _truncateAddress(account.address),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      // 日间模式（neo）用纯黑 + 粗体：地址是这一行的主信息。
                      // 不用 `monospace`：该通用族在 Android 上只有 regular，
                      // 700 会被回退成常规字重，粗体请求会静默失效。
                      color: c.neobrutalism
                          ? c.brandInk
                          : c.text.withAlpha(210),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.mutedText(150),
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            // ── Copy ────────────────────────────────────────────────
            GestureDetector(
              onTap: onCopy,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.copy,
                  size: 16,
                  // Light (neo) draws the copy glyph in solid brand ink; dark
                  // keeps the original muted tone.
                  color: c.neobrutalism ? c.brandInk : c.text.withAlpha(110),
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              // Light (neo) draws the trailing chevron in solid brand ink; dark
              // keeps the original muted tone.
              color: c.neobrutalism ? c.brandInk : c.text.withAlpha(60),
            ),
          ],
        ),
      ),
    );
  }
}

/// Middle-truncates an [address] to `first10…last10`.
///
/// Fixed 21-character budget so the row never falls back to a trailing
/// ellipsis; the copy button stays the exact-value affordance.
String _truncateAddress(String address) {
  if (address.length <= 21) return address;
  return '${address.substring(0, 10)}…${address.substring(address.length - 10)}';
}
