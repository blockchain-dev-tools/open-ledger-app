import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/mnemonic/warning_banner.dart';
import '../../widgets/mnemonic/mnemonic_word_grid.dart';
import '../../widgets/common/primary_button.dart';

/// Displays the generated 12-word BIP-39 mnemonic in a 3×4 word grid.
///
/// The user must visually confirm they have recorded the phrase before
/// proceeding to the verification quiz.
///
/// Accepts [mnemonic] as a space-separated string of 12 BIP-39 words.
///
/// Ported from the original TypeScript implementation.
class GenerateMnemonicScreen extends StatefulWidget {
  /// The 12-word BIP-39 mnemonic phrase (space-separated).
  final String mnemonic;

  const GenerateMnemonicScreen({super.key, required this.mnemonic});

  @override
  State<GenerateMnemonicScreen> createState() =>
      _GenerateMnemonicScreenState();
}

class _GenerateMnemonicScreenState extends State<GenerateMnemonicScreen> {
  bool _confirmed = false;
  bool _showPassphrase = false;
  bool _obscurePassphrase = true;
  final TextEditingController _passphraseController = TextEditingController();

  @override
  void dispose() {
    _passphraseController.dispose();
    super.dispose();
  }

  List<String> get _words => widget.mnemonic.split(' ');

  /// Navigates to the verification screen with the mnemonic and optional passphrase.
  void _continue() {
    final passphrase = _passphraseController.text.trim();
    context.go('/verify-mnemonic', extra: {
      'mnemonic': widget.mnemonic,
      'passphrase': passphrase,
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = ColorTokens.dark;
    final words = _words;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              // ── AppBar area ─────────────────────────────────────
              const SizedBox(height: 12),

              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () {
                    if (context.canPop()) {
                      context.pop();
                    }
                  },
                  child: Icon(
                    Icons.arrow_back,
                    color: c.text.withAlpha(160),
                    size: 24,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Title ───────────────────────────────────────────
              Text(
                l10n.generateMnemonicTitle,
                style: TextStyle(
                  color: c.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 16),

              // ── Warning ─────────────────────────────────────────
              WarningBanner(
                message: l10n.generateMnemonicWarning,
              ),

              const SizedBox(height: 24),

              // ── Word Grid (3 columns × 4 rows) ──────────────────
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: MnemonicWordGrid(
                      words: words,
                      columns: 3,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Confirmation checkbox ───────────────────────────
              GestureDetector(
                onTap: () {
                  setState(() {
                    _confirmed = !_confirmed;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(R.lg),
                    border: Border.all(color: c.border.withAlpha(100)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: _confirmed
                                ? c.primary
                                : c.border,
                            width: 2,
                          ),
                          color: _confirmed
                              ? c.primary
                              : Colors.transparent,
                        ),
                        child: _confirmed
                            ? Icon(
                                Icons.check,
                                size: 16,
                                color: c.onPrimary,
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        l10n.iveWrittenItDown,
                        style: TextStyle(
                          color: c.text.withAlpha(200),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Passphrase toggle ────────────────────────────
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showPassphrase = !_showPassphrase;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.advancedBip39Passphrase,
                          style: TextStyle(
                            color: c.text.withAlpha(150),
                            fontSize: 13,
                          ),
                        ),
                      ),
                      AnimatedRotation(
                        turns: _showPassphrase ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.chevron_right,
                          color: c.text.withAlpha(120),
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Passphrase input (collapsible) ───────────────
              if (_showPassphrase) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(R.lg),
                    border: Border.all(color: c.border.withAlpha(100)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'A passphrase acts as a 13th word. It creates a '
                        'completely different wallet from the same recovery '
                        'phrase. If you use one, you MUST remember it — '
                        'there is no way to recover it.',
                        style: TextStyle(
                          color: c.text.withAlpha(120),
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('passphrase-input'),
                        controller: _passphraseController,
                        obscureText: _obscurePassphrase,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: c.bg,
                          hintText: l10n.enterPassphraseOptional,
                          hintStyle: TextStyle(
                            color: c.text.withAlpha(80),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(R.lg),
                            borderSide: BorderSide(
                              color: c.border.withAlpha(100),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(R.lg),
                            borderSide: BorderSide(
                              color: c.border.withAlpha(100),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(R.lg),
                            borderSide: BorderSide(
                              color: c.primary,
                            ),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassphrase
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: c.text.withAlpha(120),
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassphrase = !_obscurePassphrase;
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 4),

              // ── Continue button ──────────────────────────────────
              PrimaryButton(
                label: l10n.continueButton,
                onTap: _confirmed ? _continue : null,
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
