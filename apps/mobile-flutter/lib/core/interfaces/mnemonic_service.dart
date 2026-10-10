/// Abstract interface for mnemonic operations.
///
/// Implemented by [MnemonicService] in `lib/services/`.
/// [WalletService] depends on this interface, never on the concrete implementation.
abstract class IMnemonicService {
  /// Generate a BIP-39 mnemonic phrase.
  String generateMnemonic({int strength = 128});

  /// Validate a BIP-39 mnemonic phrase.
  bool validateMnemonic(String mnemonic);

  /// Derive a hex-encoded BIP-39 seed from mnemonic + optional passphrase.
  String mnemonicToSeedHex(String mnemonic, String passphrase);

  /// Generate a lightweight fingerprint from the mnemonic.
  /// Returns first 8 hex chars of a hash.
  String fingerprintMnemonic(String mnemonic);

  /// Generate a deterministic Enigma mnemonic (24 words) from riddle + secret.
  List<String> generateEnigmaMnemonic(
    String riddle,
    String secret, {
    int language = 0,
  });
}
