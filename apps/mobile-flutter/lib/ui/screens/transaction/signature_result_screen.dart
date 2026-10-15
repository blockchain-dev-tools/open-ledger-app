import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../utils/formatting.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/app_toast.dart';
import '../../widgets/common/grid_background.dart';
import '../../widgets/common/neo_app_bar.dart';
import '../../widgets/common/neo_button.dart';
import '../../widgets/common/neo_card.dart';
import '../../widgets/common/neo_code_block.dart';
import '../../widgets/common/neo_rule.dart';
import '../../widgets/common/primary_button.dart';

/// Signature result screen — shown after a transaction is signed.
///
/// Reads [AppState.lastSignResult] for display data.
/// Provides copy-to-clipboard for the signature.
class SignatureResultScreen extends StatefulWidget {
  final AppState? appState;

  /// Optional preview result shown when no [AppState] is attached
  /// (design gallery). Takes precedence over `appState.lastSignResult`.
  final Map<String, dynamic>? previewResult;

  const SignatureResultScreen({super.key, this.appState, this.previewResult});

  @override
  State<SignatureResultScreen> createState() => _SignatureResultScreenState();
}

class _SignatureResultScreenState extends State<SignatureResultScreen> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).brightness == Brightness.dark
        ? ColorTokens.dark
        : ColorTokens.light;
    final result = widget.previewResult ?? widget.appState?.lastSignResult;

    // If no result, show redirect to vault.
    if (result == null) {
      return Scaffold(
        // Light follows the neo page tint (pale lime) so the reference grid
        // reads as paper ruling; dark's `groupedBg` equals `bg`, so this only
        // affects light mode.
        backgroundColor: c.groupedBg,
        body: GridBackground(
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final isSuccess = result['isSuccess'] == true;
    final chain = result['chain'] as String? ?? '';
    final signatureHex = result['signatureHex'] as String? ?? '';
    final signingAddress = result['signingAddress'] as String? ?? '';
    final derivationPath = result['derivationPath'] as String? ?? '';
    final txType = result['type'] as String?;
    final toAddr = result['to'] as String?;
    final value = result['value'] as String?;

    return Scaffold(
      // Light follows the neo page tint (pale lime) so the reference grid
      // reads as paper ruling; dark's `groupedBg` equals `bg`, so this only
      // affects light mode.
      backgroundColor: c.groupedBg,
      appBar: neoAppBar(
        c: c,
        title: Text(AppLocalizations.of(context)!.signatureResult),
        leading: IconButton(
          icon: Icon(Icons.close, color: c.text),
          onPressed: () => context.go('/'),
        ),
      ),
      body: GridBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // ── Status icon ──────────────────────────────────────
                Icon(
                  isSuccess ? Icons.check_circle : Icons.error,
                  size: 64,
                  // Light's lime washes out on the white neo page; the deeper
                  // accent green reads there. Dark keeps the brand lime.
                  color: isSuccess
                      ? c.accent
                      : c.error,
                ),
                const SizedBox(height: 12),
                Text(
                  isSuccess ? AppLocalizations.of(context)!.transactionApproved : 'Signing Failed',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: c.neobrutalism ? FontWeight.w700 : FontWeight.w600,
                    color: c.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppLocalizations.of(context)!.chainLabel(chain),
                  style: TextStyle(
                    color: c.accent,
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 24),

                // ── Details card ─────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    child: SizedBox(
                      width: double.infinity,
                      child: NeoCard(
                        // Dark restores the original hairline card.
                        legacyEdge: c.border.withAlpha(80),
                        // No horizontal padding in neo — each row carries its own
                        // via [_hpad] so the row rules span the card edge to
                        // edge. Vertical padding stays on the card.
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Signing address
                            _hpad(c, _resultRow(
                              c, AppLocalizations.of(context)!.signingAddress,
                              signingAddress.length > 14
                                  ? '${signingAddress.substring(0, 8)}...${signingAddress.substring(signingAddress.length - 6)}'
                                  : signingAddress,
                            )),
                            const SizedBox(height: 10),
                            _separator(c),
                            const SizedBox(height: 10),

                            // Derivation path
                            _hpad(c, _resultRow(c, AppLocalizations.of(context)!.derivationPath, derivationPath)),
                            const SizedBox(height: 10),
                            _separator(c),
                            const SizedBox(height: 10),

                            // To address (ETH/PERSONAL)
                            if (txType == 'eth_tx' && toAddr != null) ...[
                              _hpad(c, _resultRow(c, AppLocalizations.of(context)!.to, toAddr)),
                              const SizedBox(height: 10),
                              _separator(c),
                              const SizedBox(height: 10),
                            ],

                            // Value (ETH)
                            if (txType == 'eth_tx' && value != null) ...[
                              _hpad(c, _resultRow(c, AppLocalizations.of(context)!.value, '${weiToEth(value)} ETH')),
                              const SizedBox(height: 10),
                              _separator(c),
                              const SizedBox(height: 10),
                            ],

                            // Personal message
                            if (txType == 'personal_msg')
                              _hpad(c, _resultRow(
                                c, AppLocalizations.of(context)!.messageLabel,
                                (result['message'] as String? ?? '').length > 40
                                    ? '${(result['message'] as String? ?? '').substring(0, 40)}...'
                                    : result['message'] as String? ?? '',
                              )),
                            if (txType == 'personal_msg') ...[
                              const SizedBox(height: 10),
                              _separator(c),
                              const SizedBox(height: 10),
                            ],

                            // Signature hex (expandable)
                            _hpad(c, _buildSignatureSection(c, signatureHex)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Done button ──────────────────────────────────────
                if (c.neobrutalism)
                  NeoButton(
                    label: AppLocalizations.of(context)!.done,
                    expanded: true,
                    onTap: () {
                      widget.appState?.clearLastSignResult();
                      context.go('/');
                    },
                  )
                else
                  PrimaryButton(
                    label: AppLocalizations.of(context)!.done,
                    onTap: () {
                      widget.appState?.clearLastSignResult();
                      context.go('/');
                    },
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignatureSection(ColorTokens c, String signatureHex) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: c.mutedText(150),
              ),
              const SizedBox(width: 4),
              Text(
                AppLocalizations.of(context)!.rawSignature,
                style: TextStyle(
                  color: c.mutedText(150),
                  fontSize: 13,
                  fontWeight:
                      c.neobrutalism ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              const Spacer(),
              // Copy button
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: '0x$signatureHex'));
                  AppToast.show(
                    context,
                    message: AppLocalizations.of(context)!.copiedToClipboard,
                  );
                },
                child: Icon(
                  Icons.copy,
                  size: 16,
                  color: c.accent,
                ),
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          // Light outlines the hex as data to be checked; dark keeps the
          // original plain filled block.
          if (c.neobrutalism)
            SizedBox(
              width: double.infinity,
              child: NeoCodeBlock(
                padding: const EdgeInsets.all(12),
                child: _signatureText(c, signatureHex),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.bg,
                borderRadius: BorderRadius.circular(R.sm),
              ),
              child: _signatureText(c, signatureHex),
            ),
        ],
      ],
    );
  }

  Widget _signatureText(ColorTokens c, String signatureHex) {
    return SelectableText(
      '0x$signatureHex',
      style: TextStyle(
        color: c.text.withAlpha(200),
        fontSize: 11,
        fontFamily: 'monospace',
        height: 1.5,
      ),
    );
  }

  /// Horizontal inset for a top-level row. The neo card carries no horizontal
  /// padding of its own, so each row adds the inset here, leaving the
  /// [Neo.edge] rules between rows edge to edge. No-op in the legacy chrome,
  /// where the card still owns the inset.
  Widget _hpad(ColorTokens c, Widget child) {
    if (c.neobrutalism) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: child,
      );
    }
    return child;
  }

  /// Hairline rule between detail rows. In neo (light) it becomes the
  /// full-weight brand rule used elsewhere; dark keeps the inset hairline.
  Widget _separator(ColorTokens c) =>
      neoRule(c, legacy: Container(height: 1, color: c.border.withAlpha(60)));

  static Widget _resultRow(ColorTokens c, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              color: c.mutedText(130),
              fontSize: 13,
              fontWeight:
                  c.neobrutalism ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(
              color: c.text,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
