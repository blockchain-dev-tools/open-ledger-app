import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/interfaces/export_service.dart';
import '../../../core/interfaces/screen_security.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/grid_background.dart';
import '../../widgets/common/neo_app_bar.dart';
import '../../widgets/common/neo_button.dart';
import '../../widgets/common/neo_card.dart';
import '../../widgets/common/neo_code_block.dart';
import '../../widgets/common/neo_note.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/mnemonic/warning_banner.dart';
import '../../widgets/pin/pin_gate.dart';
import '../../widgets/security/privacy_shield.dart';
import 'auto_hide_countdown.dart';

/// Recovery-phrase export as a single static QR.
///
/// The pure-QR counterpart to [BackupSeedScreen]: the English BIP-39 phrase is
/// encoded verbatim, since 12/24 English words are importable by every wallet.
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
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.text),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
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
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              // Black-on-white is REQUIRED for QR scannability.
              color: Colors.white,
              borderRadius: BorderRadius.circular(
                c.neobrutalism ? Neo.radius : R.lg,
              ),
              // Light mode outlines the white card as a neo block; dark keeps
              // the hairline that stops it vanishing on the white background.
              border: c.neobrutalism
                  ? Border.all(color: c.neoEdge, width: Neo.edge)
                  : Border.all(color: c.border),
            ),
            child: QrImageView(
              data: mnemonic,
              version: QrVersions.auto,
              size: qrSize,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          ),
        ),
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
                  color: c.neobrutalism ? c.text : c.text.withAlpha(150),
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
        if (c.neobrutalism)
          NeoButton(
            label: l10n.iveWrittenItDown,
            expanded: true,
            onTap: () => Navigator.of(context).maybePop(),
          )
        else
          PrimaryButton(
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

  /// The phrase rendered as machine-readable data, in the same neo idiom the
  /// hex/keys use elsewhere: numbered words wrapped across lines inside an
  /// outlined block in light, the original bare wording in dark.
  ///
  /// Lives inside the [PrivacyShield] body, so the lifecycle cover hides the
  /// words together with the QR.
  Widget _buildMnemonicBlock(ColorTokens c, String mnemonic) {
    final words = mnemonic.trim().split(RegExp(r'\s+'));

    final content = Wrap(
      spacing: 18,
      runSpacing: 10,
      children: [
        for (var i = 0; i < words.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${i + 1}',
                style: TextStyle(
                  color: c.neobrutalism
                      ? c.text.withAlpha(120)
                      : c.text.withAlpha(70),
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 6),
              Text(
                words[i],
                style: TextStyle(
                  color: c.neobrutalism ? c.text : c.text.withAlpha(180),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
      ],
    );

    if (!c.neobrutalism) return content;

    return NeoCodeBlock(
      padding: const EdgeInsets.all(14),
      child: content,
    );
  }

  Widget _buildEmptyState(ColorTokens c, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.qr_code, size: 56, color: c.text.withAlpha(60)),
          const SizedBox(height: 16),
          Text(
            l10n.noMnemonicGenerated,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.text.withAlpha(140), fontSize: 14),
          ),
        ],
      ),
    );
  }
}
