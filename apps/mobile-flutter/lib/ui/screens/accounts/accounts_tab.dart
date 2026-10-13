import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/interfaces/wallet_service.dart';
import '../../../core/models/chain.dart';
import '../../../core/models/wallet_accounts.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../utils/formatting.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/app_toast.dart';
import '../../widgets/common/neo_button.dart';
import '../../widgets/common/neo_card.dart';

/// Account list tab — the Vault home.
///
/// Present the active vault as a set of chain sections. Each section is an
/// accordion: collapsed it shows the chain and its account count, expanded it
/// lists the derived account addresses and an "Add Account" action.
///
/// Navigation:
/// - Account tap → `context.push('/account/:id', extra: ChainAccount)`
class AccountsTab extends StatefulWidget {
  final IWalletService? walletService;

  const AccountsTab({super.key, this.walletService});

  @override
  State<AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends State<AccountsTab> {
  /// Which chain sections are expanded (keyed by chain name).
  final Set<String> _expandedChains = {};

  // ── Canonical data ──────────────────────────────────────────────────

  /// Chain sections in display order — from the chain registry, the single
  /// source of truth shared with the BLE control sheet.
  static final _chainOrder = [for (final chain in Chain.visible) chain.id];

  // ── Helpers ────────────────────────────────────────────────────────

  WalletAccounts? get _accounts => widget.walletService?.getAccounts();

  Map<String, List<ChainAccount>> _groupByChain(WalletAccounts accounts) {
    final map = <String, List<ChainAccount>>{
      for (final ch in _chainOrder) ch: <ChainAccount>[],
    };
    for (final acct in accounts.accounts) {
      map.putIfAbsent(acct.chain, () => []).add(acct);
    }
    return map;
  }

  int _accountIndex(String chain, int localIndex) {
    final all = _accounts?.accounts ?? [];
    int found = 0;
    for (int i = 0; i < all.length; i++) {
      if (all[i].chain == chain) {
        if (found == localIndex) return i;
        found++;
      }
    }
    return localIndex;
  }

  // ── Navigation ─────────────────────────────────────────────────────

  void _goToAccount(String chain, int localIndex) {
    final accounts = _accounts;
    if (accounts == null) return;
    final grouped = _groupByChain(accounts);
    final list = grouped[chain] ?? [];
    if (localIndex < list.length) {
      final idx = _accountIndex(chain, localIndex);
      context.push('/account/$idx', extra: list[localIndex]);
    }
  }

  void _copyAddress(String address) {
    Clipboard.setData(ClipboardData(text: address));
    AppToast.show(
      context,
      message: AppLocalizations.of(context)!.copiedToClipboard,
    );
  }

  // ── Account management ─────────────────────────────────────────────

  String _nextPathForChain(String chain, List<ChainAccount> accounts) {
    final defaultPath = Chain.fromId(chain)!.defaultAccountPath;
    final parts = defaultPath.split('/');

    int maxIdx = -1;
    for (final acct in accounts) {
      int idx;
      if (chain == 'solana' || chain == 'sui') {
        idx = int.tryParse(
                acct.derivationPath.split('/')[3].replaceAll("'", '')) ??
            -1;
      } else {
        idx = int.tryParse(acct.derivationPath.split('/').last) ?? -1;
      }
      if (idx > maxIdx) maxIdx = idx;
    }

    final nextIdx = maxIdx + 1;
    if (chain == 'solana' || chain == 'sui') {
      parts[3] = "$nextIdx'";
    } else {
      parts[parts.length - 1] = '$nextIdx';
    }
    return parts.join('/');
  }

  Future<void> _addAccount(String chain) async {
    final ws = widget.walletService;
    if (ws == null) return;

    final grouped = _accounts != null ? _groupByChain(_accounts!) : {};
    final chainAccounts = grouped[chain] ?? [];
    final nextPath = _nextPathForChain(chain, chainAccounts);

    try {
      await ws.addAccount(chain, nextPath);
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final c = isDark ? ColorTokens.dark : ColorTokens.light;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppLocalizations.of(context)!.error}: $e'),
          backgroundColor: c.error,
        ),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final accounts = _accounts;

    if (accounts == null) return _buildEmptyState(c);
    return _buildAccountList(c, accounts);
  }

  Widget _buildEmptyState(ColorTokens c) {
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
                child: Icon(Icons.account_balance_wallet_outlined,
                    size: 34, color: c.text.withAlpha(70)),
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

  Widget _buildAccountList(ColorTokens c, WalletAccounts accounts) {
    final grouped = _groupByChain(accounts);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        for (final chain in _chainOrder) ...[
          _buildChainSection(c, chain, grouped[chain] ?? []),
          // Clears the block's own offset shadow (Neo.lift) plus a gap; the
          // legacy card has no shadow, so it keeps the tighter original gap.
          SizedBox(height: c.neobrutalism ? 14.0 : 10.0),
        ],
      ],
    );
  }

  Widget _buildChainSection(
      ColorTokens c, String chain, List<ChainAccount> accounts) {
    final l10n = AppLocalizations.of(context)!;
    // The Ethereum entry covers every EVM-compatible chain, so the Vault list
    // uses a dedicated label; other screens keep the plain chain name.
    final label = chain == Chain.ethereum.id
        ? l10n.chainEthereumEvm
        : l10n.chainLabel(chain);
    final iconPath = chainIconAssetPath(chain);
    final expanded = _expandedChains.contains(chain);
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
            onTap: () {
              setState(() {
                if (expanded) {
                  _expandedChains.remove(chain);
                } else {
                  _expandedChains.add(chain);
                }
              });
            },
            child: Padding(
              // Deliberately no fill for the open section: the expanded body
              // and the flipped chevron carry the state, not a colour block.
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                          return _buildAccountRow(c, chain, idx, acct);
                        }),
                      _buildAddAccountButton(c, chain),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildAddAccountButton(ColorTokens c, String chain) {
    if (c.neobrutalism) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: NeoButton(
          key: ValueKey('add-account-$chain'),
          label: AppLocalizations.of(context)!.addAccount,
          icon: Icons.add,
          expanded: true,
          onTap: () => _addAccount(chain),
        ),
      );
    }
    // Dark keeps the original bare label row: no fill, no outline.
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: GestureDetector(
        key: ValueKey('add-account-$chain'),
        onTap: () => _addAccount(chain),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 18, color: c.accent),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.of(context)!.addAccount,
                style: TextStyle(
                  color: c.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountRow(ColorTokens c, String chain, int localIndex,
      ChainAccount acct) {
    return GestureDetector(
      onTap: () => _goToAccount(chain, localIndex),
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
                    '${accountIndexInPath(acct.derivationPath)}',
                    style: TextStyle(
                      color: c.text.withAlpha(150),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // ── Address ─────────────────────────────────────────────
            Expanded(
              child: Text(
                _truncateAddress(acct.address),
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
              onTap: () => _copyAddress(acct.address),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.copy,
                  size: 16,
                  color: c.text.withAlpha(110),
                ),
              ),
            ),
            Icon(Icons.chevron_right,
                size: 18, color: c.text.withAlpha(60)),
          ],
        ),
      ),
    );
  }

  static String _truncateAddress(String address) {
    if (address.length <= 14) return address;
    return '${address.substring(0, 7)}…${address.substring(address.length - 5)}';
  }
}
