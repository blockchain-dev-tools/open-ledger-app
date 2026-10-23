import 'dart:math';

import 'package:flutter/foundation.dart';

import '../biz/pin_biz.dart';
import '../core/interfaces/crypto_service.dart';
import '../core/interfaces/pin_auth_service.dart';
import '../core/interfaces/vault_repository.dart';
import '../core/models/vault.dart';

/// PIN authentication service — crypto plumbing + attempt tracking.
///
/// Responsibilities:
/// - PBKDF2-HMAC-SHA256(pin, deviceSalt) → the tier master key ([deriveKey])
/// - HKDF-Expand domain separation for the tier verifier ([verifyKey])
/// - AEAD encrypt/decrypt under a raw key ([encryptWithKey], [decryptWithKey])
/// - PIN matching against tier verifiers, in constant work ([matchCredential])
/// - PIN attempt tracking with lockout (max 5)
///
/// Depends on [ICryptoService] for all cryptographic operations and
/// [IVaultRepository] for persistence. The matching/attempt logic lives in
/// [PinBiz].
class PinAuthService implements IPinAuthService {
  final ICryptoService _crypto;
  final IVaultRepository _repo;

  late final PinBiz _biz;

  PinAuthService({required this._crypto, required this._repo}) {
    _biz = PinBiz(crypto: _crypto, repo: _repo);
  }

  // ── Device salt ────────────────────────────────────────────────────

  @override
  Future<void> ensureDeviceSalt() async {
    final existing = await _repo.getDeviceSalt();
    if (existing != null && existing.isNotEmpty) return;
    await _repo.setDeviceSalt(randomHex(16));
  }

  // ── Key derivation (Rust PBKDF2 + HKDF) ────────────────────────────

  @override
  Future<String> deriveKey(String pin) => _biz.deriveKey(pin);

  @override
  String verifyKey(String masterKeyHex) => _biz.verifyKey(masterKeyHex);

  @override
  String sealVerifier(String verifyKeyHex) {
    final sealed = _crypto.aeadEncryptWithKey(tierVerifyPlaintext, verifyKeyHex);
    if (sealed == null) {
      debugPrint('[PinAuthService] sealVerifier: AEAD encrypt FAILED');
      throw StateError('Tier verifier sealing failed.');
    }
    return sealed;
  }

  @override
  String? get lastMasterKey => _biz.lastMasterKey;

  @override
  void clearMasterKey() => _biz.clearMasterKey();

  // ── AEAD with a raw key (Rust ChaCha20-Poly1305) ───────────────────

  @override
  String encryptWithKey(String plaintext, String keyHex) {
    final result = _crypto.aeadEncryptWithKey(plaintext, keyHex);
    if (result == null) {
      debugPrint('[PinAuthService] encryptWithKey: ChaCha20 encrypt FAILED');
      throw StateError(
        'ChaCha20 encryption failed (plaintext=${plaintext.length} chars)',
      );
    }
    return result;
  }

  @override
  String decryptWithKey(String ciphertextHex, String keyHex) {
    final result = _crypto.aeadDecryptWithKey(ciphertextHex, keyHex);
    if (result == null) {
      debugPrint('[PinAuthService] decryptWithKey: ChaCha20 decrypt FAILED');
      throw StateError(
        'ChaCha20 decryption failed (ciphertext=${ciphertextHex.length} hex '
        'chars). Possible wrong key or corrupted data.',
      );
    }
    return result;
  }

  // ── Random salt generation ─────────────────────────────────────────

  @override
  String randomHex(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return _crypto.hexEncode(bytes);
  }

  // ── Credential matching ────────────────────────────────────────────

  @override
  Future<int?> matchCredential(String pin) => _biz.matchCredential(pin);

  @override
  Future<bool> verifyPin(String pin) => _biz.verifyPin(pin);

  @override
  Future<bool> matchesAnyCredential(String pin) =>
      _biz.matchesAnyCredential(pin);

  // ── PIN attempt tracking (delegated to PinBiz) ────────────────────

  @override
  int get pinAttempts => _biz.pinAttempts;

  @override
  int get maxPinAttempts => PinBiz.maxPinAttempts;

  @override
  Future<bool> isLocked() => _biz.isLocked();

  @override
  Future<void> incrementPinAttempts() => _biz.incrementPinAttempts();

  @override
  Future<void> resetPinAttempts() => _biz.resetPinAttempts();
}
