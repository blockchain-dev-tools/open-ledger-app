import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/interfaces/wallet_service.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/app_toast.dart';
import '../../widgets/common/grid_background.dart';
import '../../widgets/common/neo_app_bar.dart';
import '../../widgets/common/neo_button.dart';
import '../../widgets/common/neo_card.dart';
import '../../widgets/pin/pin_number_pad.dart';
import '../../widgets/pin/pin_dot_indicator.dart';
import '../../widgets/pin/pin_shake_wrapper.dart';
import '../../widgets/mnemonic/warning_banner.dart';
import '../../widgets/mnemonic/mnemonic_word_grid.dart';

/// PIN-gated seed phrase reveal.
///
/// Two-phase screen:
///   1. **PIN entry** — user enters their 6-digit wallet PIN via on-screen
///      number pad to verify ownership.
///   2. **Seed reveal** — upon successful verification, the 12-word mnemonic
///      grid is revealed with a copy-to-clipboard button.
///
/// PIN attempts are limited (max 5), mirroring the [UnlockScreen] pattern.
/// A warning banner persists throughout both phases: "Never share your seed phrase!"
///
/// Ported from the original TypeScript implementation.
class BackupSeedScreen extends StatefulWidget {
  final IWalletService? walletService;

  const BackupSeedScreen({super.key, this.walletService});

  @override
  State<BackupSeedScreen> createState() => _BackupSeedScreenState();
}

class _BackupSeedScreenState extends State<BackupSeedScreen> {
  /// Current PIN digits entered.
  final List<int> _pin = [];

  /// Number of failed PIN attempts.
  int _attemptCount = 0;

  /// Whether the PIN pad should shake on failure.
  bool _shaking = false;

  /// Whether the user is locked out (max attempts reached).
  bool _lockedOut = false;

  /// Whether the mnemonic has been successfully revealed.
  bool _revealed = false;

  /// The revealed mnemonic words (demo words until WalletService is wired).
  final List<String> _mnemonicWords = [
    'abandon', 'ability', 'able', 'about',
    'above', 'absent', 'absorb', 'abstract',
    'absurd', 'abuse', 'access', 'accident',
  ];

  static const int _maxPinLength = 6;
  static const int _maxAttempts = 5;

  /// Adds [digit] to the PIN entry.
  void _onDigitTap(int digit) {
    if (_lockedOut || _revealed) return;
    if (_pin.length >= _maxPinLength) return;

    setState(() => _pin.add(digit));

    if (_pin.length == _maxPinLength) {
      _verifyPin();
    }
  }

  /// Removes the last entered digit.
  void _onBackspaceTap() {
    if (_lockedOut || _revealed) return;
    if (_pin.isEmpty) return;

    setState(() => _pin.removeLast());
  }

  /// Verifies the entered PIN via [WalletService.verifySessionPin].
  ///
  /// Session-scoped: the seed being revealed belongs to the active vault, so
  /// only the current tier's PIN may unlock it (another tier's valid PIN is
  /// rejected).
  Future<void> _verifyPin() async {
    final entered = _pin.join();
    final ws = widget.walletService;

    // Fallback for dev/test without a wallet service.
    if (ws == null) {
      setState(() => _revealed = true);
      return;
    }

    try {
      final ok = await ws.verifySessionPin(entered);
      if (!mounted) return;

      if (ok) {
        setState(() => _revealed = true);
        return;
      }
    } catch (_) {
      // Verification failed — treat as incorrect PIN.
    }

    setState(() {
      _attemptCount++;
      _shaking = true;
      if (_attemptCount >= _maxAttempts) {
        _lockedOut = true;
      }
    });

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() {
          _pin.clear();
          _shaking = false;
        });
      }
    });
  }

  /// Copies all 12 mnemonic words to the system clipboard.
  void _copyToClipboard() {
    final phrase = _mnemonicWords.join(' ');
    Clipboard.setData(ClipboardData(text: phrase));
    AppToast.show(
      context,
      message: AppLocalizations.of(context)!.copiedToClipboard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).brightness == Brightness.dark
        ? ColorTokens.dark
        : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      // Light follows the neo page tint (pale lime) so the reference grid
      // reads as paper ruling; dark's `groupedBg` equals `bg`, so this only
      // affects light mode.
      backgroundColor: c.groupedBg,
      appBar: neoAppBar(
        c: c,
        title: Text(l10n.backupSeedTitle),
        darkBackground: c.bg,
      ),
      body: GridBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                WarningBanner(
                  message: l10n.backupSeedWarning,
                ),

                const SizedBox(height: 32),

                if (_revealed)
                  _buildRevealedView(c, l10n)
                else
                  _buildPinEntryView(c, l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// PIN entry view: lock icon, attempt counter, PIN dots, number pad.
  Widget _buildPinEntryView(ColorTokens c, AppLocalizations l10n) {
    final lockIcon = Icon(
      _lockedOut ? Icons.lock : Icons.lock_outline,
      size: 30,
      color: _lockedOut ? c.error : c.text.withAlpha(150),
    );

    return Column(
      children: [
        // Light mode frames the lock as an outlined block; dark restores the
        // original circular tinted tile.
        if (c.neobrutalism)
          NeoCard(
            lifted: false,
            child: SizedBox(
              width: 64,
              height: 64,
              child: Center(child: lockIcon),
            ),
          )
        else
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.surface,
              border: Border.all(color: c.border),
            ),
            alignment: Alignment.center,
            child: lockIcon,
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
          Text(
            l10n.incorrectPin,
            style: TextStyle(color: c.error, fontSize: 14),
          ),

        const SizedBox(height: 28),

        if (_lockedOut)
          _buildLockoutView(c, l10n)
        else
          PinNumberPad(
            onDigit: _onDigitTap,
            onBackspace: _onBackspaceTap,
            keyPrefix: 'backup-seed',
          ),
      ],
    );
  }

  Widget _buildRevealedView(ColorTokens c, AppLocalizations l10n) {
    return Column(
      children: [
        // The lime [primary] washes out on the light page, so the glyph uses
        // the deeper accent there.
        Icon(
          Icons.check_circle,
          size: 48,
          color: c.neobrutalism ? c.accent : c.primary,
        ),
        const SizedBox(height: 16),
        Text(
          l10n.yourSeedPhrase,
          style: TextStyle(
            color: c.text,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.writeDown12Words,
          style: TextStyle(color: c.text.withAlpha(140), fontSize: 14),
        ),

        const SizedBox(height: 24),

        MnemonicWordGrid(
          words: _mnemonicWords,
          columns: 3,
          fontSize: 12,
          monospace: true,
          childAspectRatio: 3.0,
          cellSpacing: 8.0,
          neo: c.neobrutalism,
        ),

        const SizedBox(height: 24),

        // Light mode renders the neo action button; dark keeps the original
        // tinted outline block.
        if (c.neobrutalism)
          NeoButton(
            label: l10n.copyToClipboard,
            icon: Icons.copy,
            quiet: true,
            expanded: true,
            onTap: _copyToClipboard,
          )
        else
          GestureDetector(
            onTap: _copyToClipboard,
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                color: c.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(R.lg),
                border: Border.all(color: c.primary.withAlpha(80)),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.copy, size: 18, color: c.primary),
                  const SizedBox(width: 8),
                  Text(
                    l10n.copyToClipboard,
                    style: TextStyle(
                      color: c.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),

        const SizedBox(height: 12),
        Text(
          l10n.makeSurePrivate,
          style: TextStyle(color: c.text.withAlpha(100), fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildLockoutView(ColorTokens c, AppLocalizations l10n) {
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
