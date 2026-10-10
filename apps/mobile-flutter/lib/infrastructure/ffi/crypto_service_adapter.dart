import 'dart:typed_data';

import '../../core/interfaces/crypto_service.dart';
// Web builds (e.g. the design gallery) have no dart:ffi — fall back to the
// inert stub so the adapter (and its consumers) compile everywhere.
import 'crypto_bridge_stub.dart'
    if (dart.library.ffi) 'crypto_bridge.dart';

/// Adapter that wraps [CryptoBridge] static FFI methods as an
/// [ICryptoService] instance for dependency injection.
///
/// This allows services to depend on the abstract [ICryptoService]
/// interface while using the concrete FFI implementation at runtime.
/// Unit tests can inject a mock [ICryptoService] instead.
class CryptoServiceAdapter implements ICryptoService {
  const CryptoServiceAdapter();

  // ── BIP-39 Mnemonic ─────────────────────────────────────────────────

  @override
  String generateMnemonic({int strength = 128}) =>
      CryptoBridge.generateMnemonic(strength: strength);

  @override
  bool validateMnemonic(String mnemonic) =>
      CryptoBridge.validateMnemonic(mnemonic);

  @override
  String reencodeMnemonic(String mnemonic) =>
      CryptoBridge.reencodeMnemonic(mnemonic);

  @override
  String? generateMnemonicLang({int strength = 128, required int language}) =>
      CryptoBridge.generateMnemonicLang(strength: strength, language: language);

  @override
  bool validateMnemonicLang(String mnemonic, int language) =>
      CryptoBridge.validateMnemonicLang(mnemonic, language);

  // ── HD Key Derivation ───────────────────────────────────────────────

  @override
  Uint8List? deriveSecp256k1PrivateKey(String seedHex, String path) =>
      CryptoBridge.deriveSecp256k1PrivateKey(seedHex, path);

  @override
  Uint8List? deriveSecp256k1Extended(String seedHex, String path) =>
      CryptoBridge.deriveSecp256k1Extended(seedHex, path);

  @override
  Uint8List? deriveEd25519PrivateKey(String seedHex, String path) =>
      CryptoBridge.deriveEd25519PrivateKey(seedHex, path);

  // ── Signing ─────────────────────────────────────────────────────────

  @override
  Uint8List? signEthTransaction(String privkeyHex, String rlpHex) =>
      CryptoBridge.signEthTransaction(privkeyHex, rlpHex);

  @override
  Uint8List? signEthPersonalMessage(String privkeyHex, String messageHex) =>
      CryptoBridge.signEthPersonalMessage(privkeyHex, messageHex);

  @override
  Uint8List? signEthEIP712(
          String privkeyHex, String domainHashHex, String structHashHex) =>
      CryptoBridge.signEthEIP712(privkeyHex, domainHashHex, structHashHex);

  @override
  Uint8List? signSolanaMessage(String privkeyHex, String messageHex) =>
      CryptoBridge.signSolanaMessage(privkeyHex, messageHex);

  // ── Address from Private Key ────────────────────────────────────────

  @override
  String? ethAddressFromPrivateKey(String privkeyHex) =>
      CryptoBridge.ethAddressFromPrivateKey(privkeyHex);

  @override
  Uint8List? ethPublicKeyBytes(String privkeyHex) =>
      CryptoBridge.ethPublicKeyBytes(privkeyHex);

  @override
  Uint8List? solanaPublicKeyBytes(String privkeyHex) =>
      CryptoBridge.solanaPublicKeyBytes(privkeyHex);

  // ── Export (ADR-011) ────────────────────────────────────────────────

  @override
  Uint8List? publicKeyForChain(String chain, String privkeyHex) =>
      CryptoBridge.publicKeyForChain(chain, privkeyHex);

  @override
  String? encodePrivateKey(String chain, String privkeyHex) =>
      CryptoBridge.encodePrivateKey(chain, privkeyHex);

  // ── Address from Seed + Path ────────────────────────────────────────

  @override
  String? deriveEthAddress(String seedHex, String path) =>
      CryptoBridge.deriveEthAddress(seedHex, path);

  @override
  String? deriveSolAddress(String seedHex, String path) =>
      CryptoBridge.deriveSolAddress(seedHex, path);

  @override
  String? deriveBtcAddress(String seedHex, String path) =>
      CryptoBridge.deriveBtcAddress(seedHex, path);

  @override
  String? deriveTronAddress(String seedHex, String path) =>
      CryptoBridge.deriveTronAddress(seedHex, path);

  @override
  String? deriveSuiAddress(String seedHex, String path) =>
      CryptoBridge.deriveSuiAddress(seedHex, path);

  // ── Address from Public Key ─────────────────────────────────────────

  @override
  String? p2wpkhAddress(String compressedPubkeyHex) =>
      CryptoBridge.p2wpkhAddress(compressedPubkeyHex);

  @override
  String? tronAddressFromPubkey(String uncompressedPubkeyHex) =>
      CryptoBridge.tronAddressFromPubkey(uncompressedPubkeyHex);

  @override
  String? suiAddress(String ed25519PubkeyHex) =>
      CryptoBridge.suiAddress(ed25519PubkeyHex);

  // ── Enigma ─────────────────────────────────────────────────────────

  @override
  String? enigmaDeriveMnemonic(String riddle, String secret, int language) =>
      CryptoBridge.enigmaDeriveMnemonic(riddle, secret, language);

  @override
  String? enigmaEntropyHex(String riddle, String secret, int language) =>
      CryptoBridge.enigmaEntropyHex(riddle, secret, language);

  @override
  String? mnemonicFromEntropy(String entropyHex, int language) =>
      CryptoBridge.mnemonicFromEntropy(entropyHex, language);

  // ── APDU Sign Data Parser ───────────────────────────────────────────

  @override
  String? parseSignData(String chain, String payloadHex) =>
      CryptoBridge.parseSignData(chain, payloadHex);

  // ── PIN auth + Mnemonic Encryption ─────────────────────────────────

  @override
  String? pbkdf2Derive(String pin, String saltHex, int keyLen) =>
      CryptoBridge.pbkdf2Derive(pin, saltHex, keyLen);

  @override
  String? mnemonicToSeed(String mnemonic, {String passphrase = ''}) =>
      CryptoBridge.mnemonicToSeed(mnemonic, passphrase: passphrase);

  @override
  String? chacha20Encrypt(String plaintext, String pin, String saltHex) =>
      CryptoBridge.chacha20Encrypt(plaintext, pin, saltHex);

  @override
  String? chacha20Decrypt(String ciphertextHex, String pin, String saltHex) =>
      CryptoBridge.chacha20Decrypt(ciphertextHex, pin, saltHex);

  // ── Key hierarchy (HKDF-Expand + raw-key AEAD) ─────────────────────

  @override
  String? hkdfExpand32(String prkHex, String info) =>
      CryptoBridge.hkdfExpand32(prkHex, info);

  @override
  String? aeadEncryptWithKey(String plaintext, String keyHex) =>
      CryptoBridge.aeadEncryptWithKey(plaintext, keyHex);

  @override
  String? aeadDecryptWithKey(String ciphertextHex, String keyHex) =>
      CryptoBridge.aeadDecryptWithKey(ciphertextHex, keyHex);

  @override
  bool constantTimeEquals(String a, String b) =>
      CryptoBridge.constantTimeEquals(a, b);

  @override
  String? historyEncrypt(String plaintext, String seedHex) =>
      CryptoBridge.historyEncrypt(plaintext, seedHex);

  @override
  String? historyDecrypt(String cipherHex, String seedHex) =>
      CryptoBridge.historyDecrypt(cipherHex, seedHex);

  // ── Hex Utilities ──────────────────────────────────────────────────

  @override
  String hexEncode(Uint8List bytes) => CryptoBridge.hexEncode(bytes);

  @override
  Uint8List hexToBytes(String hex) => CryptoBridge.hexToBytes(hex);
}
