import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/interfaces/export_service.dart';
import '../../../core/interfaces/screen_security.dart';
import '../../../core/models/wallet_accounts.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../utils/formatting.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/grid_background.dart';
import '../../widgets/common/neo_app_bar.dart';
import '../../widgets/common/neo_button.dart';
import '../../widgets/common/neo_card.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/mnemonic/warning_banner.dart';
import '../../widgets/pin/pin_gate.dart';
import '../../widgets/security/privacy_shield.dart';
import 'auto_hide_countdown.dart';

/// Single-account private-key export as a static QR.
///
/// Same shape as [SeedQrScreen] but account-scoped: the key shown is derived
/// at this account's path, and [encodingLabel] names the chain's importable
/// encoding (ETH `0x` hex, BTC WIF, SOL base58, Sui `suiprivkey…`) — a raw
/// 32-byte hex dump is not importable by most wallets.
///
/// With an [exportService] the key is derived live behind a [PinGate]
/// (contract I6); without one the preview [encodedPrivateKey] is rendered
/// verbatim, which is how the gallery reviews the layout.
class PrivateKeyQrScreen extends StatefulWidget {
  const PrivateKeyQrScreen({
    super.key,
    required this.account,
    this.exportService,
    this.screenSecurity,
    this.encodedPrivateKey,
    this.encodingLabel,
    this.previewSeconds,
  });

  /// The account whose key is shown (chain, path, address, account number).
  final ChainAccount account;

  /// Production gate + key resolver. `null` → render [encodedPrivateKey].
  final IExportService? exportService;

  /// Screenshot / recents-thumbnail block held while this screen is mounted
  /// (ADR-011 §6).
  final IScreenSecurity? screenSecurity;

  /// Preview-only key, shown verbatim when [exportService] is null.
  final String? encodedPrivateKey;

  /// Human-readable encoding name (e.g. `0x + 32B hex`). Data, not UI copy.
  final String? encodingLabel;

  /// Freezes the auto-hide countdown for deterministic screenshots.
  final int? previewSeconds;

  @override
  State<PrivateKeyQrScreen> createState() => _PrivateKeyQrScreenState();
}

class _PrivateKeyQrScreenState extends State<PrivateKeyQrScreen> {
  static const int _autoHideSeconds = 60;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;
    final exportService = widget.exportService;

    return Scaffold(
      // Light follows the neo page tint (pale lime) so the reference grid
      // reads as paper ruling; dark's `groupedBg` equals `bg`, so this only
      // affects light mode.
      backgroundColor: c.groupedBg,
      appBar: neoAppBar(
        c: c,
        title: Text(l10n.privateKeyExportTitle),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.text),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        darkBackground: c.bg,
      ),
      // The QR lives in the body, so the lifecycle cover hides exactly the
      // secret while the chain header stays put.
      body: GridBackground(
        child: PrivacyShield(
          screenSecurity: widget.screenSecurity,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(c, l10n),
                  const SizedBox(height: 20),
                  WarningBanner(message: l10n.privateKeyWarning),
                  const SizedBox(height: 20),
                  if (exportService != null)
                    PinGate(
                      exportService: exportService,
                      keyPrefix: 'export-private-key-pin',
                      onUnlocked: (pin) async {
                        final encoded =
                            exportService.encodePrivateKey(widget.account);
                        if (encoded == null || encoded.isEmpty) return null;
                        return _buildQrView(
                          context,
                          c,
                          l10n,
                          encoded,
                          exportService.encodingLabel(widget.account),
                        );
                      },
                    )
                  else if (widget.encodedPrivateKey == null ||
                      widget.encodedPrivateKey!.isEmpty)
                    _buildEmptyState(c, l10n)
                  else
                    _buildQrView(context, c, l10n, widget.encodedPrivateKey!,
                        widget.encodingLabel),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Chain icon + `Account N · <path>` chip so the key is unambiguous.
  Widget _buildHeader(ColorTokens c, AppLocalizations l10n) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: c.primary.withAlpha(20),
            borderRadius: BorderRadius.circular(20),
          ),
          child: SvgPicture.asset(
            chainIconAssetPath(widget.account.chain),
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
                l10n.chainLabel(widget.account.chain),
                style: TextStyle(
                  color: c.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${l10n.accountWithIndex(widget.account.accountIndex)} · '
                '${widget.account.derivationPath}',
                style: TextStyle(
                  color: c.text.withAlpha(120),
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQrView(BuildContext context, ColorTokens c,
      AppLocalizations l10n, String key, String? encodingLabel) {
    final screenWidth = MediaQuery.of(context).size.width;
    final qrSize = math.min(200.0, screenWidth - 96.0);

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
              data: key,
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
        const SizedBox(height: 20),
        _buildMetaCard(c, l10n, encodingLabel),
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
            label: l10n.iveBackedUp,
            expanded: true,
            onTap: () => Navigator.of(context).maybePop(),
          )
        else
          PrimaryButton(
            label: l10n.iveBackedUp,
            onTap: () => Navigator.of(context).maybePop(),
          ),
      ],
    );
  }

  Widget _buildMetaCard(
      ColorTokens c, AppLocalizations l10n, String? encodingLabel) {
    return NeoCard(
      clip: true,
      // Dark restores the original hairline card.
      legacyEdge: c.border.withAlpha(120),
      legacyRadius: R.lg,
      child: Column(
        children: [
          if (encodingLabel != null) ...[
            _metaRow(c, l10n.encoding, encodingLabel),
            // Light rules the rows off with a full-bleed black line; dark
            // keeps the original hairline.
            if (c.neobrutalism)
              Divider(height: Neo.edge, thickness: Neo.edge, color: c.neoEdge)
            else
              Divider(height: 1, color: c.border),
          ],
          _metaRow(c, l10n.address, _truncate(widget.account.address)),
        ],
      ),
    );
  }

  Widget _metaRow(ColorTokens c, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(color: c.text.withAlpha(120), fontSize: 13),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: c.text,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
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
            l10n.noAccountSelected,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.text.withAlpha(140), fontSize: 14),
          ),
        ],
      ),
    );
  }

  static String _truncate(String value) {
    if (value.length <= 20) return value;
    return '${value.substring(0, 10)}…${value.substring(value.length - 6)}';
  }
}
