import '../core/interfaces/crypto_service.dart';
import '../core/interfaces/mnemonic_service.dart';
import '../utils/fnv.dart';

/// Service for mnemonic generation, validation, fingerprinting, and Enigma.
///
/// Implements [IMnemonicService] — all crypto operations are delegated to the
/// injected [ICryptoService], keeping this service free of direct FFI imports.
class MnemonicService implements IMnemonicService {
  final ICryptoService _crypto;

  MnemonicService({required this._crypto});

  // ── BIP-39 generation / validation ──────────────────────────────────

  @override
  String generateMnemonic({int strength = 128}) {
    return _crypto.generateMnemonic(strength: strength);
  }

  @override
  bool validateMnemonic(String mnemonic) {
    return _crypto.validateMnemonic(mnemonic);
  }

  // ── Seed derivation ─────────────────────────────────────────────────

  @override
  String mnemonicToSeedHex(String mnemonic, String passphrase) {
    final result = _crypto.mnemonicToSeed(mnemonic, passphrase: passphrase);
    if (result == null) {
      throw StateError(
        'BIP-39 seed derivation failed. The mnemonic may be invalid '
        '(checksum verification failed).',
      );
    }
    return result;
  }

  // ── Fingerprint ─────────────────────────────────────────────────────

  /// Generate a lightweight fingerprint from the mnemonic.
  ///
  /// Uses a multi-round FNV-1a hash (pure Dart, no FFI), returning the
  /// first 8 hex characters.
  @override
  String fingerprintMnemonic(String mnemonic) {
    return fnv1aFingerprint(mnemonic);
  }

  // ── Enigma ──────────────────────────────────────────────────────────

  @override
  List<String> generateEnigmaMnemonic(
    String riddle,
    String secret, {
    int language = 0,
  }) {
    final phrase = _crypto.enigmaDeriveMnemonic(riddle, secret, language);
    if (phrase == null || phrase.isEmpty) {
      throw StateError(
          'Secret Phrase mnemonic generation failed (Rust SDK returned null)');
    }
    return phrase.split(' ');
  }
}
