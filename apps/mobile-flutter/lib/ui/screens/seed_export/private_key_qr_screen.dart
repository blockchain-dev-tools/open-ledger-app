import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/interfaces/export_service.dart';
import '../../../core/interfaces/screen_security.dart';
import '../../../core/models/wallet_accounts.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../utils/formatting.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/adaptive_action_button.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/grid_background.dart';
import '../../widgets/common/neo_app_bar.dart';
import '../../widgets/common/neo_back_button.dart';
import '../../widgets/common/neo_card.dart';
import '../../widgets/common/neo_code_block.dart';
import '../../widgets/common/neo_rule.dart';
import '../../widgets/common/qr_display_card.dart';
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

  /// Whether the encoded key is shown in the clear. Hidden by default; the
  /// eye button toggles it. The QR already carries the same value.
  bool _keyVisible = false;

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
        leading: neoBackButton(c, onPressed: () => Navigator.of(context).maybePop()),
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
                      // Locked out: leave this pushed route for the unlock
                      // screen's lockout view — the only reset exit (T-003).
                      onLockedOut: () {
                        if (mounted) context.go('/unlock');
                      },
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
                  color: c.mutedText(120),
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
        QrDisplayCard(data: key, size: qrSize),
        const SizedBox(height: 20),
        _buildMetaCard(c, l10n, encodingLabel),
        const SizedBox(height: 16),
        // The key itself, as text: obscured by default, revealed by the eye.
        _buildKeyReveal(c, key),
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
            neoRule(c),
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
            style: TextStyle(
              color: c.text.withAlpha(120),
              fontSize: 13,
              fontWeight:
                  c.neobrutalism ? FontWeight.w700 : FontWeight.normal,
            ),
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

  /// The encoded key, obscured until the eye button reveals it.
  ///
  /// Light frames it as a neo code block (the same treatment addresses and hex
  /// get elsewhere), dark keeps the original bare, selectable text. Lives
  /// inside the [PrivacyShield] body, so the lifecycle cover hides it too.
  Widget _buildKeyReveal(ColorTokens c, String key) {
    // A fixed run of bullets, so the ciphertext length is not leaked.
    final display = _keyVisible ? key : List<String>.filled(24, '●').join();

    final value = SelectableText(
      display,
      style: TextStyle(
        color: c.text,
        fontSize: 12,
        fontFamily: 'monospace',
        height: 1.4,
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: c.neobrutalism
              ? NeoCodeBlock(
                  padding: const EdgeInsets.all(10),
                  child: value,
                )
              : value,
        ),
        const SizedBox(width: 10),
        _KeyRevealToggle(
          visible: _keyVisible,
          onTap: () => setState(() => _keyVisible = !_keyVisible),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ColorTokens c, AppLocalizations l10n) {
    return EmptyState(icon: Icons.qr_code, message: l10n.noAccountSelected);
  }

  static String _truncate(String value) {
    if (value.length <= 20) return value;
    return '${value.substring(0, 10)}…${value.substring(value.length - 6)}';
  }
}

/// Eye button for the private-key reveal, in the neo idiom.
///
/// Light draws a small outlined block with a black glyph; dark keeps the plain
/// icon button. Follows the app's reveal convention: a struck eye while the
/// value is obscured, a plain eye once it is shown.
class _KeyRevealToggle extends StatelessWidget {
  const _KeyRevealToggle({required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final icon = visible ? Icons.visibility : Icons.visibility_off;

    if (!c.neobrutalism) {
      return IconButton(
        icon: Icon(icon),
        color: c.text.withAlpha(150),
        onPressed: onTap,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: NeoCard(
        lifted: false,
        padding: const EdgeInsets.all(7),
        child: Icon(icon, size: 18, color: c.brandInk),
      ),
    );
  }
}
