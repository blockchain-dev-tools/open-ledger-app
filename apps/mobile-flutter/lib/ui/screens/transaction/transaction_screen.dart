import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/models/apdu_message.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../utils/formatting.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/tx_details_card.dart';

/// Sign approval UI — shows transaction content and signing address
/// for the user to approve or reject.
///
/// Reads [PendingSignRequest] from [AppState.pendingRequest].
/// Displays a 60-second timeout countdown.
class TransactionScreen extends StatefulWidget {
  final AppState? appState;

  /// Optional preview request shown when no [AppState] is attached
  /// (design gallery). Takes precedence over `appState.pendingRequest`.
  final PendingSignRequest? previewRequest;

  const TransactionScreen({super.key, this.appState, this.previewRequest});

  @override
  State<TransactionScreen> createState() => _TransactionScreenState();
}

class _TransactionScreenState extends State<TransactionScreen> {
  Timer? _countdownTimer;
  int _secondsRemaining = 60;

  AppState? get _appState => widget.appState;

  /// The request to display — preview data first, then live app state.
  PendingSignRequest? get _pendingRequest =>
      widget.previewRequest ?? widget.appState?.pendingRequest;

  @override
  void initState() {
    super.initState();
    TxDetailsCard.loadChainNames().then((_) {
      if (mounted) setState(() {});
    });
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _secondsRemaining = 60;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _secondsRemaining--;
      });
      if (_secondsRemaining <= 0) {
        _countdownTimer?.cancel();
        _onTimeout();
      }
    });
  }

  Future<void> _onTimeout() async {
    final appState = _appState;
    if (appState == null) return; // Preview mode: no auto-dismiss.
    await appState.rejectSign();
    if (mounted) {
      context.go('/');
    }
  }

  Future<void> _onApprove() async {
    _countdownTimer?.cancel();
    final appState = _appState;
    if (appState == null) return; // Preview mode: no-op.
    await appState.approveSign();
    if (mounted) {
      context.go('/signature-result');
    }
  }

  Future<void> _onReject() async {
    _countdownTimer?.cancel();
    final appState = _appState;
    if (appState == null) return; // Preview mode: no-op.
    await appState.rejectSign();
    if (mounted) {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ColorTokens.dark;
    final req = _pendingRequest;

    // If no pending request, show a spinner or redirect.
    if (req == null) {
      return Scaffold(
        backgroundColor: c.bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.signTransaction),
        actions: [
          // Countdown timer
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '⏱ ${_secondsRemaining}s',
                style: TextStyle(
                  color: _secondsRemaining <= 10 ? c.error : c.text.withAlpha(180),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // ── Header ──────────────────────────────────────────
              _buildHeader(c, req),
              const SizedBox(height: 20),

              // ── Signing address ─────────────────────────────────
              _buildAddressCard(c, req.signingAddress, req.chain),
              const SizedBox(height: 16),

              // ── Transaction details ─────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  child: TxDetailsCard(
                    parsedData: req.parsedData,
                    payloadHex: req.payloadHex,
                    c: c,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Approve / Reject ────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      key: const Key('sign-reject'),
                      label: AppLocalizations.of(context)!.reject,
                      onTap: _onReject,
                      outline: true,
                      outlineColor: c.error,
                      textColor: c.error,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: PrimaryButton(
                      key: const Key('sign-approve'),
                      label: AppLocalizations.of(context)!.approve,
                      onTap: _onApprove,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorTokens c, PendingSignRequest req) {
    return Column(
      children: [
        Icon(Icons.shield_outlined, size: 48, color: c.primary),
        const SizedBox(height: 12),
        Text(
          AppLocalizations.of(context)!.transactionDetails,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: c.text,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          AppLocalizations.of(context)!.chainLabel(req.chain),
          style: TextStyle(color: c.primary, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildAddressCard(ColorTokens c, String address, String chain) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: c.border.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.key, size: 16, color: c.primary.withAlpha(200)),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.of(context)!.from,
                style: TextStyle(color: c.text.withAlpha(150), fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText.rich(
            _highlightedAddress(address, c),
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 6),
          Text(
            _pendingRequest?.derivationPath ?? '',
            style: TextStyle(
              color: c.text.withAlpha(100),
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  /// Build a [TextSpan] with first 6 and last 6 chars bold+primary.
  TextSpan _highlightedAddress(String address, ColorTokens c) {
    if (address.length <= 12) {
      return TextSpan(text: address, style: TextStyle(color: c.text));
    }
    final prefix = address.substring(0, 6);
    final middle = address.substring(6, address.length - 6);
    final suffix = address.substring(address.length - 6);
    return TextSpan(
      children: [
        TextSpan(
          text: prefix,
          style: TextStyle(color: c.primary, fontWeight: FontWeight.bold),
        ),
        TextSpan(text: middle, style: TextStyle(color: c.text)),
        TextSpan(
          text: suffix,
          style: TextStyle(color: c.primary, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
