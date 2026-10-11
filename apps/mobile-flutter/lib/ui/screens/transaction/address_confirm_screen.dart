import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/models/apdu_message.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/primary_button.dart';

/// Address display + confirm UI.
///
/// Shown when the host sends ETH GET_PUBLIC_KEY (INS 0x02) with P1=0x01 —
/// on a real Ledger that means "show the address on screen and wait for the
/// user to confirm". Reads [PendingAddressRequest] from
/// [AppState.pendingAddressRequest] and displays a 60-second countdown.
///
/// Approval returns the address over BLE (via [AppState.approveAddress]);
/// rejection returns SW 0x6985 (via [AppState.rejectAddress]). Unlike
/// [TransactionScreen] there is no signature result screen.
class AddressConfirmScreen extends StatefulWidget {
  final AppState? appState;

  /// Optional preview request shown when no [AppState] is attached
  /// (design gallery). Takes precedence over `appState.pendingAddressRequest`.
  final PendingAddressRequest? previewRequest;

  const AddressConfirmScreen({super.key, this.appState, this.previewRequest});

  @override
  State<AddressConfirmScreen> createState() => _AddressConfirmScreenState();
}

class _AddressConfirmScreenState extends State<AddressConfirmScreen> {
  Timer? _countdownTimer;
  int _secondsRemaining = 60;

  AppState? get _appState => widget.appState;

  /// The request to display — preview data first, then live app state.
  PendingAddressRequest? get _pendingRequest =>
      widget.previewRequest ?? widget.appState?.pendingAddressRequest;

  @override
  void initState() {
    super.initState();
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
    await appState.rejectAddress();
    if (mounted) context.go('/');
  }

  Future<void> _onApprove() async {
    _countdownTimer?.cancel();
    final appState = _appState;
    if (appState == null) return; // Preview mode: no-op.
    await appState.approveAddress();
    if (mounted) context.go('/');
  }

  Future<void> _onReject() async {
    _countdownTimer?.cancel();
    final appState = _appState;
    if (appState == null) return; // Preview mode: no-op.
    await appState.rejectAddress();
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).brightness == Brightness.dark
        ? ColorTokens.dark
        : ColorTokens.light;
    final req = _pendingRequest;
    final l10n = AppLocalizations.of(context)!;

    if (req == null) {
      return Scaffold(
        backgroundColor: c.bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(l10n.address),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '⏱ $_secondsRemaining' 's',
                style: TextStyle(
                  color: _secondsRemaining <= 10
                      ? c.error
                      : c.text.withAlpha(180),
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
              Icon(Icons.visibility_outlined, size: 48, color: c.primary),
              const SizedBox(height: 12),
              Text(
                l10n.address,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: c.text,
                ),
              ),
              const SizedBox(height: 20),

              // ── Address card ────────────────────────────────────
              _buildAddressCard(c, req.address, req.derivationPath),

              const Spacer(),

              // ── Approve / Reject ────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      label: l10n.reject,
                      onTap: _onReject,
                      outline: true,
                      outlineColor: c.error,
                      textColor: c.error,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: PrimaryButton(
                      label: l10n.approve,
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

  Widget _buildAddressCard(ColorTokens c, String address, String path) {
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
                AppLocalizations.of(context)!.address,
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
            path,
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
