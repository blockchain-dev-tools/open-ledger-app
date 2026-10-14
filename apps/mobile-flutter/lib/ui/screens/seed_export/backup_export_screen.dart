import 'package:flutter/material.dart';

import '../../../core/interfaces/backup_verifier.dart';
import '../../../core/interfaces/export_service.dart';
import '../../../core/interfaces/screen_security.dart';
import '../../../core/models/wallet_accounts.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/grid_background.dart';
import '../../widgets/common/neo_app_bar.dart';
import '../../widgets/common/neo_card.dart';
import '../../widgets/common/neo_note.dart';
import '../../widgets/mnemonic/warning_banner.dart';
import '../verify/verify_backup_enigma_screen.dart';
import '../verify/verify_backup_mnemonic_screen.dart';
import '../verify/verify_backup_passphrase_screen.dart';
import 'private_key_list_screen.dart';
import 'seed_qr_screen.dart';

/// Backup & Export hub — the wallet-level entry reached from
/// Settings → Security.
///
/// Two export exits, by scope:
/// - **Recovery phrase QR** (whole wallet, restores every account)
/// - **Private keys** (per-account list — the escape hatch for wallets that
///   cannot import a passphrase-protected phrase)
///
/// Below them, the **verification** exits (ADR-011 §5): the user retypes a
/// secret and the app recomputes the wallet's derived output to confirm the
/// backup was written down correctly. Verification reveals nothing, so unlike
/// the export exits it is not PIN-gated.
///
/// With an [exportService] the hub reads the live wallet and both exits gate
/// on the session PIN; without one it renders the preview fields verbatim
/// (gallery / screenshots).
class BackupExportScreen extends StatelessWidget {
  const BackupExportScreen({
    super.key,
    this.exportService,
    this.backupVerifier,
    this.screenSecurity,
    this.previewMnemonic,
    this.previewFingerprint,
    this.hasPassphrase = false,
    this.isEnigma = false,
    this.previewAccounts = const [],
    this.encodedKeyFor,
    this.encodingLabelFor,
  });

  /// Live wallet view; `null` → render the preview fields.
  final IExportService? exportService;

  /// Live verifier backing the three verification exits. `null` → the rows
  /// still render, so the gallery can review the hub (preview).
  final IBackupVerifier? backupVerifier;

  /// Forwarded to the secret-display destinations so their payload stays
  /// shielded (ADR-011 §6).
  final IScreenSecurity? screenSecurity;

  /// Preview-only phrase shown by the seed-QR destination.
  final String? previewMnemonic;

  /// Preview-only wallet fingerprint for the seed-QR chip.
  final String? previewFingerprint;

  /// Preview-only: whether the wallet uses a BIP-39 passphrase.
  final bool hasPassphrase;

  /// Preview-only: whether the wallet was created via Enigma (drives the
  /// riddle + key verification row).
  final bool isEnigma;

  /// Preview-only accounts backing the private-key list.
  final List<ChainAccount> previewAccounts;

  /// Preview-only resolvers feeding the per-account key QR.
  final String? Function(ChainAccount account)? encodedKeyFor;
  final String? Function(ChainAccount account)? encodingLabelFor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;
    final service = exportService;
    final verifier = backupVerifier;
    final showPassphraseNote = service?.hasPassphrase ?? hasPassphrase;
    final showEnigma = verifier?.isEnigma ?? isEnigma;

    return Scaffold(
      // Light follows the neo page tint (pale lime) so the reference grid
      // reads as paper ruling; dark's `groupedBg` equals `bg`, so this only
      // affects light mode.
      backgroundColor: c.groupedBg,
      appBar: neoAppBar(
        c: c,
        title: Text(l10n.backupAndExport),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.text),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        darkBackground: c.bg,
      ),
      body: GridBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WarningBanner(message: l10n.backupSeedWarning),
                const SizedBox(height: 24),
                _NavCard(
                  c: c,
                  icon: Icons.qr_code_2_outlined,
                  title: l10n.exportSeedQrRow,
                  subtitle: l10n.exportSeedQrRowSubtitle,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => service != null
                          ? SeedQrScreen(
                              exportService: service,
                              screenSecurity: screenSecurity,
                            )
                          : SeedQrScreen(
                              previewMnemonic: previewMnemonic,
                              previewFingerprint: previewFingerprint,
                              hasPassphrase: hasPassphrase,
                              previewSeconds: 58,
                            ),
                    ),
                  ),
                ),
                if (showPassphraseNote) ...[
                  const SizedBox(height: 12),
                  NeoNote(message: l10n.passphraseNotIncluded),
                ],
                const SizedBox(height: 24),
                _NavCard(
                  c: c,
                  icon: Icons.vpn_key_outlined,
                  title: l10n.privateKeysRow,
                  subtitle: l10n.privateKeysRowSubtitle,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => service != null
                          ? PrivateKeyListScreen(
                              accounts: service.accounts,
                              exportService: service,
                              screenSecurity: screenSecurity,
                            )
                          : PrivateKeyListScreen(
                              accounts: previewAccounts,
                              encodedKeyFor: encodedKeyFor,
                              encodingLabelFor: encodingLabelFor,
                              previewSeconds: 58,
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.privateKeysRareNote,
                  style: TextStyle(
                    color: c.neobrutalism ? c.text : c.text.withAlpha(110),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),

                // ── Verification (ADR-011 §5) ────────────────────────
                const SizedBox(height: 28),
                Text(
                  l10n.verifySectionHeader,
                  style: TextStyle(
                    color: c.neobrutalism ? c.text : c.text.withAlpha(170),
                    fontSize: 13,
                    fontWeight:
                        c.neobrutalism ? FontWeight.w700 : FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 12),
                _NavCard(
                  c: c,
                  icon: Icons.spellcheck,
                  title: l10n.verifySeedTitle,
                  subtitle: l10n.verifyRowSubtitle,
                  onTap: () => _openVerify(
                    context,
                    () => VerifyBackupMnemonicScreen(verifier: verifier),
                  ),
                ),
                const SizedBox(height: 12),
                // Always offered: a mismatch is also how the user discovers a
                // wallet has *no* passphrase (ADR-011 §5, bidirectional copy).
                _NavCard(
                  c: c,
                  icon: Icons.password_outlined,
                  title: l10n.verifyPassphraseTitle,
                  subtitle: l10n.verifyRowSubtitle,
                  onTap: () => _openVerify(
                    context,
                    () => VerifyBackupPassphraseScreen(verifier: verifier),
                  ),
                ),
                if (showEnigma) ...[
                  const SizedBox(height: 12),
                  _NavCard(
                    c: c,
                    icon: Icons.auto_awesome_outlined,
                    title: l10n.verifyEnigmaTitle,
                    subtitle: l10n.verifyRowSubtitle,
                    onTap: () => _openVerify(
                      context,
                      () => VerifyBackupEnigmaScreen(verifier: verifier),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openVerify(BuildContext context, Widget Function() build) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => build()));
  }
}

/// Large tappable destination card used by the hub rows.
class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.c,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final ColorTokens c;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          // The lime [primary] washes out on the light surface, so the glyph
          // uses the deeper accent there.
          Icon(icon, size: 22, color: c.neobrutalism ? c.accent : c.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 15,
                    fontWeight:
                        c.neobrutalism ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: c.neobrutalism ? c.text : c.text.withAlpha(120),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: c.text.withAlpha(100)),
        ],
      ),
    );

    // Light mode renders a neo block; dark keeps the original Material card
    // (and its ripple).
    if (c.neobrutalism) {
      return NeoCard(
        clip: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: content,
        ),
      );
    }
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(R.lg),
        side: BorderSide(color: c.border.withAlpha(80)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: content,
      ),
    );
  }
}
