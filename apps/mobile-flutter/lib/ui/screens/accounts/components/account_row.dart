import 'package:flutter/material.dart';

import '../../../../core/models/wallet_accounts.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_card.dart';

/// One account row: number chip, truncated address, a copy affordance and a
/// trailing chevron.
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
            // ── Account number token ─────────────────────────────────
            NeoCard(
              lifted: false,
              // Dark falls back to the original translucent chip, no outline.
              legacyEdgeWidth: 0,
              legacyRadius: R.sm,
              legacyBackground: c.text.withAlpha(12),
              child: SizedBox(
                width: 28,
                height: 28,
                child: Center(
                  child: Text(
                    '${account.accountIndex}',
                    style: TextStyle(
                      // Light (neo) uses the brand ink — pure black, matching
                      // the chip outline — with a heavy weight so the number
                      // reads as bold; dark keeps the original translucent
                      // muted tone.
                      color: c.neobrutalism ? c.brandInk : c.text.withAlpha(150),
                      fontSize: 12,
                      // No monospace: the generic monospace family has no bold
                      // face, so the weight collapsed to regular and the number
                      // did not read as bold.
                      fontWeight:
                          c.neobrutalism ? FontWeight.w800 : FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // ── Address ─────────────────────────────────────────────
            Expanded(
              child: Text(
                _truncateAddress(account.address),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.text.withAlpha(210),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'monospace',
                ),
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

/// Middle-truncates an [address] to `first7…last5` for the row.
String _truncateAddress(String address) {
  if (address.length <= 14) return address;
  return '${address.substring(0, 7)}…${address.substring(address.length - 5)}';
}
