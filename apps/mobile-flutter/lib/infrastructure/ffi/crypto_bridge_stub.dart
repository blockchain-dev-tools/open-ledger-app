import 'dart:typed_data';

/// Web/standalone stub for [CryptoBridge] — the real implementation
/// (`crypto_bridge.dart`) binds the Rust SDK via `dart:ffi`, which does not
/// exist on Flutter web. This stub exposes the same static surface so that
/// product screens (and the design gallery) compile for web.
///
/// Selected via conditional import:
/// ```dart
/// import 'crypto_bridge_stub.dart'
///     if (dart.library.ffi) 'crypto_bridge.dart';
/// ```
///
/// All operations are inert: nullable results return `null`, validation
/// returns `false`. `hexEncode` / `hexToBytes` are pure Dart and behave
/// identically to the real bridge.
class CryptoBridge {
  CryptoBridge._();

  // ── Hex Utilities (pure Dart — safe to call on any platform) ────────

  static String hexEncode(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List hexToBytes(String hex) {
    final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  // ── BIP-39 Mnemonic ─────────────────────────────────────────────────

  static String generateMnemonic({int strength = 128}) => '';

  static bool validateMnemonic(String mnemonic) => false;

  static String reencodeMnemonic(String mnemonic) => mnemonic;

  static String? generateMnemonicLang({int strength = 128, required int language}) =>
      null;

  static bool validateMnemonicLang(String mnemonic, int language) => false;

  // ── Enigma ──────────────────────────────────────────────────────────

  static String? enigmaDeriveMnemonic(String riddle, String secret, int language) =>
      null;

  static String? enigmaEntropyHex(String riddle, String secret, int language) =>
      null;

  static int? enigmaMatchCount(String riddle, int language) => null;

  static String? mnemonicFromEntropy(String entropyHex, int language) => null;

  // ── HD Key Derivation ───────────────────────────────────────────────

  static Uint8List? deriveSecp256k1PrivateKey(String seedHex, String path) => null;

  static Uint8List? deriveSecp256k1Extended(String seedHex, String path) => null;

  static Uint8List? deriveEd25519PrivateKey(String seedHex, String path) => null;

  // ── Signing ─────────────────────────────────────────────────────────

  static Uint8List? signEthTransaction(String privkeyHex, String rlpHex) => null;

  static Uint8List? signEthPersonalMessage(String privkeyHex, String messageHex) =>
      null;

  static Uint8List? signEthEIP712(
          String privkeyHex, String domainHashHex, String structHashHex) =>
      null;

  static Uint8List? signSolanaMessage(String privkeyHex, String messageHex) =>
      null;

  // ── Address from Private Key ────────────────────────────────────────

  static String? ethAddressFromPrivateKey(String privkeyHex) => null;

  static Uint8List? ethPublicKeyBytes(String privkeyHex) => null;

  static Uint8List? solanaPublicKeyBytes(String privkeyHex) => null;

  // ── Export (ADR-011) ────────────────────────────────────────────────

  static Uint8List? publicKeyForChain(String chain, String privkeyHex) => null;

  static String? encodePrivateKey(String chain, String privkeyHex) => null;

  // ── Address from Seed + Path ────────────────────────────────────────

  static String? deriveEthAddress(String seedHex, String path) => null;

  static String? deriveSolAddress(String seedHex, String path) => null;

  static String? deriveBtcAddress(String seedHex, String path) => null;

  static String? deriveTronAddress(String seedHex, String path) => null;

  static String? deriveSuiAddress(String seedHex, String path) => null;

  static String? deriveNearAddress(String seedHex, String path) => null;

  static String? deriveTonAddress(String seedHex, String path) => null;

  // ── Address from Public Key ─────────────────────────────────────────

  static String? p2wpkhAddress(String compressedPubkeyHex) => null;

  static String? tronAddressFromPubkey(String uncompressedPubkeyHex) => null;

  static String? suiAddress(String ed25519PubkeyHex) => null;

  // ── APDU Sign Data Parser ───────────────────────────────────────────

  static String? parseSignData(String chain, String payloadHex) => null;

  // ── PIN auth + Mnemonic Encryption ─────────────────────────────────

  static String? pbkdf2Derive(String pin, String saltHex, int keyLen) => null;

  static String? mnemonicToSeed(String mnemonic, {String passphrase = ''}) => null;

  static String? chacha20Encrypt(String plaintext, String pin, String saltHex) =>
      null;

  static String? chacha20Decrypt(String ciphertextHex, String pin, String saltHex) =>
      null;

  static String? historyEncrypt(String plaintext, String seedHex) => null;

  static String? historyDecrypt(String cipherHex, String seedHex) => null;

  static String? hkdfExpand32(String prkHex, String info) => null;

  static String? aeadEncryptWithKey(String plaintext, String keyHex) => null;

  static String? aeadDecryptWithKey(String ciphertextHex, String keyHex) => null;

  static bool constantTimeEquals(String a, String b) => a == b;
}
