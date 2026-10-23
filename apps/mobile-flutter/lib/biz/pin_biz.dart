import '../core/interfaces/crypto_service.dart';
import '../core/interfaces/vault_repository.dart';
import '../core/models/vault.dart';

/// PIN authentication business logic.
///
/// Unlocking is **one KDF**: the entered PIN is stretched once with the device
/// salt ([deriveKey]) into the master key, which doubles as the tier's vault
/// key. Each tier stores only a *verifier* — AEAD over a fixed plaintext under
/// `HKDF(masterKey, "verify")` — so "which tier does this PIN belong to?" is
/// answered by trying to open each verifier. Nothing equal to a decryption key
/// is ever stored (ADR-009 §3 revision).
///
/// The KDF is **versioned** (ADR-007): a credential records whether its
/// verifier was sealed under legacy PBKDF2 or Argon2id. Tiers are migrated one
/// at a time — and a tier's PIN is needed to migrate it — so the two versions
/// coexist until every tier has been unlocked at least once. Only the versions
/// that actually appear on the device are derived, so a fully-upgraded wallet
/// pays for one Argon2id run and nothing else.
///
/// The slot loop still walks **every** depth without short-circuiting, so
/// unlock cost never reveals how many tiers the device holds. Empty slots are
/// probed with [_dummyVerifier] — an AEAD attempt is microseconds, but keeping
/// the shape uniform means the constant-work property stays obvious.
///
/// The crypto plumbing (KDF, HKDF, AEAD) stays in
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

  /// `KDF_current(pin, deviceSalt)` → 32 bytes as hex.
  ///
  /// This is the **only** expensive step of an unlock (one Argon2id run). The
  /// result is the tier's vault key *and* the input of [verifyKey]; the stored
  /// verifier is a ciphertext under the latter, never under the key itself.
  Future<String> deriveKey(String pin) =>
      deriveKeyWithVersion(pin, currentKdfVersion);

  /// [deriveKey] pinned to a specific KDF [version].
  ///
  /// Used to open credentials written before the Argon2id switch, and by the
  /// upgrade path that re-derives under the current version.
  Future<String> deriveKeyWithVersion(String pin, int version) async {
    final salt = await _repo.getDeviceSalt();
    if (salt == null || salt.isEmpty) {
      throw StateError('Device salt missing — no wallet has been set up.');
    }
    final key = _crypto.deriveMasterKey(pin, salt, version);
    if (key == null) {
      throw StateError(
        'Key derivation failed (version=$version, pin=${pin.length} chars, '
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
  /// Work is constant per KDF version in use: one derivation per version (plus
  /// one AEAD attempt per slot in `0..maxDepth` — real verifier when
  /// configured, [_dummyVerifier] otherwise) and the loop never short-circuits.
  Future<int?> matchCredential(String pin) async {
    await _ensurePinAttemptsLoaded();
    _lastMasterKey = null;

    final credentials = await _readAllCredentials();
    final keys = await _deriveKeysFor(pin, credentials);
    final verifyKeys = {
      for (final entry in keys.entries) entry.key: verifyKey(entry.value),
    };

    // One AEAD attempt per slot, no early exit. Lowest depth wins ties.
    int? matched;
    for (var d = 0; d <= maxDepth; d++) {
      final cred = credentials[d];
      final verifierKey = verifyKeys[_probeVersion(cred, verifyKeys)];
      final opened = _crypto.aeadDecryptWithKey(
        cred?.verifier ?? _dummyVerifier,
        verifierKey!,
      );
      if (cred != null && opened == tierVerifyPlaintext) {
        matched ??= d;
      }
    }

    if (matched == null) {
      await incrementPinAttempts();
    } else {
      _lastMasterKey = keys[credentials[matched]!.kdfVersion];
      await resetPinAttempts();
    }
    return matched;
  }

  /// Whether [pin] matches any configured tier, with **no** effect on the
  /// failed-attempt counter and no master key cached. Used to enforce global
  /// PIN uniqueness.
  Future<bool> matchesAnyCredential(String pin) async {
    final credentials = await _readAllCredentials();
    final keys = await _deriveKeysFor(pin, credentials);
    final verifyKeys = {
      for (final entry in keys.entries) entry.key: verifyKey(entry.value),
    };

    for (var d = 0; d <= maxDepth; d++) {
      final cred = credentials[d];
      if (cred == null) continue;
      if (_crypto.aeadDecryptWithKey(
            cred.verifier,
            verifyKeys[cred.kdfVersion]!,
          ) ==
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

  Future<Map<int, WalletCredential?>> _readAllCredentials() async {
    final credentials = <int, WalletCredential?>{};
    for (var d = 0; d <= maxDepth; d++) {
      credentials[d] = await _repo.getCredential(d);
    }
    return credentials;
  }

  /// One key per KDF version actually present on the device.
  ///
  /// A device with no credentials still derives once, under the current
  /// version, so the work shape matches a configured slot.
  Future<Map<int, String>> _deriveKeysFor(
    String pin,
    Map<int, WalletCredential?> credentials,
  ) async {
    final versions = <int>{
      for (final cred in credentials.values)
        if (cred != null) cred.kdfVersion,
    };
    if (versions.isEmpty) versions.add(currentKdfVersion);

    final keys = <int, String>{};
    for (final version in versions) {
      keys[version] = await deriveKeyWithVersion(pin, version);
    }
    return keys;
  }

  /// KDF version used to probe [cred]'s slot. Empty slots have no version of
  /// their own; any derived key works, since [_dummyVerifier] never opens.
  int _probeVersion(WalletCredential? cred, Map<int, String> verifyKeys) =>
      cred?.kdfVersion ?? verifyKeys.keys.first;

  /// Lazy-load the PIN attempt counter from storage on first access.
  Future<void> _ensurePinAttemptsLoaded() async {
    if (_pinAttempts < 0) {
      _pinAttempts = await _repo.getPinAttempts();
    }
  }
}
