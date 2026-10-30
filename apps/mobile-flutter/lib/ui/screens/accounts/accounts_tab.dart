import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/interfaces/wallet_service.dart';
import '../../../core/models/bitcoin_address_type.dart';
import '../../../core/models/chain.dart';
import '../../../core/models/wallet_accounts.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/app_toast.dart';
import '../../widgets/common/neo_button.dart';
import '../../widgets/common/neo_sheet.dart';
import 'components/btc_address_type_sheet.dart';
import 'components/chain_section.dart';
import 'components/empty_vault.dart';
import 'components/manage_chains_sheet.dart';

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

  /// Chains shown in the Vault, in display order: the default set first, then
  /// any chain that already has an account (so a chain added from the
  /// "Manage chains" sheet survives a restart), minus the chains the user
  /// turned off.
  List<String> _enabledChains(WalletAccounts accounts) {
    final derived = {for (final a in accounts.accounts) a.chain};
    final hidden = widget.walletService?.hiddenChains ?? const <String>{};
    final ordered = <String>[
      for (final c in Chain.defaultVisible)
        if (!hidden.contains(c.id)) c.id,
    ];
    for (final c in Chain.values) {
      if (hidden.contains(c.id)) continue;
      if (!ordered.contains(c.id) && derived.contains(c.id)) ordered.add(c.id);
    }
    return ordered;
  }

  // ── Helpers ────────────────────────────────────────────────────────

  WalletAccounts? get _accounts => widget.walletService?.getAccounts();

  Map<String, List<ChainAccount>> _groupByChain(WalletAccounts accounts) {
    final map = <String, List<ChainAccount>>{
      for (final ch in _enabledChains(accounts)) ch: <ChainAccount>[],
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

  /// The next free path for [chain] — `Chain.accountPathForIndex` owns the
  /// per-chain rule (EVM/Tron vary the last segment, Solana/Sui the 4th).
  String _nextPathForChain(String chain, List<ChainAccount> accounts) {
    final c = Chain.fromId(chain)!;
    var maxIdx = -1;
    for (final acct in accounts) {
      final idx = c.accountIndexFromPath(acct.derivationPath);
      if (idx > maxIdx) maxIdx = idx;
    }
    return c.accountPathForIndex(maxIdx + 1);
  }

  /// The next free index **within one Bitcoin address type**: each type is its
  /// own account family on its own path, so `m/86'/…/0` and `m/84'/…/0` may
  /// both exist and must not push each other's counter.
  int _nextBtcIndexForType(
    BitcoinAddressType type,
    List<ChainAccount> accounts,
  ) {
    var maxIdx = -1;
    for (final acct in accounts) {
      if (acct.chain != Chain.bitcoin.id) continue;
      if (BitcoinAddressType.fromPath(acct.derivationPath) != type) continue;
      final idx = Chain.bitcoin.accountIndexFromPath(acct.derivationPath);
      if (idx > maxIdx) maxIdx = idx;
    }
    return maxIdx + 1;
  }

  /// The concrete path every Bitcoin type would create next — shown in the
  /// picker so the chosen option and the derived account can never disagree.
  Map<BitcoinAddressType, String> _nextBtcPaths(List<ChainAccount> accounts) => {
        for (final type in BitcoinAddressType.values)
          type: type.pathForIndex(_nextBtcIndexForType(type, accounts)),
      };

  /// Asks which Bitcoin address type the new account should use.
  Future<BitcoinAddressType?> _pickBtcAddressType(
    Map<BitcoinAddressType, String> paths,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    return showModalBottomSheet<BitcoinAddressType>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: neoSheetShape(c),
      builder: (_) => BtcAddressTypeSheet(paths: paths),
    );
  }

  Future<void> _addAccount(String chain) async {
    final ws = widget.walletService;
    if (ws == null) return;

    final grouped = _accounts != null ? _groupByChain(_accounts!) : {};
    final chainAccounts = grouped[chain] ?? [];

    String nextPath;
    if (chain == Chain.bitcoin.id) {
      // Bitcoin's four types are separate accounts, so the type is chosen
      // before the path exists.
      final paths = _nextBtcPaths(chainAccounts);
      final type = await _pickBtcAddressType(paths);
      if (type == null || !mounted) return;
      nextPath = paths[type]!;
    } else {
      nextPath = _nextPathForChain(chain, chainAccounts);
    }

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

  // ── Manage chains ──────────────────────────────────────────────────

  Future<void> _openManageChainsSheet() async {
    final accounts = _accounts;
    if (accounts == null) return;
    final visible = _enabledChains(accounts).toSet();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: neoSheetShape(c),
      builder: (_) =>
          ManageChainsSheet(visible: visible, onToggle: _setChainVisible),
    );
    if (mounted) setState(() {});
  }

  /// Shows or hides [chain]. Showing one that has no account derives account 0
  /// first; hiding keeps the accounts (and their history) and only drops the
  /// section from the Vault and the BLE picker.
  ///
  /// Returns false when the change failed, so the sheet can snap its switch
  /// back to the previous position.
  Future<bool> _setChainVisible(Chain chain, bool visible) async {
    final ws = widget.walletService;
    if (ws == null) return false;
    try {
      if (visible) {
        final derived =
            _accounts?.accounts.any((a) => a.chain == chain.id) ?? false;
        if (!derived) {
          await ws.addAccount(chain.id, chain.defaultAccountPath);
        }
        await ws.setChainHidden(chain.id, hidden: false);
        if (mounted) setState(() => _expandedChains.add(chain.id));
      } else {
        await ws.setChainHidden(chain.id, hidden: true);
      }
      if (mounted) setState(() {});
      return true;
    } catch (e) {
      if (!mounted) return false;
      AppToast.show(
        context,
        message: '${AppLocalizations.of(context)!.error}: $e',
      );
      return false;
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
        for (final chain in _enabledChains(accounts)) ...[
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
        _ManageChainsTile(tokens: c, onTap: _openManageChainsSheet),
      ],
    );
  }
}

/// The "Manage chains" action at the foot of the Vault list.
class _ManageChainsTile extends StatelessWidget {
  final ColorTokens tokens;
  final VoidCallback onTap;

  const _ManageChainsTile({required this.tokens, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (tokens.neobrutalism) {
      return NeoButton(
        key: const ValueKey('manage-chains-tile'),
        label: l10n.manageChains,
        icon: Icons.tune,
        expanded: true,
        onTap: onTap,
      );
    }
    return InkWell(
      key: const ValueKey('manage-chains-tile'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.tune, size: 18, color: tokens.accent),
            const SizedBox(width: 6),
            Text(
              l10n.manageChains,
              style: TextStyle(
                color: tokens.accent,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
