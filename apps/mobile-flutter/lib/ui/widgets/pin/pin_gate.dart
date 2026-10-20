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
    this.onLockedOut,
    this.keyPrefix = 'export-pin',
  });

  final IExportService exportService;

  /// Called with the verified PIN; returns the secret view, or `null` when
  /// the secret could not be resolved (the gate stays on the PIN phase).
  final Future<Widget?> Function(String pin) onUnlocked;

  /// Invoked once when the gate is — or becomes — locked out, so the host
  /// screen can leave this route for the unlock screen's lockout view, the
  /// single reset exit (T-003). Not called while attempts remain.
  final VoidCallback? onLockedOut;

  /// Prefix for the pad's widget keys (`$keyPrefix-btn-1`, …).
  final String keyPrefix;

  @override
  State<PinGate> createState() => _PinGateState();
}

class _PinGateState extends State<PinGate> {
  static const int _maxPinLength = 6;

  final List<int> _pin = [];
  bool _shaking = false;

  /// The global persisted failed-attempt counter, shared with the unlock
  /// gate — displayed as-is, never a screen-local count (T-003). Re-read
  /// after every failure so a restart-proof truth backs the display.
  late int _attempts = widget.exportService.pinAttempts;
  late final int _maxAttempts = widget.exportService.maxPinAttempts;

  /// Derived from the persisted counter: the 5th failure anywhere locks the
  /// wallet for good, so the gate reflects it instead of inventing a local
  /// lockout that silently resets on exit.
  bool get _lockedOut => _attempts >= _maxAttempts;

  /// The revealed secret view, built once the PIN checks out.
  Widget? _unlocked;

  /// Whether [PinGate.onLockedOut] already fired — the host route only needs
  /// to be left once.
  bool _lockoutReported = false;

  @override
  void initState() {
    super.initState();
    // Entering the gate on an already-locked wallet must not render a PIN pad
    // that can never succeed: hand over to the reset exit right away.
    if (_lockedOut) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reportLockout();
      });
    }
  }

  void _reportLockout() {
    if (_lockoutReported) return;
    _lockoutReported = true;
    widget.onLockedOut?.call();
  }

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
      _attempts = widget.exportService.pinAttempts;
      _shaking = true;
    });

    // The failure that exhausted the counter locks the whole wallet — leave
    // this route for the reset exit instead of sitting on a dead pad.
    if (_lockedOut) _reportLockout();

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
        if (!_lockedOut && _attempts > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${l10n.attemptsRemaining}: ${_maxAttempts - _attempts}/$_maxAttempts',
              style: TextStyle(
                color: _maxAttempts - _attempts <= 2
                    ? c.error
                    : c.text.withAlpha(130),
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
    // No reset button here on purpose: the unlock screen's lockout view is
    // the single reset exit. The gate only points back to it — no "try again
    // later", there is no cooldown to wait out (T-003).
    return Column(
      children: [
        Text(
          l10n.lockedOut,
          textAlign: TextAlign.center,
          style: TextStyle(color: c.error, fontSize: 15),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.walletLockedHint,
          textAlign: TextAlign.center,
          style: TextStyle(color: c.text.withAlpha(140), fontSize: 14),
        ),
      ],
    );
  }
}
