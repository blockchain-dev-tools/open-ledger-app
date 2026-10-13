import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/interfaces/wallet_service.dart';
import '../../../core/models/chain.dart';
import '../../../core/models/wallet_accounts.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/app_toast.dart';
import 'components/chain_section.dart';
import 'components/empty_vault.dart';

/// Account list tab — the Vault home.
///
/// Present the active vault as a set of chain sections. Each section is an
/// accordion: collapsed it shows the chain and its account count, expanded it
/// lists the derived account addresses and an "Add Account" action.
///
/// Navigation:
/// - Account tap → `context.push('/account/:id', extra: ChainAccount)`
///
/// Each block lives in `components/`; this file owns the grouping, the
/// expand set, navigation and copy wiring.
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
        idx =
            int.tryParse(
              acct.derivationPath.split('/')[3].replaceAll("'", ''),
            ) ??
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

  /// Toggles a chain section's expansion (default: all collapsed).
  void _toggleChain(String chain) {
    setState(() {
      if (_expandedChains.contains(chain)) {
        _expandedChains.remove(chain);
      } else {
        _expandedChains.add(chain);
      }
    });
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final accounts = _accounts;

    if (accounts == null) return const EmptyVault();
    return _buildAccountList(c, accounts);
  }

  Widget _buildAccountList(ColorTokens c, WalletAccounts accounts) {
    final grouped = _groupByChain(accounts);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        for (final chain in _chainOrder) ...[
          ChainSection(
            chain: chain,
            accounts: grouped[chain] ?? [],
            expanded: _expandedChains.contains(chain),
            onToggle: () => _toggleChain(chain),
            onAccountTap: (localIndex) => _goToAccount(chain, localIndex),
            onCopyAddress: _copyAddress,
            onAddAccount: () => _addAccount(chain),
          ),
          // Clears the block's own offset shadow (Neo.lift) plus a gap; the
          // legacy card has no shadow, so it keeps the tighter original gap.
          SizedBox(height: c.neobrutalism ? 14.0 : 10.0),
        ],
      ],
    );
  }
}
