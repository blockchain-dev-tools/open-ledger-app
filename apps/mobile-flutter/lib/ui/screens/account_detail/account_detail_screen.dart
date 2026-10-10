import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/models/wallet_accounts.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../utils/formatting.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/app_toast.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/common/section_header.dart';

/// Shows account details in three levels: identity header, a "Details" card
/// (derivation path + collapsible public key), and an "Address" card
/// (QR + address + copy).
///
/// Receives [ChainAccount] via [GoRouterState.extra] (passed from
/// the accounts tab). Falls back to a placeholder view when no extra is
/// provided (e.g. direct deep-link to `/account/:id`).
///
/// Signing is triggered by BLE-connected wallet clients (OKX Wallet, etc.)
/// via APDU commands — no in-app "Sign" button.
///
/// Ported from the original TypeScript implementation.
class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen({super.key});

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  /// Whether the public key hex is expanded (default: collapsed).
  bool _publicKeyExpanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;

    // Resolve account from GoRouter extra (passed by the accounts tab).
    final state = GoRouterState.of(context);
    final account =
        state.extra is ChainAccount ? state.extra as ChainAccount : null;
    final accountIndex = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        // Match the body background — the theme's AppBar uses c.surface,
        // which renders as a lighter band above the c.bg page body.
        backgroundColor: c.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        // Pull the title closer to the back button (default leading width is
        // 56 + titleSpacing 16, which reads as a wide empty gap).
        titleSpacing: 0,
        title: Text(
          l10n.accountDetail,
          style: TextStyle(
            color: c.text,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.text),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            }
          },
        ),
      ),
      body: account == null
          ? _buildPlaceholder(context, c)
          : _buildContent(context, c, account, accountIndex),
    );
  }

  /// Placeholder shown when no account data is available.
  Widget _buildPlaceholder(BuildContext context, ColorTokens c) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.qr_code, size: 64, color: c.text.withAlpha(60)),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.noAccountSelected,
            style: TextStyle(
              color: c.text.withAlpha(120),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  /// Full account detail body: identity → details → address → backup.
  Widget _buildContent(
      BuildContext context, ColorTokens c, ChainAccount account, int index) {
    final l10n = AppLocalizations.of(context)!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Identity header ──────────────────────────────────────
          _buildIdentityHeader(context, c, account.chain, index),

          const SizedBox(height: 24),

          // ── Details section ──────────────────────────────────────
          SectionHeader(title: l10n.details),
          const SizedBox(height: 8),
          _buildDetailsCard(context, c, account),

          const SizedBox(height: 28),

          // ── Address card (QR + address + copy) ───────────────────
          _buildReceiveCard(context, c, account.address),

          const SizedBox(height: 28),

          // ── Backup section (single-account private key export) ───
          SectionHeader(title: l10n.backupSection),
          const SizedBox(height: 8),
          _buildBackupCard(context, c, account),
        ],
      ),
    );
  }

  /// "Backup" entry: export **this** account's private key as a QR.
  ///
  /// Single-account scope lives here; the mnemonic and the all-accounts key
  /// list stay in Settings → Backup & Export, which the trailing hint names
  /// so the account page does not read as the only backup path.
  Widget _buildBackupCard(
      BuildContext context, ColorTokens c, ChainAccount account) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.lg),
            side: BorderSide(color: c.border.withAlpha(80)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push('/export-private-key', extra: account),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.vpn_key_outlined, size: 20, color: c.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.exportPrivateKey,
                          style: TextStyle(
                            color: c.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          l10n.exportPrivateKeySubtitle,
                          style: TextStyle(
                            color: c.text.withAlpha(120),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: c.text.withAlpha(100),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.exportEntryHint,
          style: TextStyle(color: c.text.withAlpha(100), fontSize: 12),
        ),
      ],
    );
  }

  /// Left-aligned identity header: 40×40 circular tinted chain icon +
  /// chain label + `Account <index>` subtitle.
  Widget _buildIdentityHeader(
      BuildContext context, ColorTokens c, String chain, int index) {
    final l10n = AppLocalizations.of(context)!;

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
            chainIconAssetPath(chain),
            width: 22,
            height: 22,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.chainLabel(chain),
              style: TextStyle(
                color: c.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              l10n.accountWithIndex(index),
              style: TextStyle(
                color: c.text.withAlpha(120),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// One full-width "Address" card: QR + left-aligned grouped address +
  /// full-width copy button. The whole card is tappable to copy.
  Widget _buildReceiveCard(
      BuildContext context, ColorTokens c, String address) {
    final l10n = AppLocalizations.of(context)!;
    final screenWidth = MediaQuery.of(context).size.width;
    final qrSize = math.min(200.0, screenWidth - 96.0);

    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(R.lg),
        side: BorderSide(color: c.border.withAlpha(80)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _copy(context, address),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.address,
                style: TextStyle(
                  color: c.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    // Black-on-white is REQUIRED for QR scannability —
                    // the only literal colors allowed on this screen.
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(R.lg),
                  ),
                  child: QrImageView(
                    data: address,
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
              Text(
                _groupAddress(address),
                style: TextStyle(
                  color: c.text,
                  fontSize: 15,
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: l10n.copyAddress,
                onTap: () => _copy(context, address),
                outline: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One "Details" card with two rows (label left / value right, monospace):
  /// derivation path, and a collapsible public key.
  Widget _buildDetailsCard(
      BuildContext context, ColorTokens c, ChainAccount account) {
    final l10n = AppLocalizations.of(context)!;

    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(R.lg),
        side: BorderSide(color: c.border.withAlpha(80)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildDetailRow(
            c,
            label: l10n.derivationPath,
            value: account.derivationPath,
          ),
          Divider(height: 1, color: c.border),
          if (account.publicKey.isNotEmpty)
            _buildPublicKeyRow(context, c, account.publicKey),
        ],
      ),
    );
  }

  /// A non-interactive `label left / value right` row.
  Widget _buildDetailRow(
    ColorTokens c, {
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                fontSize: 13,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Collapsible public key row. Collapsed → middle-truncated `first8…last6`
  /// + copy icon + "Show more"; tap toggles full wrapped hex + "Show less".
  Widget _buildPublicKeyRow(
      BuildContext context, ColorTokens c, String pubKey) {
    final l10n = AppLocalizations.of(context)!;
    final expanded = _publicKeyExpanded;

    if (!expanded) {
      return InkWell(
        onTap: () => setState(() => _publicKeyExpanded = true),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    l10n.publicKey,
                    style:
                        TextStyle(color: c.text.withAlpha(120), fontSize: 13),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _truncatePubKey(pubKey),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _copyIcon(context, c, pubKey),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                l10n.showMore,
                style: TextStyle(
                  color: c.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l10n.publicKey,
                style: TextStyle(color: c.text.withAlpha(120), fontSize: 13),
              ),
              const Spacer(),
              _copyIcon(context, c, pubKey),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            pubKey,
            style: TextStyle(
              color: c.text.withAlpha(160),
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => setState(() => _publicKeyExpanded = false),
            child: Text(
              l10n.showLess,
              style: TextStyle(
                color: c.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Small inline copy affordance (icon only, ripple).
  Widget _copyIcon(BuildContext context, ColorTokens c, String text) {
    return InkWell(
      onTap: () => _copy(context, text),
      borderRadius: BorderRadius.circular(R.sm),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(Icons.copy, size: 16, color: c.text.withAlpha(100)),
      ),
    );
  }

  /// Copies [text] to the clipboard and shows a themed confirmation toast.
  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    AppToast.show(
      context,
      message: AppLocalizations.of(context)!.copiedToClipboard,
    );
  }

  /// Groups a raw address into 4-char chunks (space-separated) so it wraps
  /// naturally without splitting a group across lines. A leading `0x` prefix
  /// is attached to the first chunk.
  static String _groupAddress(String address) {
    var prefix = '';
    var body = address;
    if (body.startsWith('0x') || body.startsWith('0X')) {
      prefix = body.substring(0, 2);
      body = body.substring(2);
    }

    final chunks = <String>[];
    for (var i = 0; i < body.length; i += 4) {
      final end = (i + 4 <= body.length) ? i + 4 : body.length;
      chunks.add(body.substring(i, end));
    }

    if (chunks.isEmpty) return prefix;
    chunks[0] = prefix + chunks[0];
    return chunks.join(' ');
  }

  /// Middle-truncates a public key to `first8…last6` for the collapsed state.
  static String _truncatePubKey(String pubKey) {
    if (pubKey.length <= 14) return pubKey;
    return '${pubKey.substring(0, 8)}…${pubKey.substring(pubKey.length - 6)}';
  }
}
