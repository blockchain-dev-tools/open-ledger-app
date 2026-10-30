import 'package:flutter/material.dart';

import '../../../data/bip39_wordlist.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../utils/enigma.dart';
import '../../theme/color_tokens.dart';
import '../common/neo_card.dart';
import '../common/primary_button.dart';
import 'mnemonic_language_picker.dart';

/// Derives the 24-word phrase for [riddle] + [secret] in [language].
///
/// Mirrors `generateEnigmaMnemonic`, so a test host can stand in for the Rust
/// bridge where the native symbols are missing.
typedef EnigmaDerive =
    ({List<String> words, String entropyHex}) Function(
      String riddle,
      String secret, {
      Bip39WordlistLanguage language,
    });

/// Everything a successful derivation hands to the review step.
typedef EnigmaDerivation = ({
  List<String> words,
  String entropyHex,
  String riddle,
  String secret,
  Bip39WordlistLanguage language,
});

/// The riddle + secret form that derives a secret-phrase wallet.
///
/// Shared by the first-run Secret Phrase screen and the vault manager's
/// "New Vault" Enigma tab, so both render — and derive — identically.
///
/// The host owns the text controllers and the wordlist selection, so typed
/// input and the chosen language survive a tab switch; this widget owns only
/// the transient presentation state (secret visibility, live match count,
/// processing flag) and reports a finished derivation through [onGenerated].
class EnigmaForm extends StatefulWidget {
  final TextEditingController riddleController;
  final TextEditingController secretController;

  /// BIP-39 wordlist used for the riddle → index lookup.
  final Bip39WordlistLanguage language;
  final ValueChanged<Bip39WordlistLanguage> onLanguageChanged;

  final void Function(EnigmaDerivation derivation) onGenerated;

  /// Test seam: replaces the Rust-backed derivation. Null uses
  /// [generateEnigmaMnemonic].
  final EnigmaDerive? derive;

  const EnigmaForm({
    super.key,
    required this.riddleController,
    required this.secretController,
    required this.language,
    required this.onLanguageChanged,
    required this.onGenerated,
    this.derive,
  });

  @override
  State<EnigmaForm> createState() => _EnigmaFormState();
}

class _EnigmaFormState extends State<EnigmaForm> {
  bool _obscureSecret = true;
  bool _isGenerating = false;

  /// Live count of BIP-39 words the riddle matches (null when the native
  /// bridge is unavailable, in which case the hint stays hidden).
  int? _matchCount;

  @override
  void initState() {
    super.initState();
    // The host may hand over a riddle typed before this form was mounted
    // (a tab switch away and back), so seed the hint from the current text.
    _refreshMatchCount();
  }

  @override
  void didUpdateWidget(EnigmaForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language) _refreshMatchCount();
  }

  /// Recomputes [_matchCount] from the current riddle and wordlist.
  ///
  /// Callers wrap this in `setState`; derivation itself is cheap (one
  /// wordlist lookup per token, capped at 1024 tokens).
  void _refreshMatchCount() {
    final riddle = widget.riddleController.text.trim();
    _matchCount = riddle.isEmpty
        ? 0
        : enigmaMatchCount(riddle, language: widget.language);
  }

  /// Whether both input fields have content.
  bool get _isFormValid =>
      widget.riddleController.text.trim().isNotEmpty &&
      widget.secretController.text.trim().isNotEmpty;

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
    final language = widget.language;
    final riddle = widget.riddleController.text.trim();
    final secret = widget.secretController.text.trim();

    // Brief delay to show processing state.
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;

      try {
        final derive = widget.derive ?? generateEnigmaMnemonic;
        final result = derive(riddle, secret, language: language);

        setState(() => _isGenerating = false);

        widget.onGenerated((
          words: result.words,
          entropyHex: result.entropyHex,
          riddle: riddle,
          secret: secret,
          language: language,
        ));
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
    final l10n = AppLocalizations.of(context)!;
    final c = Theme.of(context).brightness == Brightness.dark
        ? ColorTokens.dark
        : ColorTokens.light;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Language Selector ────────────────────────────────────────
        Text(
          l10n.mnemonicLanguage,
          style: TextStyle(
            color: c.text.withAlpha(200),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        MnemonicLanguageTrigger(
          language: widget.language,
          onChanged: (lang) => setState(() {
            widget.onLanguageChanged(lang);
            _refreshMatchCount();
          }),
        ),

        const SizedBox(height: 20),

        // ── Riddle Input ─────────────────────────────────────────────
        Text(
          l10n.yourRiddle,
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
            key: const Key('enigma-riddle'),
            controller: widget.riddleController,
            maxLines: 3,
            style: TextStyle(color: c.text, fontSize: 15),
            onChanged: (_) => setState(_refreshMatchCount),
            decoration: _fieldDecoration(
              c,
              hintText: l10n.enterMemorablePhrase,
            ),
          ),
        ),

        // ── Match count hint ─────────────────────────────────────────
        if (widget.riddleController.text.trim().isNotEmpty &&
            _matchCount != null) ...[
          const SizedBox(height: 6),
          Text(
            _matchCount! > 0
                ? l10n.enigmaMatchCount(_matchCount!)
                : l10n.enigmaNoMatch,
            style: TextStyle(
              color: _matchCount! > 0 ? c.mutedText(160) : c.error,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],

        const SizedBox(height: 20),

        // ── Secret Key Input ─────────────────────────────────────────
        Text(
          l10n.secretKey,
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
            key: const Key('enigma-secret'),
            controller: widget.secretController,
            obscureText: _obscureSecret,
            style: TextStyle(color: c.text, fontSize: 15),
            onChanged: (_) => setState(() {}),
            decoration: _fieldDecoration(
              c,
              hintText: l10n.enterSecretKey,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureSecret ? Icons.visibility_off : Icons.visibility,
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

        // ── Tip Text ─────────────────────────────────────────────────
        Text(
          l10n.tipLongUnique,
          style: TextStyle(
            color: c.text.withAlpha(100),
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),

        const SizedBox(height: 32),

        // ── Generate Button ──────────────────────────────────────────
        PrimaryButton(
          key: const Key('enigma-generate'),
          label: l10n.generateWallet,
          onTap: _isFormValid && !_isGenerating ? _onGenerate : null,
          loading: _isGenerating,
        ),
      ],
    );
  }
}
