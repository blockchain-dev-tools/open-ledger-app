import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/enigma_logo_icon.dart';
import '../../widgets/common/grid_background.dart';
import '../../widgets/common/neo_app_bar.dart';
import '../../widgets/common/neo_card.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/mnemonic/mnemonic_language_picker.dart';
import '../../../data/bip39_wordlist.dart';
import '../../../utils/enigma.dart';

/// Enigma wallet creation screen.
///
/// Alternative wallet creation flow: the user provides a personal riddle
/// and secret key. These are combined and hashed to produce deterministic
/// entropy, from which a 24-word BIP-39 mnemonic is derived.
///
/// On success, navigates to [EnigmaMnemonicScreen] with the generated words.
///
/// Ported from the original TypeScript implementation.
class EnigmaScreen extends StatefulWidget {
  const EnigmaScreen({super.key});

  @override
  State<EnigmaScreen> createState() => _EnigmaScreenState();
}

class _EnigmaScreenState extends State<EnigmaScreen> {
  final _riddleController = TextEditingController();
  final _secretController = TextEditingController();
  bool _obscureSecret = true;
  bool _isGenerating = false;
  Bip39WordlistLanguage _selectedLanguage = Bip39WordlistLanguage.english;

  @override
  void dispose() {
    _riddleController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  /// Whether both input fields have content.
  bool get _isFormValid =>
      _riddleController.text.trim().isNotEmpty &&
      _secretController.text.trim().isNotEmpty;

  /// Wraps an input in the neo block in light mode; dark returns the field
  /// untouched so it keeps its own filled, hairline-outlined box.
  Widget _neoField(ColorTokens c, Widget child) =>
      c.neobrutalism ? NeoCard(child: child) : child;

  /// Field chrome. Light (neo) drops the field's own fill and outline — the
  /// surrounding [NeoCard] supplies both — while dark keeps the original
  /// filled, hairline-outlined box.
  InputDecoration _fieldDecoration(
    ColorTokens c, {
    required String hintText,
    Widget? suffixIcon,
  }) {
    final neo = c.neobrutalism;
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(R.lg),
      borderSide: BorderSide(color: c.border),
    );
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: c.text.withAlpha(100), fontSize: 14),
      filled: !neo,
      fillColor: neo ? null : c.surface,
      contentPadding: const EdgeInsets.all(16),
      suffixIcon: suffixIcon,
      border: neo ? InputBorder.none : border,
      enabledBorder: neo ? InputBorder.none : border,
      focusedBorder: neo
          ? InputBorder.none
          : OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.lg),
              borderSide: BorderSide(color: c.primary, width: 1.5),
            ),
    );
  }

  void _onGenerate() {
    if (!_isFormValid || _isGenerating) return;

    setState(() => _isGenerating = true);
    final language = _selectedLanguage;

    // Brief delay to show processing state.
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;

      try {
        final result = generateEnigmaMnemonic(
          _riddleController.text.trim(),
          _secretController.text.trim(),
          language: language,
        );

        setState(() => _isGenerating = false);

        context.go('/enigma-mnemonic', extra: {
          'words': result.words,
          'language': language,
          'entropyHex': result.entropyHex,
          'riddle': _riddleController.text.trim(),
          'secret': _secretController.text.trim(),
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Secret Phrase generation failed: $e'),
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? ColorTokens.dark.error
                : ColorTokens.light.error,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) context.go('/welcome');
      },
      child: Scaffold(
        // Light follows the neo page tint (pale lime) so the reference grid
        // reads as paper ruling; dark's `groupedBg` equals `bg`, so this only
        // affects light mode.
        backgroundColor: c.groupedBg,
        appBar: neoAppBar(
          c: c,
          title: Text(AppLocalizations.of(context)!.enigmaWallet),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: c.text),
            onPressed: () => context.go('/welcome'),
          ),
        ),
        body: GridBackground(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header ──────────────────────────────────────────
                  if (c.neobrutalism)
                    Center(
                      child: NeoCard(
                        fill: c.actionFill,
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: Center(
                            child: EnigmaLogoIcon(color: c.brandInk, size: 48),
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.primary.withAlpha(20),
                        border: Border.all(color: c.primary.withAlpha(60)),
                      ),
                      alignment: Alignment.center,
                      child: EnigmaLogoIcon(color: c.primary, size: 36),
                    ),

                  const SizedBox(height: 24),

                  Text(
                    AppLocalizations.of(context)!.enigmaTitle,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    AppLocalizations.of(context)!.enigmaDescription,
                    style: TextStyle(
                      color: c.neobrutalism ? c.text : c.text.withAlpha(160),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Language Selector ──────────────────────────────
                  Text(
                    AppLocalizations.of(context)!.mnemonicLanguage,
                    style: TextStyle(
                      color: c.text.withAlpha(200),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  MnemonicLanguageTrigger(
                    language: _selectedLanguage,
                    onChanged: (lang) =>
                        setState(() => _selectedLanguage = lang),
                  ),

                  const SizedBox(height: 20),

                  // ── Riddle Input ────────────────────────────────────
                  Text(
                    AppLocalizations.of(context)!.yourRiddle,
                    style: TextStyle(
                      color: c.text.withAlpha(200),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _neoField(
                    c,
                    TextField(
                      controller: _riddleController,
                      maxLines: 3,
                      style: TextStyle(color: c.text, fontSize: 15),
                      onChanged: (_) => setState(() {}),
                      decoration: _fieldDecoration(
                        c,
                        hintText:
                            AppLocalizations.of(context)!.enterMemorablePhrase,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Secret Key Input ────────────────────────────────
                  Text(
                    AppLocalizations.of(context)!.secretKey,
                    style: TextStyle(
                      color: c.text.withAlpha(200),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _neoField(
                    c,
                    TextField(
                      controller: _secretController,
                      obscureText: _obscureSecret,
                      style: TextStyle(color: c.text, fontSize: 15),
                      onChanged: (_) => setState(() {}),
                      decoration: _fieldDecoration(
                        c,
                        hintText: AppLocalizations.of(context)!.enterSecretKey,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureSecret
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: c.text.withAlpha(150),
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() => _obscureSecret = !_obscureSecret);
                          },
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Tip Text ────────────────────────────────────────
                  Text(
                    AppLocalizations.of(context)!.tipLongUnique,
                    style: TextStyle(
                      color: c.text.withAlpha(100),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Generate Button ─────────────────────────────────
                  PrimaryButton(
                    label: AppLocalizations.of(context)!.generateWallet,
                    onTap: _isFormValid && !_isGenerating ? _onGenerate : null,
                    loading: _isGenerating,
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
