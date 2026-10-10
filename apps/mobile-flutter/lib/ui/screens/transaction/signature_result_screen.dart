import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../utils/formatting.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/app_toast.dart';
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
    final c = ColorTokens.dark;
    final result = widget.previewResult ?? widget.appState?.lastSignResult;

    // If no result, show redirect to vault.
    if (result == null) {
      return Scaffold(
        backgroundColor: c.bg,
        body: const Center(child: CircularProgressIndicator()),
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
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.signatureResult),
        leading: IconButton(
          icon: Icon(Icons.close, color: c.text),
          onPressed: () => context.go('/'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // ── Status icon ──────────────────────────────────────
              Icon(
                isSuccess ? Icons.check_circle : Icons.error,
                size: 64,
                color: isSuccess ? c.primary : c.error,
              ),
              const SizedBox(height: 12),
              Text(
                isSuccess ? AppLocalizations.of(context)!.transactionApproved : 'Signing Failed',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: c.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppLocalizations.of(context)!.chainLabel(chain),
                style: TextStyle(color: c.primary, fontSize: 14),
              ),

              const SizedBox(height: 24),

              // ── Details card ─────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(R.lg),
                      border: Border.all(color: c.border.withAlpha(80)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Signing address
                        _resultRow(
                          c, AppLocalizations.of(context)!.signingAddress,
                          signingAddress.length > 14
                              ? '${signingAddress.substring(0, 8)}...${signingAddress.substring(signingAddress.length - 6)}'
                              : signingAddress,
                        ),
                        const SizedBox(height: 10),
                        Container(height: 1, color: c.border.withAlpha(60)),
                        const SizedBox(height: 10),

                        // Derivation path
                        _resultRow(c, AppLocalizations.of(context)!.derivationPath, derivationPath),
                        const SizedBox(height: 10),
                        Container(height: 1, color: c.border.withAlpha(60)),
                        const SizedBox(height: 10),

                        // To address (ETH/PERSONAL)
                        if (txType == 'eth_tx' && toAddr != null) ...[
                          _resultRow(c, AppLocalizations.of(context)!.to, toAddr),
                          const SizedBox(height: 10),
                          Container(height: 1, color: c.border.withAlpha(60)),
                          const SizedBox(height: 10),
                        ],

                        // Value (ETH)
                        if (txType == 'eth_tx' && value != null) ...[
                          _resultRow(c, AppLocalizations.of(context)!.value, '${weiToEth(value)} ETH'),
                          const SizedBox(height: 10),
                          Container(height: 1, color: c.border.withAlpha(60)),
                          const SizedBox(height: 10),
                        ],

                        // Personal message
                        if (txType == 'personal_msg')
                          _resultRow(
                            c, AppLocalizations.of(context)!.messageLabel,
                            (result['message'] as String? ?? '').length > 40
                                ? '${(result['message'] as String? ?? '').substring(0, 40)}...'
                                : result['message'] as String? ?? '',
                          ),
                        if (txType == 'personal_msg') ...[
                          const SizedBox(height: 10),
                          Container(height: 1, color: c.border.withAlpha(60)),
                          const SizedBox(height: 10),
                        ],

                        // Signature hex (expandable)
                        _buildSignatureSection(c, signatureHex),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── Done button ──────────────────────────────────────
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
                color: c.text.withAlpha(150),
              ),
              const SizedBox(width: 4),
              Text(
                AppLocalizations.of(context)!.rawSignature,
                style: TextStyle(
                  color: c.text.withAlpha(150),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
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
                child: Icon(Icons.copy, size: 16, color: c.primary),
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: SelectableText(
              '0x$signatureHex',
              style: TextStyle(
                color: c.text.withAlpha(200),
                fontSize: 11,
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
          ),
        ],
      ],
    );
  }

  static Widget _resultRow(ColorTokens c, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(color: c.text.withAlpha(130), fontSize: 13),
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
