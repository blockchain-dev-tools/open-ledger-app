/// Abstract interface for PIN authentication.
///
/// Implemented by [PinAuthService] in `lib/services/`.
/// [WalletService] depends on this interface, never on the concrete implementation.
///
/// **Key hierarchy** (ADR-009 §3 revision): one KDF stretches the PIN with
/// the device salt into a *master key*, which doubles as the tier's vault key.
/// Each tier stores a **verifier** — AEAD over a fixed plaintext under
/// `HKDF(masterKey, "verify")` — so opening it is the PIN check, and no stored
/// value equals a decryption key.
///
/// The KDF is versioned (ADR-007): new credentials use Argon2id, and a legacy
/// PBKDF2 credential is upgraded the first time its tier is unlocked.
///
/// There is one credential per tier (`0..maxDepth`); the depth a PIN belongs to
/// is *verified*, never looked up. PIN *matching* lives here; PIN *change*
/// (which re-encrypts vaults) lives in the wallet layer.
abstract class IPinAuthService {
  /// Create the device-level KDF salt if it does not exist yet.
  ///
  /// Called once when the first wallet is created; the salt then never changes.
  Future<void> ensureDeviceSalt();

  /// `KDF_current(pin, deviceSalt)` → 32 bytes as hex.
  ///
  /// The single expensive step (one Argon2id run). The result is both the
  /// tier's vault key and the input of [verifyKey].
  Future<String> deriveKey(String pin);

  /// [deriveKey] pinned to a specific KDF version (ADR-007).
  ///
  /// Version 0 = legacy PBKDF2, 1 = Argon2id. Used to open a credential written
  /// before the Argon2id switch, and to re-derive during the upgrade.
  Future<String> deriveKeyWithVersion(String pin, int version);

  /// Verifier key for [masterKeyHex] — `HKDF-Expand` domain separation so the
  /// master key itself never seals the stored verifier.
  String verifyKey(String masterKeyHex);

  /// Seal the fixed verifier plaintext under [verifyKeyHex]; the returned
  /// ciphertext is what a tier credential stores.
  String sealVerifier(String verifyKeyHex);

  /// Master key produced by the last successful [matchCredential].
  ///
  /// The caller consumes it to decrypt the tier just opened, so one unlock
  /// costs exactly one PBKDF2. `null` when no match has been made.
  String? get lastMasterKey;

  /// Drop the cached master key (session end / wallet lock).
  void clearMasterKey();

  /// Match [pin] against every tier verifier, in constant work.
  ///
  /// Side effects: caches the master key on a match and resets the
  /// failed-attempt counter; otherwise clears it and increments the counter.
  /// Returns the matched tier `depth`, or `null`.
  Future<int?> matchCredential(String pin);

  /// Whether [pin] matches any configured credential.
  Future<bool> verifyPin(String pin);

  /// Whether [pin] matches any configured tier, with **no** effect on the
  /// failed-attempt counter. Used to enforce global PIN uniqueness.
  Future<bool> matchesAnyCredential(String pin);

  /// Current PIN attempt count.
  int get pinAttempts;

  /// Max allowed PIN attempts before lockout.
  int get maxPinAttempts;

  /// Whether the wallet is currently locked out.
  Future<bool> isLocked();

  /// Increment the failed PIN attempt counter.
  Future<void> incrementPinAttempts();

  /// Reset the PIN attempt counter to zero.
  Future<void> resetPinAttempts();

  /// AEAD-encrypt [plaintext] under the raw 32-byte key [keyHex].
  String encryptWithKey(String plaintext, String keyHex);

  /// AEAD-decrypt [ciphertextHex] under [keyHex].
  ///
  /// Throws when it cannot be opened (wrong key / corruption) — callers that
  /// expect failure as a normal outcome use `ICryptoService` directly.
  String decryptWithKey(String ciphertextHex, String keyHex);

  /// Generate [length] random bytes as a hex string.
  String randomHex(int length);
}
