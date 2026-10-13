import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/models/chain.dart';
import '../../../../core/models/wallet_accounts.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../../utils/formatting.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_card.dart';
import 'account_row.dart';
import 'add_account_button.dart';

/// One collapsible chain group in the Vault home.
///
/// Collapsed it shows the chain icon, its label and an account count; expanded
/// it lists the derived account rows and an "Add Account" action. The expanded
/// state lives in the parent — this widget reads [expanded] and reports taps
/// through [onToggle], keeping it free of any state of its own.
class ChainSection extends StatelessWidget {
  final String chain;
  final List<ChainAccount> accounts;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(int localIndex) onAccountTap;
  final void Function(String address) onCopyAddress;
  final VoidCallback onAddAccount;

  const ChainSection({
    super.key,
    required this.chain,
    required this.accounts,
    required this.expanded,
    required this.onToggle,
    required this.onAccountTap,
    required this.onCopyAddress,
    required this.onAddAccount,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;
    // The Ethereum entry covers every EVM-compatible chain, so the Vault list
    // uses a dedicated label; other screens keep the plain chain name.
    final label = chain == Chain.ethereum.id
        ? l10n.chainEthereumEvm
        : l10n.chainLabel(chain);
    final iconPath = chainIconAssetPath(chain);
    final count = accounts.length;

    return NeoCard(
      clip: true,
      // Light mode outlines the section in brand ink (black) at [Neo.edge] px;
      // dark falls back to the original black-2px-while-expanded hairline.
      edge: c.brandInk,
      legacyEdgeWidth: expanded ? 2 : 1,
      child: Column(
        children: [
          // ── Header (tap anywhere to expand/collapse) ──────────────
          GestureDetector(
            key: ValueKey('chain-header-$chain'),
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Padding(
              // Deliberately no fill for the open section: the expanded body
              // and the flipped chevron carry the state, not a colour block.
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // Light mode: the logo sits unframed — a 2px outline around it
                  // just doubled up on the section's own outline. Dark restores
                  // the original translucent lime tile.
                  if (c.neobrutalism)
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: SvgPicture.asset(
                          iconPath,
                          width: 26,
                          height: 26,
                          fit: BoxFit.contain,
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c.primary.withAlpha(expanded ? 30 : 18),
                        borderRadius: BorderRadius.circular(R.lg),
                      ),
                      child: SvgPicture.asset(
                        iconPath,
                        width: 22,
                        height: 22,
                        fit: BoxFit.contain,
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            color: c.text,
                            fontSize: 16,
                            fontWeight: c.neobrutalism
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$count account${count == 1 ? '' : 's'}',
                          style: TextStyle(
                            color: c.text.withAlpha(115),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more,
                      color: c.text.withAlpha(100),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded body: accounts + add action ─────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (c.neobrutalism)
                        Divider(
                          height: Neo.edge,
                          thickness: Neo.edge,
                          color: c.neoEdge,
                        )
                      else
                        Divider(height: 1, color: c.borderStrong),
                      if (accounts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                          child: Text(
                            l10n.noAccounts,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: c.text.withAlpha(110),
                              fontSize: 14,
                            ),
                          ),
                        )
                      else
                        ...accounts.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final acct = entry.value;
                          return AccountRow(
                            account: acct,
                            onTap: () => onAccountTap(idx),
                            onCopy: () => onCopyAddress(acct.address),
                          );
                        }),
                      AddAccountButton(chain: chain, onTap: onAddAccount),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
