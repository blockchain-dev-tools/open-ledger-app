import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../theme/widgets/brand_mark.dart';
import '../../widgets/common/grid_background.dart';
import '../../widgets/common/neo_card.dart';
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

  @override
  void initState() {
    super.initState();
    _reflectPersistedLockout();
  }

  /// A wallet that is already locked out — five failures anywhere, and the
  /// counter survives restarts — must show the lockout view on entry, not
  /// after the user types a full PIN into a pad that can never open anything.
  Future<void> _reflectPersistedLockout() async {
    final ws = widget.walletService;
    if (ws == null) return;

    bool locked;
    try {
      locked = await ws.isLocked();
    } catch (_) {
      // Unreadable counter: keep normal PIN entry rather than inventing a
      // lockout.
      return;
    }

    if (!mounted || !locked) return;
    setState(() => _lockedOut = true);
  }

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
          // Start the foreground idle window for this session (T-004).
          widget.appState?.onSessionStarted();
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

  /// Confirms the destructive reset before wiping every key (T-019).
  ///
  /// Both the lockout view and the "forgot PIN" link land here; the dialog
  /// spells out that the recovery phrase is the only way back in.
  Future<void> _confirmResetWallet() async {
    final c = Theme.of(context).brightness == Brightness.dark
        ? ColorTokens.dark
        : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(l10n.resetWalletTitle, style: TextStyle(color: c.text)),
        content: Text(
          l10n.resetWalletConfirm,
          style: TextStyle(color: c.text.withAlpha(200), fontSize: 14),
        ),
        actions: [
          TextButton(
            key: const Key('reset-wallet-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              l10n.cancel,
              style: TextStyle(color: c.text.withAlpha(150)),
            ),
          ),
          TextButton(
            key: const Key('reset-wallet-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.reset, style: TextStyle(color: c.error)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) await _resetWallet();
  }

  /// Resets the wallet and navigates to Welcome screen via GoRouter.
  ///
  /// Uses [IWalletService.resetAll] — reached only from the confirmed reset
  /// path, it must clear **every** tier and credential, not just a session.
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
        // Light follows the neo page tint (pale lime) so the reference grid
        // reads as paper ruling; dark's `groupedBg` equals `bg`, so this only
        // affects light mode.
        backgroundColor: c.groupedBg,
        body: GridBackground(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Identity / state mark ─────────────────────────
                      // Locked out: a single lock glyph replaces the brand
                      // mark, so the page never shows two logos at once.
                      if (_lockedOut)
                        Icon(Icons.lock, size: 56, color: c.error)
                      else
                        const BrandMark(size: 80),

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
                            // Neo text runs heavier so the line reads as a hard
                            // label; dark keeps the regular weight.
                            fontWeight: c.neobrutalism
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),

                      // ── PIN entry, or the lockout explanation ─────────
                      // A locked wallet has nothing left to type: no dots and
                      // no pad, just the state, its consequence and the reset
                      // exit.
                      if (!_lockedOut) ...[
                        const SizedBox(height: 28),

                        PinShakeWrapper(
                          shaking: _shaking,
                          child: PinDotIndicator(
                            length: _maxPinLength,
                            filledCount: _pin.length,
                          ),
                        ),

                        const SizedBox(height: 10),

                        const SizedBox(height: 32),

                        PinNumberPad(
                          onDigit: _onDigitTap,
                          onBackspace: _onBackspaceTap,
                          keyPrefix: 'unlock',
                        ),

                        const SizedBox(height: 24),

                        // ── Forgot PIN ──────────────────────────────────
                        GestureDetector(
                          key: const Key('forgot-pin'),
                          onTap: _confirmResetWallet,
                          child: Text(
                            l10n.forgotPin,
                            style: TextStyle(
                              // Neo inverts the muted grey link to a heavy
                              // black one; dark keeps the thin grey underline.
                              color: c.mutedText(120),
                              fontSize: 14,
                              fontWeight: c.neobrutalism
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                              decoration: TextDecoration.underline,
                              decorationColor: c.neobrutalism
                                  ? c.neoEdge
                                  : c.text.withAlpha(80),
                              decorationThickness: c.neobrutalism ? 2 : null,
                            ),
                          ),
                        ),
                      ] else
                        _buildLockoutView(c, l10n),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Lockout view after max attempts exceeded.
  ///
  /// One mark (the lock above the title), one title, then why it is locked,
  /// what a reset costs, and the single destructive action — no repeated
  /// headline and no label that only restates the button.
  Widget _buildLockoutView(ColorTokens c, AppLocalizations l10n) {
    return Column(
      children: [
        Text(
          l10n.lockedOutReason,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.text,
            fontSize: 15,
            height: 1.5,
            fontWeight: c.neobrutalism ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.lockedOutConsequence,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.mutedText(150),
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),
        GestureDetector(
          key: const Key('reset-wallet'),
          onTap: _confirmResetWallet,
          child: NeoCard(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            // Dark restores the original error-tinted rounded block; light
            // renders the neo block (black outline + hard shadow) with the
            // destructive label in red.
            legacyBackground: c.error.withAlpha(30),
            legacyEdge: c.error.withAlpha(100),
            legacyEdgeWidth: 1,
            legacyRadius: R.lg,
            child: Text(
              l10n.resetWallet,
              style: TextStyle(
                color: c.error,
                fontWeight: c.neobrutalism ? FontWeight.w700 : FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
