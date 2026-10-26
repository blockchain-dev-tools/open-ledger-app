import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/interfaces/export_service.dart';
import '../../../core/interfaces/screen_security.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/adaptive_action_button.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/grid_background.dart';
import '../../widgets/common/neo_app_bar.dart';
import '../../widgets/common/neo_back_button.dart';
import '../../widgets/common/neo_card.dart';
import '../../widgets/common/neo_note.dart';
import '../../widgets/common/qr_display_card.dart';
import '../../widgets/mnemonic/mnemonic_word_grid.dart';
import '../../widgets/mnemonic/warning_banner.dart';
import '../../widgets/pin/pin_gate.dart';
import '../../widgets/security/privacy_shield.dart';
import 'auto_hide_countdown.dart';

/// Recovery-phrase export as a single static QR.
///
/// The English BIP-39 phrase is encoded verbatim, since 12/24 English words
/// are importable by every wallet.
/// Entered from Settings → Backup & Export. With an [exportService] the
/// phrase is revealed behind a [PinGate] — PIN re-verification on the spot,
/// per contract I6 — and without one the preview phrase is rendered
/// verbatim, which is how the gallery reviews the layout.
///
/// The QR is the only exit — no clipboard, no file. A BIP-39 passphrase is
/// deliberately NOT encoded and gets an explicit warning instead, so the user
/// does not discover the gap only when restoring.
class SeedQrScreen extends StatefulWidget {
  const SeedQrScreen({
    super.key,
    this.exportService,
    this.screenSecurity,
    this.previewMnemonic,
    this.previewFingerprint,
    this.hasPassphrase = false,
    this.previewSeconds,
  });

  /// Production gate + reveal path. `null` → render the preview fields.
  final IExportService? exportService;

  /// Screenshot / recents-thumbnail block held while this screen is mounted
  /// (ADR-011 §6).
  final IScreenSecurity? screenSecurity;

  /// Preview-only phrase, rendered verbatim when [exportService] is null.
  final String? previewMnemonic;

  /// Wallet fingerprint shown as a chip so the user can tell which wallet
  /// the QR belongs to. Preview-only, like [previewMnemonic].
  final String? previewFingerprint;

  /// Whether the wallet uses a BIP-39 passphrase (never encoded in the QR).
  final bool hasPassphrase;

  /// Freezes the auto-hide countdown for deterministic screenshots.
  final int? previewSeconds;

  @override
  State<SeedQrScreen> createState() => _SeedQrScreenState();
}

class _SeedQrScreenState extends State<SeedQrScreen> {
  static const int _autoHideSeconds = 60;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;
    final exportService = widget.exportService;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      // Light follows the neo page tint (pale lime) so the reference grid
      // reads as paper ruling; dark's `groupedBg` equals `bg`, so this only
      // affects light mode.
      backgroundColor: c.groupedBg,
      appBar: neoAppBar(
        c: c,
        title: Text(l10n.exportSeedTitle),
        leading: neoBackButton(c, onPressed: () => Navigator.of(context).maybePop()),
        darkBackground: c.bg,
      ),
      // The QR lives in the body, so the lifecycle cover hides exactly the
      // secret while the plain "Recovery Phrase" title stays put.
      body: GridBackground(
        child: PrivacyShield(
          screenSecurity: widget.screenSecurity,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  WarningBanner(message: l10n.mnemonicQrWarning),
                  const SizedBox(height: 20),
                  if (exportService != null)
                    PinGate(
                      exportService: exportService,
                      keyPrefix: 'export-seed-pin',
                      // Locked out: leave this pushed route for the unlock
                      // screen's lockout view — the only reset exit (T-003).
                      onLockedOut: () {
                        if (mounted) context.go('/unlock');
                      },
                      onUnlocked: (pin) async {
                        final revealed = await exportService.revealMnemonic(pin);
                        if (revealed == null || revealed.isEmpty) return null;
                        return _buildQrView(c, l10n, screenWidth, revealed,
                            exportService.fingerprint,
                            exportService.hasPassphrase);
                      },
                    )
                  else if (widget.previewMnemonic == null ||
                      widget.previewMnemonic!.isEmpty)
                    _buildEmptyState(c, l10n)
                  else
                    _buildQrView(c, l10n, screenWidth, widget.previewMnemonic!,
                        widget.previewFingerprint, widget.hasPassphrase),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQrView(ColorTokens c, AppLocalizations l10n, double screenWidth,
      String mnemonic, String? fingerprint, bool hasPassphrase) {
    final qrSize = math.min(220.0, screenWidth - 96.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QrDisplayCard(data: mnemonic, size: qrSize),
        const SizedBox(height: 16),
        if (fingerprint != null)
          Center(
            // Light mode draws the chip as a small outlined block; dark keeps
            // the original hairline pill.
            child: NeoCard(
              lifted: false,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              legacyEdge: c.border.withAlpha(120),
              legacyRadius: R.lg,
              child: Text(
                l10n.walletChip(fingerprint),
                style: TextStyle(
                  color: c.mutedText(150),
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        const SizedBox(height: 20),
        // The phrase itself, as text, right under the QR chip. Same payload
        // as the QR, so a user can read or re-type the words directly.
        _buildMnemonicBlock(c, mnemonic),
        const SizedBox(height: 20),
        AutoHideCountdown(
          seconds: _autoHideSeconds,
          previewSeconds: widget.previewSeconds,
          onElapsed: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(height: 20),
        // Light mode renders the neo action button; dark keeps the original
        // flat button.
        AdaptiveActionButton(
          label: l10n.iveWrittenItDown,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.englishBip39Note,
          textAlign: TextAlign.center,
          style: TextStyle(color: c.text.withAlpha(110), fontSize: 12),
        ),
        if (hasPassphrase) ...[
          const SizedBox(height: 20),
          // Awareness note (not the red [WarningBanner]) — the passphrase is a
          // gap to be aware of, not a misuse.
          NeoNote(message: l10n.passphraseNotIncluded),
        ],
      ],
    );
  }

  /// The phrase, shown with the same shared grid the generate / Enigma /
  /// back-up screens use.
  ///
  /// Lives inside the [PrivacyShield] body, so the lifecycle cover hides the
  /// words together with the QR.
  Widget _buildMnemonicBlock(ColorTokens c, String mnemonic) {
    return MnemonicWordGrid(
      words: mnemonic.trim().split(RegExp(r'\s+')),
      columns: 3,
      fontSize: 14,
      monospace: true,
      // Light draws the neo cells; dark keeps the flat tiles.
      neo: c.neobrutalism,
    );
  }

  Widget _buildEmptyState(ColorTokens c, AppLocalizations l10n) {
    return EmptyState(icon: Icons.qr_code, message: l10n.noMnemonicGenerated);
  }
}
