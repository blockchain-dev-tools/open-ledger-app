import 'package:flutter/material.dart';

import '../../../core/interfaces/export_service.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import 'pin_dot_indicator.dart';
import 'pin_number_pad.dart';
import 'pin_shake_wrapper.dart';

/// Two-phase PIN gate for the secret-bearing export screens (contract I6).
///
/// Phase 1 shows the number pad; phase 2 renders whatever [onUnlocked]
/// returns. The PIN is re-verified **on the spot** — a session that is
/// already unlocked does not count, and only the current tier's PIN is
/// accepted ([IExportService.verifySessionPin]).
///
/// Reused by the recovery-phrase QR and the per-account key QR. The gallery
/// renders those screens without a gate (a `null` export service), so the
/// reviewed visuals are the same widgets the app ships.
class PinGate extends StatefulWidget {
  const PinGate({
    super.key,
    required this.exportService,
    required this.onUnlocked,
    this.keyPrefix = 'export-pin',
  });

  final IExportService exportService;

  /// Called with the verified PIN; returns the secret view, or `null` when
  /// the secret could not be resolved (the gate stays on the PIN phase).
  final Future<Widget?> Function(String pin) onUnlocked;

  /// Prefix for the pad's widget keys (`$keyPrefix-btn-1`, …).
  final String keyPrefix;

  @override
  State<PinGate> createState() => _PinGateState();
}

class _PinGateState extends State<PinGate> {
  static const int _maxPinLength = 6;
  static const int _maxAttempts = 5;

  final List<int> _pin = [];
  int _attemptCount = 0;
  bool _shaking = false;
  bool _lockedOut = false;

  /// The revealed secret view, built once the PIN checks out.
  Widget? _unlocked;

  void _onDigitTap(int digit) {
    if (_lockedOut || _unlocked != null) return;
    if (_pin.length >= _maxPinLength) return;

    setState(() => _pin.add(digit));
    if (_pin.length == _maxPinLength) {
      _verifyPin();
    }
  }

  void _onBackspaceTap() {
    if (_lockedOut || _unlocked != null) return;
    if (_pin.isEmpty) return;
    setState(() => _pin.removeLast());
  }

  Future<void> _verifyPin() async {
    final entered = _pin.join();

    // `verifySessionPin` throws on a locked wallet — treat any throw as a
    // failed attempt rather than crashing inside a GestureDetector callback
    // (whose exceptions are swallowed silently).
    Widget? view;
    try {
      if (await widget.exportService.verifySessionPin(entered)) {
        view = await widget.onUnlocked(entered);
      }
    } catch (_) {
      view = null;
    }

    if (!mounted) return;

    if (view != null) {
      setState(() => _unlocked = view);
      return;
    }

    setState(() {
      _attemptCount++;
      _shaking = true;
      if (_attemptCount >= _maxAttempts) {
        _lockedOut = true;
      }
    });

    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() {
        _pin.clear();
        _shaking = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final revealed = _unlocked;
    if (revealed != null) return revealed;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.surface,
            border: Border.all(color: c.border),
          ),
          alignment: Alignment.center,
          child: Icon(
            _lockedOut ? Icons.lock : Icons.lock_outline,
            size: 30,
            color: _lockedOut ? c.error : c.text.withAlpha(150),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _lockedOut ? l10n.lockedOut : l10n.unlockTitle,
          style: TextStyle(
            color: _lockedOut ? c.error : c.text,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        if (!_lockedOut)
          Text(
            l10n.enterPinToReveal,
            style: TextStyle(color: c.text.withAlpha(140), fontSize: 14),
          ),
        if (!_lockedOut && _attemptCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${l10n.attemptsRemaining}: ${_maxAttempts - _attemptCount}/$_maxAttempts',
              style: TextStyle(
                color: _attemptCount >= 3 ? c.error : c.text.withAlpha(130),
                fontSize: 13,
              ),
            ),
          ),
        const SizedBox(height: 24),
        PinShakeWrapper(
          shaking: _shaking,
          child: PinDotIndicator(
            length: _maxPinLength,
            filledCount: _pin.length,
          ),
        ),
        const SizedBox(height: 10),
        if (_shaking && !_lockedOut)
          Text(l10n.incorrectPin, style: TextStyle(color: c.error, fontSize: 14)),
        const SizedBox(height: 28),
        if (_lockedOut)
          _buildLockout(c, l10n)
        else
          PinNumberPad(
            onDigit: _onDigitTap,
            onBackspace: _onBackspaceTap,
            keyPrefix: widget.keyPrefix,
          ),
      ],
    );
  }

  Widget _buildLockout(ColorTokens c, AppLocalizations l10n) {
    return Column(
      children: [
        Text(
          l10n.lockedOut,
          textAlign: TextAlign.center,
          style: TextStyle(color: c.error, fontSize: 15),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.pleaseTryAgainLater,
          textAlign: TextAlign.center,
          style: TextStyle(color: c.text.withAlpha(140), fontSize: 14),
        ),
      ],
    );
  }
}
