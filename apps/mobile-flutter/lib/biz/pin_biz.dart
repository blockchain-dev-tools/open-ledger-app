import '../core/interfaces/crypto_service.dart';
import '../core/interfaces/vault_repository.dart';
import '../core/models/vault.dart';

/// PIN authentication business logic.
///
/// Unlocking is **one PBKDF2**: the entered PIN is stretched once with the
/// device salt ([deriveKey]) into the master key, which doubles as the tier's
/// vault key. Each tier stores only a *verifier* — AEAD over a fixed plaintext
/// under `HKDF(masterKey, "verify")` — so "which tier does this PIN belong to?"
/// is answered by trying to open each verifier. Nothing equal to a decryption
/// key is ever stored (ADR-009 §3 revision).
///
/// The slot loop still walks **every** depth without short-circuiting, so
/// unlock cost never reveals how many tiers the device holds. Empty slots are
/// probed with [_dummyVerifier] — an AEAD attempt is microseconds, but keeping
/// the shape uniform means the constant-work property stays obvious.
///
/// The crypto plumbing (PBKDF2, HKDF, AEAD) stays in
/// `lib/services/pin_auth_service.dart`; this class holds the decision logic and
/// depends only on `core/interfaces/`.
class PinBiz {
  final ICryptoService _crypto;
  final IVaultRepository _repo;

  /// Cached PIN attempt count. -1 is the sentinel for "not yet loaded".
  int _pinAttempts = -1;

  static const int maxPinAttempts = 5;

  /// Master key produced by the most recent successful [matchCredential].
  /// The caller consumes it to decrypt the tier that was just opened, so the
  /// expensive derivation never happens twice for one unlock.
  String? _lastMasterKey;

  /// Placeholder for empty tier slots: byte-for-byte the same length as a real
  /// verifier (`nonce ‖ ciphertext+tag`), so an empty slot's AEAD attempt costs
  /// exactly what a configured one does. Its value never authenticates.
  static final String _dummyVerifier =
      '00' * ((12 + tierVerifyPlaintext.length + 16) * 2);

  PinBiz({required this._crypto, required this._repo});

  // ── Public API ───────────────────────────────────────────────────────

  /// Current failed PIN attempt count (0 before first failure).
  int get pinAttempts => _pinAttempts < 0 ? 0 : _pinAttempts;

  /// Master key from the last successful [matchCredential], or `null` when no
  /// match has been made (or after a failed one).
  String? get lastMasterKey => _lastMasterKey;

  /// Drop the cached master key (called when a session ends).
  void clearMasterKey() => _lastMasterKey = null;

  /// Whether the wallet is currently locked out (attempts exhausted).
  Future<bool> isLocked() async {
    await _ensurePinAttemptsLoaded();
    return _pinAttempts >= maxPinAttempts;
  }

  /// Increment the failed-attempt counter and persist.
  Future<void> incrementPinAttempts() async {
    await _ensurePinAttemptsLoaded();
    _pinAttempts++;
    await _repo.setPinAttempts(_pinAttempts);
  }

  /// Reset the failed-attempt counter to zero and persist.
  Future<void> resetPinAttempts() async {
    _pinAttempts = 0;
    await _repo.setPinAttempts(0);
  }

  // ── Key derivation ───────────────────────────────────────────────────

  /// `PBKDF2-HMAC-SHA256(pin, deviceSalt)` → 32 bytes as hex.
  ///
  /// This is the **only** expensive step of an unlock (100k iterations). The
  /// result is the tier's vault key *and* the input of [verifyKey]; the stored
  /// verifier is a ciphertext under the latter, never under the key itself.
  Future<String> deriveKey(String pin) async {
    final salt = await _repo.getDeviceSalt();
    if (salt == null || salt.isEmpty) {
      throw StateError('Device salt missing — no wallet has been set up.');
    }
    final key = _crypto.pbkdf2Derive(pin, salt, 32);
    if (key == null) {
      throw StateError(
        'PBKDF2 derivation failed (pin=${pin.length} chars, '
        'salt=${salt.length} hex chars)',
      );
    }
    return key;
  }

  /// Verifier key for [masterKeyHex]: `HKDF-Expand(masterKey, "verify")`.
  ///
  /// Domain separation keeps the stored verifier from being sealed under the
  /// vault key itself. Costs one HMAC — negligible next to [deriveKey].
  String verifyKey(String masterKeyHex) {
    final key = _crypto.hkdfExpand32(masterKeyHex, tierVerifyContext);
    if (key == null) {
      throw StateError('HKDF-Expand failed (verify context)');
    }
    return key;
  }

  // ── Match PIN ────────────────────────────────────────────────────────

  /// Match [pin] against every tier verifier and return the matched `depth`, or
  /// `null` when nothing matches.
  ///
  /// **Side effects:** on a match caches the master key (see [lastMasterKey])
  /// and resets the attempt counter; otherwise clears it and increments.
  ///
  /// Work is constant: one PBKDF2 (the derivation does not depend on the tier)
  /// plus one AEAD attempt per slot in `0..maxDepth` — real verifier when
  /// configured, [_dummyVerifier] otherwise — and the loop never short-circuits.
  Future<int?> matchCredential(String pin) async {
    await _ensurePinAttemptsLoaded();
    _lastMasterKey = null;

    final masterKey = await deriveKey(pin);
    final verifyKeyHex = verifyKey(masterKey);

    // One AEAD attempt per slot, no early exit. Lowest depth wins ties.
    int? matched;
    for (var d = 0; d <= maxDepth; d++) {
      final cred = await _repo.getCredential(d);
      final opened = _crypto.aeadDecryptWithKey(
        cred?.verifier ?? _dummyVerifier,
        verifyKeyHex,
      );
      if (cred != null && opened == tierVerifyPlaintext) {
        matched ??= d;
      }
    }

    if (matched == null) {
      await incrementPinAttempts();
    } else {
      _lastMasterKey = masterKey;
      await resetPinAttempts();
    }
    return matched;
  }

  /// Whether [pin] matches any configured tier, with **no** effect on the
  /// failed-attempt counter and no master key cached. Used to enforce global
  /// PIN uniqueness.
  Future<bool> matchesAnyCredential(String pin) async {
    final masterKey = await deriveKey(pin);
    final verifyKeyHex = verifyKey(masterKey);
    for (var d = 0; d <= maxDepth; d++) {
      final cred = await _repo.getCredential(d);
      if (cred == null) continue;
      if (_crypto.aeadDecryptWithKey(cred.verifier, verifyKeyHex) ==
          tierVerifyPlaintext) {
        return true;
      }
    }
    return false;
  }

  /// Whether [pin] matches any configured credential.
  Future<bool> verifyPin(String pin) async =>
      (await matchCredential(pin)) != null;

  // ── Private helpers ──────────────────────────────────────────────────

  /// Lazy-load the PIN attempt counter from storage on first access.
  Future<void> _ensurePinAttemptsLoaded() async {
    if (_pinAttempts < 0) {
      _pinAttempts = await _repo.getPinAttempts();
    }
  }
}
