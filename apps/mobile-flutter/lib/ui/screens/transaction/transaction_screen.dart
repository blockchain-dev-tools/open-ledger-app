import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/models/apdu_message.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../utils/formatting.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/grid_background.dart';
import '../../widgets/common/neo_app_bar.dart';
import '../../widgets/common/neo_button.dart';
import '../../widgets/common/neo_card.dart';
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
    final c = Theme.of(context).brightness == Brightness.dark
        ? ColorTokens.dark
        : ColorTokens.light;
    final req = _pendingRequest;

    // If no pending request, show a spinner or redirect.
    if (req == null) {
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

    return Scaffold(
      // Light follows the neo page tint (pale lime) so the reference grid
      // reads as paper ruling; dark's `groupedBg` equals `bg`, so this only
      // affects light mode.
      backgroundColor: c.groupedBg,
      appBar: neoAppBar(
        c: c,
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
      body: GridBackground(
        child: SafeArea(
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
                      neo: c.neobrutalism,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Approve / Reject ────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: c.neobrutalism
                          ? NeoButton(
                              key: const Key('sign-reject'),
                              label: AppLocalizations.of(context)!.reject,
                              quiet: true,
                              expanded: true,
                              onTap: _onReject,
                            )
                          : PrimaryButton(
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
                      child: c.neobrutalism
                          ? NeoButton(
                              key: const Key('sign-approve'),
                              label: AppLocalizations.of(context)!.approve,
                              expanded: true,
                              onTap: _onApprove,
                            )
                          : PrimaryButton(
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
      ),
    );
  }

  Widget _buildHeader(ColorTokens c, PendingSignRequest req) {
    return Column(
      children: [
        Icon(
          Icons.shield_outlined,
          size: 48,
          // Light's lime washes out on the white neo page; the deeper accent
          // green reads there. Dark keeps the brand lime.
          color: c.neobrutalism ? c.accent : c.primary,
        ),
        const SizedBox(height: 12),
        Text(
          AppLocalizations.of(context)!.transactionDetails,
          style: TextStyle(
            fontSize: 20,
            fontWeight: c.neobrutalism ? FontWeight.w700 : FontWeight.w600,
            color: c.text,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          AppLocalizations.of(context)!.chainLabel(req.chain),
          style: TextStyle(
            color: c.neobrutalism ? c.accent : c.primary,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildAddressCard(ColorTokens c, String address, String chain) {
    return SizedBox(
      width: double.infinity,
      child: NeoCard(
        // Dark restores the original hairline card.
        legacyEdge: c.border.withAlpha(80),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.key,
                  size: 16,
                  color: c.neobrutalism ? c.accent : c.primary.withAlpha(200),
                ),
                const SizedBox(width: 6),
                Text(
                  AppLocalizations.of(context)!.from,
                  style: TextStyle(
                    // Light (neo) prints the label black and bold so it reads as
                    // a key; dark keeps the original muted grey.
                    color: c.neobrutalism ? c.text : c.text.withAlpha(150),
                    fontSize: 13,
                    fontWeight:
                        c.neobrutalism ? FontWeight.w600 : FontWeight.normal,
                  ),
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
                // Light (neo) prints the derivation path in solid text black;
                // dark keeps the original muted tone.
                color: c.neobrutalism ? c.text : c.text.withAlpha(100),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build a [TextSpan] with first 6 and last 6 chars bold+primary.
  TextSpan _highlightedAddress(String address, ColorTokens c) {
    // Light's lime highlights wash out on white; the accent green stands in.
    final highlight = c.neobrutalism ? c.accent : c.primary;
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
          style: TextStyle(color: highlight, fontWeight: FontWeight.bold),
        ),
        TextSpan(text: middle, style: TextStyle(color: c.text)),
        TextSpan(
          text: suffix,
          style: TextStyle(color: highlight, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
