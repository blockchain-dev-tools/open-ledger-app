import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════
// FFI struct: matches rust/open-ledger-ffi/src/types.rs FfiResult
// ═══════════════════════════════════════════════════════════════════════════

final class FfiResult extends Struct {
  external Pointer<Utf8> data;

  @Int32()
  external int errorCode;

  external Pointer<Utf8> errorMsg;
}

// ═══════════════════════════════════════════════════════════════════════════
// FFI type definitions
// ═══════════════════════════════════════════════════════════════════════════

// -- fn() -> FfiResult
typedef _GenMnemonicC = Pointer<FfiResult> Function(Uint32);
typedef _GenMnemonicDart = Pointer<FfiResult> Function(int);

// -- fn(u32, u32) -> FfiResult
typedef _GenLangC = Pointer<FfiResult> Function(Uint32, Uint32);
typedef _GenLangDart = Pointer<FfiResult> Function(int, int);

// -- fn(*const c_char) -> u8
typedef _ValidateC = Uint8 Function(Pointer<Utf8>);
typedef _ValidateDart = int Function(Pointer<Utf8>);

// -- fn(*const c_char, u32) -> u8
typedef _ValidateLangC = Uint8 Function(Pointer<Utf8>, Uint32);
typedef _ValidateLangDart = int Function(Pointer<Utf8>, int);

// -- fn(*const c_char, *const c_char) -> u8
typedef _ConstantTimeEqC = Uint8 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _ConstantTimeEqDart = int Function(Pointer<Utf8>, Pointer<Utf8>);

// -- fn(*const c_char) -> FfiResult
typedef _Fn1C = Pointer<FfiResult> Function(Pointer<Utf8>);
typedef _Fn1Dart = Pointer<FfiResult> Function(Pointer<Utf8>);

// -- fn(*const c_char, *const c_char) -> FfiResult
typedef _Fn2C = Pointer<FfiResult> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _Fn2Dart = Pointer<FfiResult> Function(Pointer<Utf8>, Pointer<Utf8>);

// -- fn(*const c_char, *const c_char, *const c_char) -> FfiResult
typedef _Fn3C = Pointer<FfiResult> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _Fn3Dart = Pointer<FfiResult> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);

// -- fn(*const c_char, *const c_char, u32) -> FfiResult
typedef _EnigmaDeriveC = Pointer<FfiResult> Function(Pointer<Utf8>, Pointer<Utf8>, Uint32);
typedef _EnigmaDeriveDart = Pointer<FfiResult> Function(Pointer<Utf8>, Pointer<Utf8>, int);

// -- fn(*const c_char, u32) -> FfiResult
typedef _MnemonicFromEntropyC = Pointer<FfiResult> Function(Pointer<Utf8>, Uint32);
typedef _MnemonicFromEntropyDart = Pointer<FfiResult> Function(Pointer<Utf8>, int);

// -- fn(*const c_char, *const c_char, u32) -> FfiResult
typedef _Pbkdf2C = Pointer<FfiResult> Function(Pointer<Utf8>, Pointer<Utf8>, Uint32);
typedef _Pbkdf2Dart = Pointer<FfiResult> Function(Pointer<Utf8>, Pointer<Utf8>, int);

// -- free_ffi_result(*mut FfiResult) -> void
typedef _FreeResultC = Void Function(Pointer<FfiResult>);
typedef _FreeResultDart = void Function(Pointer<FfiResult>);



// ═══════════════════════════════════════════════════════════════════════════
// Dart FFI bridge
// ═══════════════════════════════════════════════════════════════════════════
class CryptoBridge {
  CryptoBridge._();

  static final DynamicLibrary _lib = _loadLibrary();

  /// The loaded native library, shared with sibling FFI bindings so the
  /// platform-specific loading rules live in exactly one place.
  static DynamicLibrary get nativeLibrary => _lib;

  static DynamicLibrary _loadLibrary() {
    // iOS: Rust staticlib is linked into the main executable → symbols are
    // visible via DynamicLibrary.process().
    // Android: cdylib .so is bundled as a jniLib, opened by soname.
    // macOS (simulator/debug): same as iOS, static-linked into Runner.app.
    if (Platform.isIOS || Platform.isMacOS) {
      return DynamicLibrary.process();
    }
    return DynamicLibrary.open('libopen_ledger_crypto.so');
  }

  // ── Bound function handles ─────────────────────────────────────────

  static final _GenMnemonicDart _genMnemonic = _lib
      .lookupFunction<_GenMnemonicC, _GenMnemonicDart>('generate_mnemonic');

  static final _ValidateDart _validate = _lib
      .lookupFunction<_ValidateC, _ValidateDart>('validate_mnemonic');

  static final _Fn1Dart _reencode = _lib
      .lookupFunction<_Fn1C, _Fn1Dart>('reencode_mnemonic');

  static final _GenLangDart _genMnemonicLang = _lib
      .lookupFunction<_GenLangC, _GenLangDart>('generate_mnemonic_lang');

  static final _ValidateLangDart _validateLang = _lib
      .lookupFunction<_ValidateLangC, _ValidateLangDart>('validate_mnemonic_lang');

  static final _ConstantTimeEqDart _constantTimeEq = _lib
      .lookupFunction<_ConstantTimeEqC, _ConstantTimeEqDart>('constant_time_eq');

  static final _FreeResultDart _freeResult = _lib
      .lookupFunction<_FreeResultC, _FreeResultDart>('free_ffi_result');

  static final _Fn2Dart _deriveSecp = _lib
      .lookupFunction<_Fn2C, _Fn2Dart>('derive_secp256k1_private_key_ffi');

  static final _Fn2Dart _deriveSecpExtended = _lib
      .lookupFunction<_Fn2C, _Fn2Dart>('derive_secp256k1_extended_ffi');

  static final _Fn2Dart _deriveEd = _lib
      .lookupFunction<_Fn2C, _Fn2Dart>('derive_ed25519_private_key_ffi');

  static final _Fn2Dart _signEthTx = _lib
      .lookupFunction<_Fn2C, _Fn2Dart>('sign_eth_transaction_ffi');

  static final _Fn2Dart _signEthPersonal = _lib
      .lookupFunction<_Fn2C, _Fn2Dart>('sign_eth_personal_message_ffi');

  static final _Fn3Dart _signEip712 = _lib
      .lookupFunction<_Fn3C, _Fn3Dart>('sign_eth_eip712_ffi');

  static final _Fn2Dart _signSol = _lib
      .lookupFunction<_Fn2C, _Fn2Dart>('sign_solana_message_ffi');

  static final _Fn1Dart _ethAddrFromKey = _lib
      .lookupFunction<_Fn1C, _Fn1Dart>('eth_address_from_private_key_ffi');

  static final _Fn1Dart _solPubkey = _lib
      .lookupFunction<_Fn1C, _Fn1Dart>('solana_public_key_bytes_ffi');

  static final _Fn1Dart _ethPubkey = _lib
      .lookupFunction<_Fn1C, _Fn1Dart>('eth_public_key_bytes_ffi');

  static final _Fn2Dart _pubkeyForChain = _lib
      .lookupFunction<_Fn2C, _Fn2Dart>('public_key_for_chain');

  static final _Fn2Dart _encodePrivkey = _lib
      .lookupFunction<_Fn2C, _Fn2Dart>('encode_private_key');

  static final _Fn2Dart _deriveEthAddr = _lib
      .lookupFunction<_Fn2C, _Fn2Dart>('derive_eth_address_ffi');

  static final _Fn2Dart _deriveSolAddr = _lib
      .lookupFunction<_Fn2C, _Fn2Dart>('derive_sol_address_ffi');

  static final _Fn2Dart _deriveBtcAddr = _lib
      .lookupFunction<_Fn2C, _Fn2Dart>('derive_btc_address_ffi');

  static final _Fn2Dart _deriveTronAddr = _lib
      .lookupFunction<_Fn2C, _Fn2Dart>('derive_tron_address_ffi');

  static final _Fn2Dart _deriveSuiAddr = _lib
      .lookupFunction<_Fn2C, _Fn2Dart>('derive_sui_address_ffi');

  static final _Fn1Dart _p2wpkh = _lib
      .lookupFunction<_Fn1C, _Fn1Dart>('p2wpkh_address_ffi');

  static final _Fn1Dart _tronFromPubkey = _lib
      .lookupFunction<_Fn1C, _Fn1Dart>('tron_address_from_pubkey_ffi');

  static final _Fn1Dart _suiAddr = _lib
      .lookupFunction<_Fn1C, _Fn1Dart>('sui_address_ffi');

  static final _EnigmaDeriveDart _enigmaDerive = _lib
      .lookupFunction<_EnigmaDeriveC, _EnigmaDeriveDart>('enigma_derive_mnemonic');

  static final _EnigmaDeriveDart _enigmaEntropyHex = _lib
      .lookupFunction<_EnigmaDeriveC, _EnigmaDeriveDart>('enigma_entropy_hex');

  static final _MnemonicFromEntropyDart _mnemonicFromEntropy = _lib
      .lookupFunction<_MnemonicFromEntropyC, _MnemonicFromEntropyDart>('mnemonic_from_entropy');

  static final _Pbkdf2Dart _pbkdf2 = _lib
      .lookupFunction<_Pbkdf2C, _Pbkdf2Dart>('pbkdf2_derive');

  static final _Fn2Dart _mnemonicToSeed = _lib
      .lookupFunction<_Fn2C, _Fn2Dart>('mnemonic_to_seed');

  static final _Fn3Dart _chacha20Enc = _lib
      .lookupFunction<_Fn3C, _Fn3Dart>('chacha20_encrypt');

  static final _Fn3Dart _chacha20Dec = _lib
      .lookupFunction<_Fn3C, _Fn3Dart>('chacha20_decrypt');

  static final _Fn2Dart _historyEnc = _lib
      .lookupFunction<_Fn2C, _Fn2Dart>('history_encrypt');

  static final _Fn2Dart _historyDec = _lib
      .lookupFunction<_Fn2C, _Fn2Dart>('history_decrypt');

  // ── Key hierarchy (HKDF-Expand + raw-key AEAD) ─────────────────────

  static final _Fn2Dart _hkdfExpand32 = _lib
      .lookupFunction<_Fn2C, _Fn2Dart>('hkdf_expand32');

  static final _Fn2Dart _aeadEncWithKey = _lib
      .lookupFunction<_Fn2C, _Fn2Dart>('aead_encrypt_with_key');

  static final _Fn2Dart _aeadDecWithKey = _lib
      .lookupFunction<_Fn2C, _Fn2Dart>('aead_decrypt_with_key');

  static final _Fn2Dart _parseSignData = _lib
      .lookupFunction<_Fn2C, _Fn2Dart>('parse_sign_data');

  // ── Internal helpers ───────────────────────────────────────────────

  static Pointer<Utf8> _str(String s) => s.toNativeUtf8();

  /// Extract data from FfiResult. Throws on error. Frees the result.
  static String _resultToStr(Pointer<FfiResult> r) {
    final result = r.ref;
    if (result.errorCode != 0) {
      final msg = result.errorMsg == nullptr ? 'Unknown error' : result.errorMsg.toDartString();
      _freeResult(r);
      throw Exception('CryptoError(${result.errorCode}): $msg');
    }
    final s = result.data == nullptr ? '' : result.data.toDartString();
    _freeResult(r);
    return s;
  }

  /// Extract optional data from FfiResult. Returns null on error.
  static String? _resultToOptionalStr(Pointer<FfiResult> r) {
    final result = r.ref;
    if (result.errorCode != 0) {
      _freeResult(r);
      return null;
    }
    final s = result.data == nullptr ? '' : result.data.toDartString();
    _freeResult(r);
    return s;
  }

  /// Extract hex data as bytes from FfiResult.
  /// Extract optional hex data as bytes.
  static Uint8List? _resultToOptionalBytes(Pointer<FfiResult> r) {
    final hex = _resultToOptionalStr(r);
    if (hex == null) return null;
    return hexToBytes(hex);
  }

  // ── Public hex utilities ───────────────────────────────────────────

  static String hexEncode(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Uint8List hexToBytes(String hex) {
    if (hex.length % 2 != 0) {
      throw ArgumentError('Invalid hex string (odd length)');
    }
    return Uint8List.fromList(List.generate(
      hex.length ~/ 2,
      (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
    ));
  }

  // ═══════════════════════════════════════════════════════════════════
  // Public API — Group 1: BIP-39 mnemonic
  // ═══════════════════════════════════════════════════════════════════

  static String generateMnemonic({int strength = 128}) {
    return _resultToStr(_genMnemonic(strength));
  }

  static bool validateMnemonic(String mnemonic) {
    final arg = _str(mnemonic);
    try {
      final result = _validate(arg);
      return result != 0;
    } finally {
      calloc.free(arg);
    }
  }

  static String reencodeMnemonic(String mnemonic) {
    final arg = _str(mnemonic);
    try {
      return _resultToStr(_reencode(arg));
    } finally {
      calloc.free(arg);
    }
  }

  static String? generateMnemonicLang({int strength = 128, required int language}) {
    return _resultToOptionalStr(_genMnemonicLang(strength, language));
  }

  static bool validateMnemonicLang(String mnemonic, int language) {
    final arg = _str(mnemonic);
    try {
      return _validateLang(arg, language) != 0;
    } finally {
      calloc.free(arg);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Public API — Group 1b: Enigma
  // ═══════════════════════════════════════════════════════════════════

  static String? enigmaDeriveMnemonic(String riddle, String secret, int language) {
    final r = _str(riddle);
    final s = _str(secret);
    try {
      return _resultToOptionalStr(_enigmaDerive(r, s, language));
    } finally {
      calloc.free(r);
      calloc.free(s);
    }
  }

  static String? enigmaEntropyHex(String riddle, String secret, int language) {
    final r = _str(riddle);
    final s = _str(secret);
    try {
      return _resultToOptionalStr(_enigmaEntropyHex(r, s, language));
    } finally {
      calloc.free(r);
      calloc.free(s);
    }
  }

  static String? mnemonicFromEntropy(String entropyHex, int language) {
    final e = _str(entropyHex);
    try {
      return _resultToOptionalStr(_mnemonicFromEntropy(e, language));
    } finally {
      calloc.free(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Public API — Group 2: HD key derivation
  // ═══════════════════════════════════════════════════════════════════

  static Uint8List? deriveSecp256k1PrivateKey(String seedHex, String path) {
    final s = _str(seedHex);
    final p = _str(path);
    try {
      return _resultToOptionalBytes(_deriveSecp(s, p));
    } finally {
      calloc.free(s);
      calloc.free(p);
    }
  }

  static Uint8List? deriveSecp256k1Extended(String seedHex, String path) {
    final s = _str(seedHex);
    final p = _str(path);
    try {
      return _resultToOptionalBytes(_deriveSecpExtended(s, p));
    } finally {
      calloc.free(s);
      calloc.free(p);
    }
  }

  static Uint8List? deriveEd25519PrivateKey(String seedHex, String path) {
    final s = _str(seedHex);
    final p = _str(path);
    try {
      return _resultToOptionalBytes(_deriveEd(s, p));
    } finally {
      calloc.free(s);
      calloc.free(p);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Public API — Group 3: Signing
  // ═══════════════════════════════════════════════════════════════════

  static Uint8List? signEthTransaction(String privkeyHex, String rlpHex) {
    final k = _str(privkeyHex);
    final r = _str(rlpHex);
    try {
      return _resultToOptionalBytes(_signEthTx(k, r));
    } finally {
      calloc.free(k);
      calloc.free(r);
    }
  }

  static Uint8List? signEthPersonalMessage(String privkeyHex, String messageHex) {
    final k = _str(privkeyHex);
    final m = _str(messageHex);
    try {
      return _resultToOptionalBytes(_signEthPersonal(k, m));
    } finally {
      calloc.free(k);
      calloc.free(m);
    }
  }

  static Uint8List? signEthEIP712(String privkeyHex, String domainHashHex, String structHashHex) {
    final k = _str(privkeyHex);
    final d = _str(domainHashHex);
    final s = _str(structHashHex);
    try {
      return _resultToOptionalBytes(_signEip712(k, d, s));
    } finally {
      calloc.free(k);
      calloc.free(d);
      calloc.free(s);
    }
  }

  static Uint8List? signSolanaMessage(String privkeyHex, String messageHex) {
    final k = _str(privkeyHex);
    final m = _str(messageHex);
    try {
      return _resultToOptionalBytes(_signSol(k, m));
    } finally {
      calloc.free(k);
      calloc.free(m);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Public API — Group 4: Address from private key
  // ═══════════════════════════════════════════════════════════════════

  static String? ethAddressFromPrivateKey(String privkeyHex) {
    final k = _str(privkeyHex);
    try {
      return _resultToOptionalStr(_ethAddrFromKey(k));
    } finally {
      calloc.free(k);
    }
  }

  static Uint8List? ethPublicKeyBytes(String privkeyHex) {
    final k = _str(privkeyHex);
    try {
      return _resultToOptionalBytes(_ethPubkey(k));
    } finally {
      calloc.free(k);
    }
  }

  static Uint8List? solanaPublicKeyBytes(String privkeyHex) {
    final k = _str(privkeyHex);
    try {
      return _resultToOptionalBytes(_solPubkey(k));
    } finally {
      calloc.free(k);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Public API — Group 5b: Export (ADR-011) — real pubkey + key encoding
  // ═══════════════════════════════════════════════════════════════════

  /// The chain's **real** public key bytes.
  ///
  /// Ethereum/Tron → uncompressed 65B, Bitcoin → compressed 33B,
  /// Solana/Sui → Ed25519 32B.
  static Uint8List? publicKeyForChain(String chain, String privkeyHex) {
    final c = _str(chain);
    final k = _str(privkeyHex);
    try {
      return _resultToOptionalBytes(_pubkeyForChain(c, k));
    } finally {
      calloc.free(c);
      calloc.free(k);
    }
  }

  /// The chain's **importable** private-key encoding
  /// (ETH `0x`hex / BTC WIF / SOL base58 / Tron hex / Sui `suiprivkey`).
  static String? encodePrivateKey(String chain, String privkeyHex) {
    final c = _str(chain);
    final k = _str(privkeyHex);
    try {
      return _resultToOptionalStr(_encodePrivkey(c, k));
    } finally {
      calloc.free(c);
      calloc.free(k);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Public API — Group 5: Address from seed + path
  // ═══════════════════════════════════════════════════════════════════

  static String? deriveEthAddress(String seedHex, String path) {
    final s = _str(seedHex);
    final p = _str(path);
    try {
      return _resultToOptionalStr(_deriveEthAddr(s, p));
    } finally {
      calloc.free(s);
      calloc.free(p);
    }
  }

  static String? deriveSolAddress(String seedHex, String path) {
    final s = _str(seedHex);
    final p = _str(path);
    try {
      return _resultToOptionalStr(_deriveSolAddr(s, p));
    } finally {
      calloc.free(s);
      calloc.free(p);
    }
  }

  static String? deriveBtcAddress(String seedHex, String path) {
    final s = _str(seedHex);
    final p = _str(path);
    try {
      return _resultToOptionalStr(_deriveBtcAddr(s, p));
    } finally {
      calloc.free(s);
      calloc.free(p);
    }
  }

  static String? deriveTronAddress(String seedHex, String path) {
    final s = _str(seedHex);
    final p = _str(path);
    try {
      return _resultToOptionalStr(_deriveTronAddr(s, p));
    } finally {
      calloc.free(s);
      calloc.free(p);
    }
  }

  static String? deriveSuiAddress(String seedHex, String path) {
    final s = _str(seedHex);
    final p = _str(path);
    try {
      return _resultToOptionalStr(_deriveSuiAddr(s, p));
    } finally {
      calloc.free(s);
      calloc.free(p);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Public API — Group 6: Address from public key
  // ═══════════════════════════════════════════════════════════════════

  static String? p2wpkhAddress(String compressedPubkeyHex) {
    final k = _str(compressedPubkeyHex);
    try {
      return _resultToOptionalStr(_p2wpkh(k));
    } finally {
      calloc.free(k);
    }
  }

  static String? tronAddressFromPubkey(String uncompressedPubkeyHex) {
    final k = _str(uncompressedPubkeyHex);
    try {
      return _resultToOptionalStr(_tronFromPubkey(k));
    } finally {
      calloc.free(k);
    }
  }

  static String? suiAddress(String ed25519PubkeyHex) {
    final k = _str(ed25519PubkeyHex);
    try {
      return _resultToOptionalStr(_suiAddr(k));
    } finally {
      calloc.free(k);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Public API — Group 6b: APDU signing data parser
  // ═══════════════════════════════════════════════════════════════════

  static String? parseSignData(String chain, String payloadHex) {
    final c = _str(chain);
    final p = _str(payloadHex);
    try {
      return _resultToOptionalStr(_parseSignData(c, p));
    } finally {
      calloc.free(c);
      calloc.free(p);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Public API — Group 7: PIN auth + mnemonic encryption
  // ═══════════════════════════════════════════════════════════════════

  static String? pbkdf2Derive(String pin, String saltHex, int keyLen) {
    final p = _str(pin);
    final s = _str(saltHex);
    try {
      return _resultToOptionalStr(_pbkdf2(p, s, keyLen));
    } finally {
      calloc.free(p);
      calloc.free(s);
    }
  }

  static String? mnemonicToSeed(String mnemonic, {String passphrase = ''}) {
    final m = _str(mnemonic);
    final pp = _str(passphrase);
    try {
      return _resultToOptionalStr(_mnemonicToSeed(m, pp));
    } finally {
      calloc.free(m);
      calloc.free(pp);
    }
  }

  static String? chacha20Encrypt(String plaintext, String pin, String saltHex) {
    final pt = _str(plaintext);
    final p = _str(pin);
    final s = _str(saltHex);
    try {
      return _resultToOptionalStr(_chacha20Enc(pt, p, s));
    } finally {
      calloc.free(pt);
      calloc.free(p);
      calloc.free(s);
    }
  }

  static String? chacha20Decrypt(String ciphertextHex, String pin, String saltHex) {
    final ct = _str(ciphertextHex);
    final p = _str(pin);
    final s = _str(saltHex);
    try {
      return _resultToOptionalStr(_chacha20Dec(ct, p, s));
    } finally {
      calloc.free(ct);
      calloc.free(p);
      calloc.free(s);
    }
  }

  static String? historyEncrypt(String plaintext, String seedHex) {
    final pt = _str(plaintext);
    final s = _str(seedHex);
    try {
      return _resultToOptionalStr(_historyEnc(pt, s));
    } finally {
      calloc.free(pt);
      calloc.free(s);
    }
  }

  // ── Key hierarchy (HKDF-Expand + raw-key AEAD) ─────────────────────

  static String? hkdfExpand32(String prkHex, String info) {
    final k = _str(prkHex);
    final i = _str(info);
    try {
      return _resultToOptionalStr(_hkdfExpand32(k, i));
    } finally {
      calloc.free(k);
      calloc.free(i);
    }
  }

  static String? aeadEncryptWithKey(String plaintext, String keyHex) {
    final pt = _str(plaintext);
    final k = _str(keyHex);
    try {
      return _resultToOptionalStr(_aeadEncWithKey(pt, k));
    } finally {
      calloc.free(pt);
      calloc.free(k);
    }
  }

  static String? aeadDecryptWithKey(String ciphertextHex, String keyHex) {
    final ct = _str(ciphertextHex);
    final k = _str(keyHex);
    try {
      return _resultToOptionalStr(_aeadDecWithKey(ct, k));
    } finally {
      calloc.free(ct);
      calloc.free(k);
    }
  }

  static String? historyDecrypt(String cipherHex, String seedHex) {
    final ct = _str(cipherHex);
    final s = _str(seedHex);
    try {
      return _resultToOptionalStr(_historyDec(ct, s));
    } finally {
      calloc.free(ct);
      calloc.free(s);
    }
  }

  /// Constant-time string comparison (see `ICryptoService.constantTimeEquals`).
  static bool constantTimeEquals(String a, String b) {
    final ap = _str(a);
    final bp = _str(b);
    try {
      return _constantTimeEq(ap, bp) != 0;
    } finally {
      calloc.free(ap);
      calloc.free(bp);
    }
  }
}

class Bip39Language {
  Bip39Language._();
  static const int english = 0;
  static const int chineseSimplified = 1;
  static const int chineseTraditional = 2;
  static const int czech = 3;
  static const int french = 4;
  static const int italian = 5;
  static const int japanese = 6;
  static const int korean = 7;
  static const int portuguese = 8;
  static const int spanish = 9;
}
