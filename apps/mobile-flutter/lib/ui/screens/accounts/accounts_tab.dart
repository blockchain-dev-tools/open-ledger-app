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

/// Account list tab — displays wallet accounts grouped by chain.
///
/// Extracted from the original vault screen, stripped of BLE controls
/// and settings navigation. Shows expandable chain sections with
/// account addresses and copy-to-clipboard.
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
            Icon(Icons.account_balance_wallet_outlined,
                size: 64, color: c.text.withAlpha(60)),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.noAccounts,
              style: TextStyle(
                color: c.text.withAlpha(120),
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create or import a wallet to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.text.withAlpha(80),
                fontSize: 14,
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        _buildFingerprintBanner(c, accounts),
        const SizedBox(height: 12),
        for (final chain in _chainOrder)
          _buildChainSection(c, chain, grouped[chain] ?? []),
      ],
    );
  }

  Widget _buildFingerprintBanner(ColorTokens c, WalletAccounts accounts) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: c.primary.withAlpha(12),
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: c.primary.withAlpha(40)),
      ),
      child: Row(
        children: [
          Icon(Icons.fingerprint, size: 20, color: c.primary.withAlpha(160)),
          const SizedBox(width: 10),
          Text(
            'Wallet: ${accounts.mnemonicFingerprint}',
            style: TextStyle(
              color: c.text.withAlpha(160),
              fontSize: 13,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: c.border.withAlpha(80)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(20),
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
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$count account${count == 1 ? '' : 's'}',
                            style: TextStyle(
                              color: c.text.withAlpha(120),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: expanded ? 0.25 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.chevron_right,
                        color: c.text.withAlpha(100),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Expanded account list ────────────────────────────────
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: expanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Divider(height: 1),
                        ...accounts.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final acct = entry.value;
                          return _buildAccountRow(
                              c, chain, idx, acct, count);
                        }),
                        // "Add Account" button
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          child: GestureDetector(
                            onTap: () => _addAccount(chain),
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: c.primary.withAlpha(60),
                                ),
                                borderRadius:
                                    BorderRadius.circular(R.sm),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add,
                                      size: 18,
                                      color: c.primary.withAlpha(180)),
                                  const SizedBox(width: 6),
                                  Text(
                                    AppLocalizations.of(context)!.addAccount,
                                    style: TextStyle(
                                      color: c.primary.withAlpha(200),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountRow(ColorTokens c, String chain, int localIndex,
      ChainAccount acct, int totalCount) {
    final isLast = localIndex == totalCount - 1;

    return GestureDetector(
      onTap: () => _goToAccount(chain, localIndex),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(bottom: BorderSide(color: c.border)),
        ),
        child: Row(
          children: [
            // ── Derivation path badge ────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: c.text.withAlpha(12),
                borderRadius: BorderRadius.circular(R.sm),
              ),
              child: Text(
                acct.derivationPath.split('/').last,
                style: TextStyle(
                  color: c.text.withAlpha(140),
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 10),
            // ── Address ──────────────────────────────────────────────
            Expanded(
              child: Text(
                _truncateAddress(acct.address),
                style: TextStyle(
                  color: c.text.withAlpha(180),
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // ── Copy button ──────────────────────────────────────────
            GestureDetector(
              onTap: () => _copyAddress(acct.address),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.copy,
                  size: 16,
                  color: c.text.withAlpha(100),
                ),
              ),
            ),
            const SizedBox(width: 2),
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
