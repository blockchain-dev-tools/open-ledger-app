import '../data/bip39_wordlist.dart';
// Web builds have no dart:ffi — the inert stub keeps this compilable
// (Enigma derivation itself only works on native).
import '../infrastructure/ffi/crypto_bridge_stub.dart'
    if (dart.library.ffi) '../infrastructure/ffi/crypto_bridge.dart' as bridge;

/// Generate an Enigma mnemonic (always English output for seed compatibility).
///
/// The [language] controls which BIP-39 wordlist is used for the riddle text
/// → index lookup. The output mnemonic is always 24 English words.
///
/// Returns both the mnemonic words and the raw entropy hex (64 hex chars).
/// The entropy can be used with [mnemonicFromEntropy] to display the same
/// wallet in different BIP-39 wordlists.
({List<String> words, String entropyHex}) generateEnigmaMnemonic(
  String riddle,
  String secret, {
  Bip39WordlistLanguage language = Bip39WordlistLanguage.english,
}) {
  final phrase = bridge.CryptoBridge.enigmaDeriveMnemonic(
    riddle,
    secret,
    bip39LanguageCode(language),
  );
  if (phrase == null || phrase.isEmpty) {
    throw StateError(
        'Secret Phrase mnemonic generation failed (Rust SDK returned null)');
  }
  final entropyHex = bridge.CryptoBridge.enigmaEntropyHex(
    riddle,
    secret,
    bip39LanguageCode(language),
  );
  if (entropyHex == null || entropyHex.isEmpty) {
    throw StateError(
        'Secret Phrase entropy derivation failed (Rust SDK returned null)');
  }
  return (words: phrase.split(' '), entropyHex: entropyHex);
}

/// Generate a 24-word BIP-39 mnemonic from pre-computed entropy hex.
///
/// Use this to display the same Enigma wallet in different BIP-39 wordlists
/// (e.g., Chinese, Japanese, etc.) without re-deriving the entropy.
///
/// [entropyHex] must be 64 hex chars (32 bytes).
List<String> mnemonicFromEntropy(
  String entropyHex, {
  Bip39WordlistLanguage language = Bip39WordlistLanguage.english,
}) {
  final phrase = bridge.CryptoBridge.mnemonicFromEntropy(
    entropyHex,
    bip39LanguageCode(language),
  );
  if (phrase == null || phrase.isEmpty) {
    throw StateError(
        'Mnemonic from entropy failed (Rust SDK returned null)');
  }
  return phrase.split(' ');
}
