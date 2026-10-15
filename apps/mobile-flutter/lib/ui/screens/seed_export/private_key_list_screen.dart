import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/interfaces/export_service.dart';
import '../../../core/interfaces/screen_security.dart';
import '../../../core/models/chain.dart';
import '../../../core/models/wallet_accounts.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../utils/formatting.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/grid_background.dart';
import '../../widgets/common/neo_app_bar.dart';
import '../../widgets/common/neo_card.dart';
import '../../widgets/common/neo_note.dart';
import '../../widgets/common/neo_rule.dart';
import 'private_key_qr_screen.dart';

/// Per-account private-key list — the second hub destination.
///
/// One row per derived account; a tap opens that account's
/// [PrivateKeyQrScreen]. Keys are resolved lazily by [encodedKeyFor] only
/// when a row is tapped, so the list never holds every key at once.
///
/// With an [exportService] each row opens [PrivateKeyQrScreen] behind that
/// service's PIN gate; without one the injected preview resolvers are used
/// (gallery / screenshots). A row is inert when neither source is available.
class PrivateKeyListScreen extends StatelessWidget {
  const PrivateKeyListScreen({
    super.key,
    required this.accounts,
    this.exportService,
    this.screenSecurity,
    this.encodedKeyFor,
    this.encodingLabelFor,
    this.previewSeconds,
  });

  final List<ChainAccount> accounts;

  /// Production resolver + PIN gate; `null` → use the preview resolvers.
  final IExportService? exportService;

  /// Forwarded to each [PrivateKeyQrScreen] so its payload stays shielded
  /// (ADR-011 §6).
  final IScreenSecurity? screenSecurity;

  /// Preview-only resolver, used when [exportService] is null. Returns the
  /// importable key encoding, or null when unavailable (row renders disabled).
  final String? Function(ChainAccount account)? encodedKeyFor;
  final String? Function(ChainAccount account)? encodingLabelFor;

  /// Freezes the destination's auto-hide countdown for screenshots.
  final int? previewSeconds;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;
    final visibleAccounts = accounts
        .where((account) => Chain.visible.contains(Chain.fromId(account.chain)))
        .toList();

    return Scaffold(
      // Light follows the neo page tint (pale lime) so the reference grid
      // reads as paper ruling; dark's `groupedBg` equals `bg`, so this only
      // affects light mode.
      backgroundColor: c.groupedBg,
      appBar: neoAppBar(
        c: c,
        title: Text(l10n.privateKeysRow),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.text),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        darkBackground: c.bg,
      ),
      body: GridBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              // Primary-tinted note: exporting keys is usually redundant, so
              // the list leads with why you probably do not need it.
              NeoNote(
                message: l10n.privateKeysRareNote,
                fontSize: 12.5,
              ),
              const SizedBox(height: 20),
              NeoCard(
                clip: true,
                // Dark restores the original hairline card.
                legacyEdge: c.border.withAlpha(80),
                legacyRadius: R.lg,
                child: Column(
                  children: [
                    for (var i = 0; i < visibleAccounts.length; i++) ...[
                      if (i > 0)
                        // Light rules the rows off with a full-bleed black line;
                        // dark keeps the original inset hairline.
                        neoRule(
                          c,
                          legacy: Divider(
                            height: 1,
                            thickness: 0.5,
                            indent: 62,
                            color: c.border.withAlpha(140),
                          ),
                        ),
                      _AccountRow(
                        c: c,
                        account: visibleAccounts[i],
                        accountIndex: visibleAccounts[i].accountIndex,
                        enabled:
                            exportService != null || encodedKeyFor != null,
                        onTap: () => _openKey(context, visibleAccounts[i]),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openKey(BuildContext context, ChainAccount account) {
    final service = exportService;
    final encoded = encodedKeyFor?.call(account);
    if (service == null && encoded == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PrivateKeyQrScreen(
          account: account,
          exportService: service,
          screenSecurity: screenSecurity,
          encodedPrivateKey: encoded,
          encodingLabel: encodingLabelFor?.call(account),
          previewSeconds: previewSeconds,
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.c,
    required this.account,
    required this.accountIndex,
    required this.enabled,
    required this.onTap,
  });

  final ColorTokens c;
  final ChainAccount account;
  final int accountIndex;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Light leaves the chain logo unframed (the row block already
            // outlines it); dark restores the original circular tinted tile.
            if (c.neobrutalism)
              SvgPicture.asset(
                chainIconAssetPath(account.chain),
                width: 34,
                height: 34,
                fit: BoxFit.contain,
              )
            else
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: c.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: SvgPicture.asset(
                  chainIconAssetPath(account.chain),
                  width: 18,
                  height: 18,
                  fit: BoxFit.contain,
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${l10n.chainLabel(account.chain)} · '
                    '${l10n.accountWithIndex(accountIndex)}',
                    style: TextStyle(
                      color: enabled ? c.text : c.text.withAlpha(120),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    account.derivationPath,
                    style: TextStyle(
                      color: c.text.withAlpha(110),
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: enabled
                  ? c.text.withAlpha(100)
                  : c.text.withAlpha(40),
            ),
          ],
        ),
      ),
    );
  }
}
