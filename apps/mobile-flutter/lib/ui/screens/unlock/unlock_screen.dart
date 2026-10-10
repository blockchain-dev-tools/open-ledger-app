import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../theme/widgets/brand_shield.dart';
import '../../widgets/pin/pin_number_pad.dart';
import '../../widgets/pin/pin_dot_indicator.dart';
import '../../widgets/pin/pin_shake_wrapper.dart';
import '../../../core/interfaces/wallet_service.dart';
import '../../../app/app_state.dart';

/// PIN entry screen for cold-start wallet unlock.
///
/// User enters a 6-digit PIN via on-screen number pad.
/// Max 5 attempts before lockout. On 5th failure, "Reset Wallet" option appears.
/// PIN verification uses [walletService.verifyPin].
///
/// Ported from the original TypeScript implementation.
class UnlockScreen extends StatefulWidget {
  /// Wallet service for PIN verification and unlock.
  final IWalletService? walletService;

  /// App state — loads persisted history after unlock and coordinates reset.
  final AppState? appState;

  const UnlockScreen({super.key, this.walletService, this.appState});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final List<int> _pin = [];
  bool _verifying = false;
  bool _shaking = false;
  bool _lockedOut = false;
  String? _error;

  static const int _maxPinLength = 6;
  static const int _maxAttempts = 5;

  /// Adds [digit] to the PIN entry (max 6).
  void _onDigitTap(int digit) {
    if (_lockedOut || _verifying) return;
    if (_pin.length >= _maxPinLength) return;

    setState(() {
      _pin.add(digit);
    });

    // Auto-verify when PIN reaches 6 digits.
    if (_pin.length == _maxPinLength) {
      _verifyPin();
    }
  }

  /// Removes the last entered digit.
  void _onBackspaceTap() {
    if (_lockedOut) return;
    if (_pin.isEmpty) return;

    setState(() {
      _pin.removeLast();
    });
  }

  /// Verifies the entered PIN against [walletService].
  Future<void> _verifyPin() async {
    final entered = _pin.join();
    final ws = widget.walletService;
    if (ws == null) {
      // No wallet service — navigate to vault (dev mode).
      if (mounted) context.go('/');
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      // Check lockout first.
      if (await ws.isLocked()) {
        setState(() {
          _lockedOut = true;
          _verifying = false;
        });
        return;
      }

      final ok = await ws.verifyPin(entered);
      if (!mounted) return;

      if (ok) {
        // Success — unlock wallet and navigate to Vault.
        try {
          await ws.unlockWallet(entered);
          // A `wipe` stand-in erased the tier it replaced; those vaults' history
          // went with them via `onVaultsDestroyed`, so only the records of the
          // vault this session just opened need loading.
          await widget.appState?.loadHistory();
          if (mounted) context.go('/');
        } on StateError catch (e) {
          // Internal error during unlock (corrupted data, etc.).
          if (mounted) {
            setState(() {
              _error = e.message;
              _shaking = true;
            });
            _resetPinAfterDelay();
          }
        }
      } else {
        // Failure — PIN did not match. Increment attempts and trigger shake.
        final attempts = ws.pinAttempts;
        final remaining = _maxAttempts - attempts;
        setState(() {
          if (remaining <= 0) {
            _lockedOut = true;
          }
          _shaking = true;
          _error = remaining > 0
              ? '${AppLocalizations.of(context)!.incorrectPin} ($remaining attempt${remaining == 1 ? '' : 's'} remaining)'
              : AppLocalizations.of(context)!.lockedOut;
        });
        _resetPinAfterDelay();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context)!.unexpectedError;
          _shaking = true;
        });
        _resetPinAfterDelay();
      }
    } finally {
      if (mounted) {
        setState(() => _verifying = false);
      }
    }
  }

  /// Resets the wallet and navigates to Welcome screen via GoRouter.
  ///
  /// Uses [IWalletService.resetAll] — this path is only reachable when locked
  /// out, so it must clear **every** tier and credential, not just a session.
  Future<void> _resetWallet() async {
    final appState = widget.appState;
    if (appState != null) {
      await appState.resetWallet();
    } else {
      await widget.walletService?.resetAll();
    }
    if (mounted) context.go('/welcome');
  }

  void _resetPinAfterDelay() {
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() {
          _pin.clear();
          _shaking = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        systemStatusBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Brand Mark ────────────────────────────────────
                    const BrandShield(size: 80),

                    const SizedBox(height: 32),

                    // ── Title ─────────────────────────────────────────
                    Text(
                      _lockedOut ? l10n.lockedOut : l10n.unlockTitle,
                      style: TextStyle(
                        color: _lockedOut ? c.error : c.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Error message (if any) ─────────────────────────
                    if (_error != null && !_lockedOut)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: c.error,
                          fontSize: 14,
                        ),
                      ),

                    const SizedBox(height: 28),

                    // ── PIN Dots ──────────────────────────────────────
                    PinShakeWrapper(
                      shaking: _shaking,
                      child: PinDotIndicator(
                        length: _maxPinLength,
                        filledCount: _pin.length,
                      ),
                    ),

                    const SizedBox(height: 10),

                    const SizedBox(height: 32),

                    // ── Number Pad or Lockout ─────────────────────────
                    if (_lockedOut)
                      _buildLockoutView(c, l10n)
                    else
                      PinNumberPad(
                        onDigit: _onDigitTap,
                        onBackspace: _onBackspaceTap,
                        keyPrefix: 'unlock',
                      ),

                    const SizedBox(height: 24),

                    // ── Forgot PIN ────────────────────────────────────
                    if (!_lockedOut)
                      GestureDetector(
                        key: const Key('forgot-pin'),
                        onTap: _resetWallet,
                        child: Text(
                          l10n.forgotPin,
                          style: TextStyle(
                            color: c.text.withAlpha(120),
                            fontSize: 14,
                            decoration: TextDecoration.underline,
                            decorationColor: c.text.withAlpha(80),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Lockout view after max attempts exceeded.
  Widget _buildLockoutView(ColorTokens c, AppLocalizations l10n) {
    return Column(
      children: [
        Icon(Icons.lock, size: 48, color: c.error),
        const SizedBox(height: 16),
        Text(
          l10n.lockedOut,
          textAlign: TextAlign.center,
          style: TextStyle(color: c.error, fontSize: 15),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.resetWallet,
          textAlign: TextAlign.center,
          style: TextStyle(color: c.text.withAlpha(140), fontSize: 14),
        ),
        const SizedBox(height: 24),
        GestureDetector(
          key: const Key('reset-wallet'),
          onTap: _resetWallet,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            decoration: BoxDecoration(
              color: c.error.withAlpha(30),
              borderRadius: BorderRadius.circular(R.lg),
              border: Border.all(color: c.error.withAlpha(100)),
            ),
            child: Text(
              l10n.reset,
              style: TextStyle(
                color: c.error,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
