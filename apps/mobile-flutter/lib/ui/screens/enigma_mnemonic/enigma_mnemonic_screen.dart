import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/mnemonic/warning_banner.dart';
import '../../widgets/mnemonic/mnemonic_word_grid.dart';
import '../../widgets/common/primary_button.dart';
import '../../../data/bip39_wordlist.dart';
import '../../../utils/enigma.dart';
// Web builds (design gallery) have no dart:ffi — the inert stub keeps the
// screen compilable; the seed-hex section simply stays hidden there.
import '../../../infrastructure/ffi/crypto_bridge_stub.dart'
    if (dart.library.ffi) '../../../infrastructure/ffi/crypto_bridge.dart'
    as bridge;

/// Displays the 24-word mnemonic generated via Enigma protocol.
///
/// Receives the word list, language, entropy hex, riddle and secret from
/// [GoRouterState.extra] (set by [EnigmaScreen]). Supports switching the
/// display language (re-derives mnemonic from the same entropy). Also
/// shows the BIP-39 seed hex for verification.
///
/// The **English mnemonic** is always the one used for wallet setup
/// (passed to SetPin), ensuring address derivation works correctly.
class EnigmaMnemonicScreen extends StatefulWidget {
  /// Optional preview data used when the route carries no extra
  /// (e.g. design-gallery direct URL loads). Route extras take precedence.
  final List<String>? previewWords;
  final String? previewEntropyHex;

  const EnigmaMnemonicScreen({
    super.key,
    this.previewWords,
    this.previewEntropyHex,
  });

  @override
  State<EnigmaMnemonicScreen> createState() => _EnigmaMnemonicScreenState();
}

class _EnigmaMnemonicScreenState extends State<EnigmaMnemonicScreen> {
  final TextEditingController _passphraseController = TextEditingController();
  bool _obscurePassphrase = true;

  /// English words — used for wallet setup (SetPin).
  late List<String> _englishWords;

  /// Currently displayed words (may be in any language, for display only).
  late List<String> _displayWords;

  /// The entropy hex from which all language variants are derived.
  late String _entropyHex;

  /// Language currently selected for display.
  late Bip39WordlistLanguage _displayLanguage;

  /// BIP-39 wordlist index the Enigma screen used to derive this mnemonic.
  ///
  /// Captured **once** from the route extra — the persisted `enigmaLanguage`
  /// must record the creation choice so the phrase can be re-derived later.
  /// The display-language switcher ([_onDisplayLanguageChanged]) changes only
  /// [_displayWords], never this value: the output mnemonic is always 24
  /// English words, so only the riddle→index lookup depends on the language.
  int _creationLanguage = 0;

  /// BIP-39 seed hex (derived from English mnemonic).
  String? _seedHex;

  /// Whether route extra has been processed (guard for didChangeDependencies).
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _initFromExtra();
      _computeSeed();
    }
  }

  void _initFromExtra() {
    final extra = GoRouterState.of(context).extra;
    var words = <String>[];
    var entropyHex = '';
    var creationLanguage = 0;
    if (extra is Map) {
      final extraWords = extra['words'];
      if (extraWords is List &&
          extraWords.isNotEmpty &&
          extraWords.first is String) {
        words = extraWords.cast<String>();
      }
      entropyHex = (extra['entropyHex'] as String?) ?? '';
      // The Enigma screen sends the chosen Bip39WordlistLanguage; accept a raw
      // index too so either shape resolves to the same persisted int.
      final lang = extra['language'];
      if (lang is int) {
        creationLanguage = lang;
      } else if (lang is Bip39WordlistLanguage) {
        creationLanguage = lang.index;
      }
    }
    // Fall back to preview data (design gallery direct URL loads).
    if (words.isEmpty && widget.previewWords != null) {
      words = widget.previewWords!;
      entropyHex = widget.previewEntropyHex ?? '';
    }
    _englishWords = words;
    _entropyHex = entropyHex;
    _creationLanguage = creationLanguage;
    _displayLanguage = Bip39WordlistLanguage.english;
    _displayWords = List.from(_englishWords);
  }

  void _computeSeed() {
    final phrase = _englishWords.join(' ');
    final seedHex = bridge.CryptoBridge.mnemonicToSeed(phrase);
    if (seedHex != null) {
      _seedHex = seedHex;
    }
  }

  void _onDisplayLanguageChanged(Bip39WordlistLanguage newLang) {
    try {
      final words = mnemonicFromEntropy(
        _entropyHex,
        language: newLang,
      );
      setState(() {
        _displayLanguage = newLang;
        _displayWords = words;
      });
    } catch (_) {
      // If conversion fails (e.g., invalid wordlist), keep current display.
    }
  }

  String _localizedLanguageName(Bip39WordlistLanguage lang) {
    final l10n = AppLocalizations.of(context)!;
    switch (lang) {
      case Bip39WordlistLanguage.english:
        return l10n.languageEnglish;
      case Bip39WordlistLanguage.chineseSimplified:
        return l10n.languageChinese;
    }
  }

  @override
  void dispose() {
    _passphraseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) context.go('/enigma');
      },
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          title: const Text('Secret Phrase Mnemonic'),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: c.text),
            onPressed: () => context.go('/enigma'),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ──────────────────────────────────────────
                Icon(Icons.shield_outlined, size: 56, color: c.primary),
                const SizedBox(height: 20),
                Text(
                  AppLocalizations.of(context)!.yourEnigmaSeedPhrase,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  AppLocalizations.of(context)!.writeDown24Words,
                  style: TextStyle(
                    color: c.text.withAlpha(160),
                    fontSize: 14,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 20),

                // ── Warning Banner ──────────────────────────────────
                WarningBanner(
                  message: AppLocalizations.of(context)!.neverShareSeed,
                  bold: true,
                ),

                const SizedBox(height: 24),

                // ── Language Selector (interactive) ─────────────────
                Row(
                  children: [
                    Text(
                      AppLocalizations.of(context)!.displayLanguage,
                      style: TextStyle(
                        color: c.text.withAlpha(160),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 0,
                        ),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(R.sm),
                          border: Border.all(color: c.border),
                        ),
                        child: DropdownButton<Bip39WordlistLanguage>(
                          value: _displayLanguage,
                          isExpanded: true,
                          underline: const SizedBox.shrink(),
                          dropdownColor: c.surface,
                          style: TextStyle(color: c.text, fontSize: 13),
                          icon: Icon(Icons.arrow_drop_down,
                              size: 18, color: c.text.withAlpha(120)),
                          items: Bip39WordlistLanguage.values.map((lang) {
                            return DropdownMenuItem(
                              value: lang,
                              child: Text(_localizedLanguageName(lang)),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              _onDisplayLanguageChanged(value);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ── Word Grid (4 columns × 6 rows for 24 words) ────
                if (_displayWords.isNotEmpty)
                  MnemonicWordGrid(
                    words: _displayWords,
                    columns: 4,
                    fontSize: 12,
                    childAspectRatio: 2.0,
                    cellSpacing: 6.0,
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      children: [
                        Icon(Icons.error_outline,
                            size: 40, color: c.text.withAlpha(80)),
                        const SizedBox(height: 12),
                        Text(
                          AppLocalizations.of(context)!.noMnemonicGenerated,
                          style: TextStyle(
                            color: c.text.withAlpha(120),
                            fontSize: 14,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 20),

                // ── Seed Hex Display ────────────────────────────────
                if (_seedHex != null)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(R.lg),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.vpn_key_outlined,
                                size: 16, color: c.primary),
                            const SizedBox(width: 8),
                            Text(
                              'BIP-39 Seed (hex)',
                              style: TextStyle(
                                color: c.text.withAlpha(180),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SelectableText(
                          _seedHex!,
                          style: TextStyle(
                            color: c.text.withAlpha(140),
                            fontSize: 11,
                            fontFamily: 'monospace',
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          AppLocalizations.of(context)!.seedDerivedFromEnglish,
                          style: TextStyle(
                            color: c.text.withAlpha(70),
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 20),

                // ── Instructions ────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(R.lg),
                    border: Border.all(color: c.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 18, color: c.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'I have written down my seed phrase',
                              style: TextStyle(
                                color: c.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 18, color: c.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'I understand that losing these words '
                              'means losing access to my funds',
                              style: TextStyle(
                                color: c.text.withAlpha(160),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Passphrase Input ─────────────────────────────────
                Text(
                  AppLocalizations.of(context)!.passphraseOptional,
                  style: TextStyle(
                    color: c.text.withAlpha(150),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  AppLocalizations.of(context)!.bip39PassphraseExplanation,
                  style: TextStyle(
                    color: c.text.withAlpha(100),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(R.lg),
                    border: Border.all(color: c.border),
                  ),
                  child: TextField(
                    key: const Key('passphrase-input'),
                    controller: _passphraseController,
                    obscureText: _obscurePassphrase,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 15,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Enter passphrase (optional)',
                      hintStyle: TextStyle(
                        color: c.text.withAlpha(80),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassphrase
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: c.text.withAlpha(150),
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassphrase = !_obscurePassphrase;
                          });
                        },
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Continue Button ─────────────────────────────────
                PrimaryButton(
                  label: AppLocalizations.of(context)!.continueToSetPin,
                  onTap: _englishWords.isNotEmpty
                      ? () {
                          try {
                            context.go('/set-pin', extra: {
                              'mnemonic': _englishWords.join(' '),
                              'passphrase': _passphraseController.text.trim(),
                              'source': 'enigma',
                              'enigmaLanguage': _creationLanguage,
                            });
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Navigation failed: $e'),
                                backgroundColor: c.error,
                              ),
                            );
                          }
                        }
                      : null,
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
