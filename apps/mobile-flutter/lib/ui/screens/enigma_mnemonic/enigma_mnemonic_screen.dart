import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/bip39_wordlist.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../utils/enigma.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/grid_background.dart';
import '../../widgets/common/neo_app_bar.dart';
import '../../widgets/common/neo_back_button.dart';
import '../../widgets/mnemonic/warning_banner.dart';
// Web builds (design gallery) have no dart:ffi — the inert stub keeps the
// screen compilable; the seed-hex section simply stays hidden there.
import '../../../infrastructure/ffi/crypto_bridge_stub.dart'
    if (dart.library.ffi) '../../../infrastructure/ffi/crypto_bridge.dart'
    as bridge;
import 'components/enigma_continue_button.dart';
import 'components/enigma_header.dart';
import 'components/enigma_verification_card.dart';
import 'components/enigma_word_grid.dart';
import 'components/mnemonic_language_selector.dart';
import 'components/passphrase_field.dart';
import 'components/seed_hex_card.dart';

/// Displays the 24-word mnemonic generated via Enigma protocol.
///
/// Receives the word list, language, entropy hex, riddle and secret from
/// [GoRouterState.extra] (set by [EnigmaScreen]). Supports switching the
/// display language (re-derives mnemonic from the same entropy). Also
/// shows the BIP-39 seed hex for verification.
///
/// The **English mnemonic** is always the one used for wallet setup
/// (passed to SetPin), ensuring address derivation works correctly.
///
/// Each block lives in `components/`; this file owns the state, the
/// reveal/blur logic and the navigation handlers.
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
      // FFI language code too so either shape resolves to the same persisted int.
      final lang = extra['language'];
      if (lang is int) {
        creationLanguage = lang;
      } else if (lang is Bip39WordlistLanguage) {
        creationLanguage = bip39LanguageCode(lang);
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
      final words = mnemonicFromEntropy(_entropyHex, language: newLang);
      setState(() {
        _displayLanguage = newLang;
        _displayWords = words;
      });
    } catch (_) {
      // If conversion fails (e.g., invalid wordlist), keep current display.
    }
  }

  /// Advances to Set-PIN with the English mnemonic and the entered passphrase.
  void _onContinue() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    try {
      context.go(
        '/set-pin',
        extra: {
          'mnemonic': _englishWords.join(' '),
          'passphrase': _passphraseController.text.trim(),
          'source': 'enigma',
          'enigmaLanguage': _creationLanguage,
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Navigation failed: $e'),
          backgroundColor: c.error,
        ),
      );
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
        // Light follows the neo page tint (pale lime) so the reference grid
        // reads as paper ruling; dark's `groupedBg` equals `bg`, so this only
        // affects light mode.
        backgroundColor: c.groupedBg,
        appBar: neoAppBar(
          c: c,
          title: const Text('Secret Phrase Mnemonic'),
          leading: neoBackButton(c, onPressed: () => context.go('/enigma')),
        ),
        body: GridBackground(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header ──────────────────────────────────────────
                  const EnigmaHeader(),

                  const SizedBox(height: 20),

                  // ── Warning Banner ──────────────────────────────────
                  WarningBanner(
                    message: AppLocalizations.of(context)!.neverShareSeed,
                    bold: true,
                  ),

                  const SizedBox(height: 24),

                  // ── Language Selector (interactive) ─────────────────
                  MnemonicLanguageSelector(
                    language: _displayLanguage,
                    onChanged: _onDisplayLanguageChanged,
                  ),

                  const SizedBox(height: 20),

                  // ── Word Grid (4 columns × 6 rows for 24 words) ────
                  EnigmaWordGrid(words: _displayWords),

                  const SizedBox(height: 20),

                  // ── Seed Hex Display ────────────────────────────────
                  if (_seedHex != null) SeedHexCard(seedHex: _seedHex!),

                  const SizedBox(height: 20),

                  // ── Instructions ────────────────────────────────────
                  const EnigmaVerificationCard(),

                  const SizedBox(height: 24),

                  // ── Passphrase Input ─────────────────────────────────
                  PassphraseField(
                    controller: _passphraseController,
                    obscure: _obscurePassphrase,
                    onToggleObscure: () {
                      setState(() {
                        _obscurePassphrase = !_obscurePassphrase;
                      });
                    },
                  ),

                  const SizedBox(height: 24),

                  // ── Continue Button ─────────────────────────────────
                  EnigmaContinueButton(
                    onTap: _englishWords.isNotEmpty ? _onContinue : null,
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
