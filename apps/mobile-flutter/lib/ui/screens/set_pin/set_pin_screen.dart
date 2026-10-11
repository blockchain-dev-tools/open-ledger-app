import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/pin/pin_number_pad.dart';
import '../../widgets/pin/pin_dot_indicator.dart';
import '../../widgets/pin/pin_shake_wrapper.dart';
import '../../../core/interfaces/wallet_service.dart';
import '../../../core/models/vault.dart';
import '../../../app/app_state.dart';

/// Two-phase 6-digit PIN entry for wallet creation or PIN change.
///
/// Modes (detected by whether [mnemonic] is provided):
/// - **Create** (`mnemonic != null`): Phase 1 (enter new PIN) → Phase 2
///   (confirm PIN). On match → setup wallet → `context.go('/')`.
/// - **Change** (`mnemonic == null`): Phase 1 (enter old PIN) → Phase 2
///   (enter new PIN) → Phase 3 (confirm new PIN). Old PIN verified against
///   [walletService]. On success → `context.go('/')`.
///
/// The 3×4 number pad and 6-dot indicators mirror [UnlockScreen] styling.
///
/// Ported from the original TypeScript implementation.
class SetPinScreen extends StatefulWidget {
  /// Optional mnemonic — when provided, the screen runs in "create wallet PIN"
  /// mode.  When `null`, the screen runs in "change PIN" mode.
  final String? mnemonic;

  /// Optional wallet service for PIN verification and storage.
  ///
  /// When `null` (e.g. during standalone testing), PINs are accepted without
  /// cryptographic verification and wallet persistence is skipped.
  final IWalletService? walletService;

  /// Optional BIP-39 passphrase for the seed derivation.
  /// Passed through to [WalletService.setupWallet] when non-empty.
  final String passphrase;

  /// When `true`, the flow adds a new vault to the current session
  /// (`walletService.addVault`) instead of creating the first wallet. The
  /// single-phase PIN entry re-authenticates the existing session credential.
  final bool addVault;

  /// How the mnemonic originated (ADR-011 §4); recorded on the created vault.
  final VaultSource source;

  /// BIP-39 wordlist index for the Enigma riddle→index lookup. Only
  /// meaningful when [source] is [VaultSource.enigma]; `0` otherwise.
  final int enigmaLanguage;

  /// App state — loads persisted history after wallet setup.
  final AppState? appState;

  /// Whether to persist the passphrase alongside the mnemonic.
  /// Automatically `true` when [passphrase] is non-empty.
  bool get storePassphrase => passphrase.isNotEmpty;

  const SetPinScreen({
    super.key,
    this.mnemonic,
    this.walletService,
    this.passphrase = '',
    this.addVault = false,
    this.source = VaultSource.imported,
    this.enigmaLanguage = 0,
    this.appState,
  });

  /// `true` when [mnemonic] is non-null and non-empty → create wallet PIN.
  bool get isCreateMode => mnemonic != null && mnemonic!.isNotEmpty;

  @override
  State<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<SetPinScreen> {
  final List<int> _pin = [];
  int _phase = 0;
  String? _firstPin;
  String? _oldPin;
  String? _error;
  bool _shaking = false;

  static const int _pinLength = 6;

  // ── Header labels per mode / phase ──────────────────────────────────

  String _title(AppLocalizations l10n) {
    if (widget.addVault) return l10n.vaultPinPrompt;
    if (widget.isCreateMode) {
      return _phase == 0 ? l10n.setPinTitle : l10n.confirmPin;
    }
    switch (_phase) {
      case 0:
        return l10n.changePinTitle;
      case 1:
        return l10n.enterNewPin;
      case 2:
        return l10n.confirmNewPin;
      default:
        return l10n.changePinTitle;
    }
  }

  String _subtitle(AppLocalizations l10n) {
    if (widget.addVault) return '';
    if (widget.isCreateMode) {
      return _phase == 0 ? l10n.setPinSubtitle : l10n.confirmPinSubtitle;
    }
    switch (_phase) {
      case 0:
        return l10n.enterOldPin;
      case 1:
        return l10n.enterNewPinSubtitle;
      case 2:
        return l10n.confirmNewPinSubtitle;
      default:
        return '';
    }
  }

  // ── Input handlers ──────────────────────────────────────────────────

  void _onDigitTap(int digit) {
    if (_pin.length >= _pinLength) return;
    setState(() {
      _pin.add(digit);
      _error = null;
    });
    if (_pin.length == _pinLength) {
      _onPinComplete();
    }
  }

  void _onBackspaceTap() {
    if (_pin.isEmpty) return;
    setState(() => _pin.removeLast());
  }

  // ── PIN completion logic ────────────────────────────────────────────

  void _onPinComplete() {
    final entered = _pin.join();

    if (widget.addVault) {
      _addVault(entered);
    } else if (widget.isCreateMode) {
      _handleCreateFlow(entered);
    } else {
      _handleChangeFlow(entered);
    }
  }

  void _handleCreateFlow(String entered) {
    if (_phase == 0) {
      // Phase 1 complete — store and move to confirmation.
      _firstPin = entered;
      setState(() {
        _phase = 1;
        _pin.clear();
      });
    } else {
      // Phase 2 (confirm) — must match.
      if (entered == _firstPin) {
        _setupWallet(_firstPin!);
      } else {
        _showError(AppLocalizations.of(context)!.pinMismatch);
        _resetToPhaseZero();
      }
    }
  }

  void _handleChangeFlow(String entered) async {
    if (_phase == 0) {
      // Verify old PIN.
      await _verifyOldPin(entered);
    } else if (_phase == 1) {
      // Store new PIN, move to confirmation.
      _firstPin = entered;
      setState(() {
        _phase = 2;
        _pin.clear();
      });
    } else {
      // Phase 2 (confirm new PIN) — must match.
      if (entered == _firstPin) {
        await _changePin(entered);
      } else {
        _showError(AppLocalizations.of(context)!.pinMismatch);
        // Go back to new-PIN entry.
        if (mounted) {
          setState(() {
            _phase = 1;
            _firstPin = null;
          });
          _resetPinWithDelay();
        }
      }
    }
  }

  // ── Wallet operations ───────────────────────────────────────────────

  Future<void> _setupWallet(String pin) async {
    if (widget.walletService == null || widget.mnemonic == null) {
      // No real wallet service — navigate directly (testing / dev).
      if (mounted) context.go('/');
      return;
    }
    try {
      await widget.walletService!.setupWallet(
        widget.mnemonic!,
        pin: pin,
        passphrase: widget.passphrase,
        storePassphrase: widget.passphrase.isNotEmpty,
        source: widget.source,
        enigmaLanguage: widget.enigmaLanguage,
      );
      await widget.appState?.loadHistory();
      if (mounted) context.go('/');
    } catch (e) {
      debugPrint('[SetPin] setupWallet failed: $e');
      _showError('Failed to setup wallet: $e');
      if (mounted) _resetPinWithDelay();
    }
  }

  /// Add a vault to the current session (single-phase PIN re-auth).
  ///
  /// Unlike [_setupWallet], this never creates the primary credential — it
  /// verifies [pin] against the existing session and appends a new vault.
  Future<void> _addVault(String pin) async {
    if (widget.walletService == null || widget.mnemonic == null) {
      if (mounted) context.go('/');
      return;
    }
    try {
      await widget.walletService!.addVault(
        widget.mnemonic!,
        pin: pin,
        passphrase: widget.passphrase,
        storePassphrase: widget.passphrase.isNotEmpty,
        source: widget.source,
        enigmaLanguage: widget.enigmaLanguage,
      );
      if (mounted) context.go('/');
    } on StateError catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      final message = switch (e.message) {
        'Incorrect PIN' || 'PIN does not match the current wallet.' =>
          l10n.incorrectPin,
        'This wallet is already in this tier.' => l10n.vaultAlreadyInTier,
        _ => e.message,
      };
      _showError(message);
      _resetPinWithDelay();
    } catch (e) {
      debugPrint('[SetPin] addVault failed: $e');
      _showError('Failed to add vault: $e');
      _resetPinWithDelay();
    }
  }

  Future<void> _verifyOldPin(String entered) async {
    if (widget.walletService == null) {
      // No wallet service — accept any PIN for now.
      _oldPin = entered;
      if (mounted) {
        setState(() {
          _phase = 1;
          _pin.clear();
        });
      }
      return;
    }
    // Session-scoped gate: only the current tier's PIN may authorise a change.
    // Another tier's valid PIN is rejected here, instead of being accepted and
    // then failing in `updatePin` with a misleading "Failed to change PIN".
    final ok = await widget.walletService!.verifySessionPin(entered);
    if (!mounted) return;
    if (ok) {
      _oldPin = entered;
      setState(() {
        _phase = 1;
        _pin.clear();
      });
    } else {
      _showError(AppLocalizations.of(context)!.incorrectPin);
      _resetPinWithDelay();
    }
  }

  Future<void> _changePin(String newPin) async {
    if (widget.walletService == null) {
      if (mounted) context.go('/');
      return;
    }
    final bool ok;
    try {
      ok = await widget.walletService!.updatePin(_oldPin!, newPin);
    } on StateError catch (e) {
      // A duplicate PIN is rejected by the wallet layer (tier PINs must stay
      // globally unique). Callbacks here swallow exceptions, so surface it.
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      _showError(
        e.message == 'The new PIN is already in use by another wallet.'
            ? l10n.pinAlreadyInUse
            : 'Failed to change PIN',
      );
      _resetPinWithDelay();
      return;
    }
    if (!mounted) return;
    if (ok) {
      context.go('/');
    } else {
      _showError('Failed to change PIN');
      _resetPinWithDelay();
    }
  }

  // ── UI helpers ──────────────────────────────────────────────────────

  void _showError(String message) {
    setState(() {
      _error = message;
      _shaking = true;
    });
  }

  void _resetToPhaseZero() {
    setState(() {
      _phase = 0;
      _firstPin = null;
    });
    _resetPinWithDelay();
  }

  void _resetPinWithDelay() {
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() {
          _pin.clear();
          _shaking = false;
        });
      }
    });
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).brightness == Brightness.dark
        ? ColorTokens.dark
        : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
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
                    // ── Icon ────────────────────────────────────────────
                    Icon(
                      Icons.lock_outline,
                      size: 64,
                      color: c.primary.withAlpha(120),
                    ),

                    const SizedBox(height: 20),

                    // ── Title ───────────────────────────────────────────
                    Text(
                      _title(l10n),
                      style: TextStyle(
                        color: c.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // ── Subtitle ────────────────────────────────────────
                    Text(
                      _subtitle(l10n),
                      style: TextStyle(
                        color: c.text.withAlpha(140),
                        fontSize: 14,
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── PIN Dots (with shake) ───────────────────────────
                    PinShakeWrapper(
                      shaking: _shaking,
                      child: PinDotIndicator(
                        length: _pinLength,
                        filledCount: _pin.length,
                      ),
                    ),

                    const SizedBox(height: 10),

                    // ── Error Indicator ─────────────────────────────────
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(color: c.error, fontSize: 14),
                      ),

                    const SizedBox(height: 32),

                    // ── Number Pad ──────────────────────────────────────
                    PinNumberPad(
                      onDigit: _onDigitTap,
                      onBackspace: _onBackspaceTap,
                      keyPrefix: 'pin',
                    ),

                    const SizedBox(height: 24),

                    // ── Cancel → go back ────────────────────────────────
                    GestureDetector(
                      key: const Key('pin-cancel'),
                      onTap: () {
                        if (context.canPop()) {
                          context.pop();
                        }
                      },
                      child: Text(
                        l10n.cancel,
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
}
