import '../core/interfaces/account_service.dart';
import '../core/interfaces/mnemonic_service.dart';
import '../core/interfaces/pin_auth_service.dart';
import '../core/interfaces/vault_repository.dart';
import '../core/models/vault.dart';
import '../core/models/wallet_accounts.dart';

/// Multi-vault wallet lifecycle business logic (ADR-010 / depth).
///
/// A *session* is opened by a PIN and bound to one **tier** (`depth`):
/// - the PIN that matches tier `d` loads **every** vault at `depth == d`
///   (decrypted and cached up front); tiers are invisible to one another
///   (ADR-009 I14);
/// - a session may itself configure a stand-in one level deeper
///   (`depth + 1`), so stand-ins nest: `0 ← 1 ← 2` (`maxDepth`).
///
/// UI-framework-agnostic: imports only `core/interfaces/` + `core/models/`.
class WalletBiz {
  final IPinAuthService _pinAuth;
  final IAccountService _accountService;
  final IMnemonicService _mnemonicService;
  final IVaultRepository _repo;

  /// Max allowed PIN attempts before lockout.
  static const int maxPinAttempts = 5;

  // ── Session state ───────────────────────────────────────────────────

  int? _depth;
  List<Vault> _vaults = const [];
  String? _activeVaultId;

  final Map<String, String> _mnemonics = {};
  final Map<String, String> _seeds = {};
  final Map<String, String> _passphrases = {};

  /// Set by [unlockWallet] when a `wipe` stand-in erased the tier it replaced.
  bool _lastUnlockWiped = false;

  /// Fired whenever the **active vault** changes inside a live session — a
  /// switch ([switchVault]), a removal that reassigns the active vault
  /// ([removeVault]), or the first vault added to an empty session
  /// ([addVault]).
  ///
  /// The app assembly wires this to the BLE layer so a connected host never
  /// keeps signing with the previous vault's seed (see
  /// `BleSession.onActiveVaultChanged`).
  void Function()? onActiveVaultChanged;

  /// Fired with the ids of vaults destroyed for good — a removal
  /// ([removeVault]) or a cleared tier ([_clearTier], which covers
  /// [clearWallet], [removeStandIn] and the `wipe` unlock path).
  ///
  /// The app assembly drops their persisted signing history: the ciphertext
  /// is unreadable once the seed is gone, but leaving it under
  /// `wallet.signHistory` still records how many wallets the device held.
  void Function(Set<String> vaultIds)? onVaultsDestroyed;

  WalletBiz({
    required this._pinAuth,
    required this._accountService,
    required this._mnemonicService,
    required this._repo,
  });

  // ── Session getters ─────────────────────────────────────────────────

  /// Whether a session is open (a vault is active).
  bool get isUnlocked => _activeVaultId != null;

  /// Tier that opened the current session, or `null` when locked.
  int? get sessionDepth => _depth;

  /// Whether the current session is a stand-in tier (`depth > 0`).
  bool get isStandInSession => _depth != null && _depth! > 0;

  /// Vaults visible to the current session.
  List<Vault> get vaults => List.unmodifiable(_vaults);

  /// Id of the active (currently shown) vault.
  String? get activeVaultId => _activeVaultId;

  /// The active vault, or `null` when locked.
  Vault? get activeVault {
    for (final v in _vaults) {
      if (v.id == _activeVaultId) return v;
    }
    return null;
  }

  /// Cached mnemonic for the active vault (available only when unlocked).
  String? get mnemonic =>
      _activeVaultId == null ? null : _mnemonics[_activeVaultId];

  /// Pre-computed seed hex for the active vault.
  String? get seedHex => _activeVaultId == null ? null : _seeds[_activeVaultId];

  /// Cached passphrase for the active vault (empty string if none).
  String? get passphrase =>
      _activeVaultId == null ? null : (_passphrases[_activeVaultId] ?? '');

  /// Accounts of the active vault.
  WalletAccounts? get accounts => activeVault?.accounts;

  // ── Existence / stand-in queries ────────────────────────────────────

  Future<bool> hasWallet() => _repo.hasWallet();

  /// The tier a stand-in configured from the current session would occupy.
  int get _childDepth => (_depth ?? 0) + 1;

  /// Whether the current session has a stand-in configured one tier deeper.
  Future<bool> hasStandIn() async =>
      (await _repo.getCredential(_childDepth)) != null;

  /// Configured behaviour of the stand-in the current session set up for its
  /// child tier (`depth + 1`). Session-relative, like [hasStandIn].
  Future<StandInMode> standInMode() => _repo.getStandInMode(_childDepth);

  /// Whether the most recent [unlockWallet] ran the stand-in `wipe` mode and
  /// erased the tier it replaced. The caller clears the matching history.
  bool get lastUnlockWiped => _lastUnlockWiped;

  // ── Wallet lifecycle ───────────────────────────────────────────────

  /// Create the first wallet: the depth-0 credential + one depth-0 vault.
  Future<WalletAccounts> setupWallet(
    String mnemonic, {
    required String pin,
    String passphrase = '',
    bool storePassphrase = false,
    VaultSource source = VaultSource.imported,
    int enigmaLanguage = 0,
  }) async {
    await _pinAuth.ensureDeviceSalt();
    final vaultKey = await _pinAuth.deriveKey(pin);
    final encrypted = _pinAuth.encryptWithKey(mnemonic, vaultKey);
    final fingerprint = _mnemonicService.fingerprintMnemonic(mnemonic);
    final seed = _mnemonicService.mnemonicToSeedHex(mnemonic, passphrase);
    final derived = await _accountService.deriveDefaultAccounts(
      mnemonic,
      passphrase,
      seed,
    );

    final vault = Vault(
      id: _repo.newVaultId(),
      label: '',
      depth: 0,
      mnemonicEncrypted: encrypted,
      passphraseEncrypted: (storePassphrase && passphrase.isNotEmpty)
          ? _pinAuth.encryptWithKey(passphrase, vaultKey)
          : null,
      accounts: derived.copyWith(mnemonicFingerprint: fingerprint),
      createdAt: DateTime.now().millisecondsSinceEpoch,
      source: source,
      enigmaLanguage: enigmaLanguage,
    );

    await _repo.setCredential(
      WalletCredential(
        depth: 0,
        verifier: _pinAuth.sealVerifier(_pinAuth.verifyKey(vaultKey)),
        kdfVersion: currentKdfVersion,
      ),
    );
    await _repo.saveVault(vault);

    _beginSession(0, [vault], vault.id);
    _mnemonics[vault.id] = mnemonic;
    _seeds[vault.id] = seed;
    _passphrases[vault.id] = passphrase;
    await _pinAuth.resetPinAttempts();

    return vault.accounts;
  }

  /// Open a session: match [pin], then load the tier it unlocks.
  ///
  /// With `wipe` mode, matching a stand-in PIN (tier `d ≥ 1`) erases the tier
  /// it replaced (`d - 1`) before loading (ADR-009 §7) and resets the mode.
  Future<WalletAccounts> unlockWallet(String pin) async {
    if (await _pinAuth.isLocked()) {
      throw StateError(
        'Wallet is locked after $maxPinAttempts failed attempts. '
        'Reset the wallet and import your mnemonic to recover.',
      );
    }

    _lastUnlockWiped = false;
    final d = await _pinAuth.matchCredential(pin);
    if (d == null) {
      throw StateError('Incorrect PIN');
    }
    // Consume the key that [matchCredential] derived, so this unlock costs
    // exactly one PBKDF2 rather than re-deriving per vault.
    final vaultKey = _pinAuth.lastMasterKey;
    if (vaultKey == null) {
      throw StateError('Wallet data corrupted: no session key.');
    }

    final cred = await _repo.getCredential(d);
    if (cred == null) {
      throw StateError('Wallet data corrupted: missing credential.');
    }

    final vaults = await _repo.listVaults(depth: d);
    if (vaults.isEmpty) {
      throw StateError('Wallet data corrupted: no vaults found.');
    }

    // A stand-in may erase the tier it replaced before showing itself. The
    // mode is read from the tier being entered ([d]) — per-tier storage keeps
    // a nested `wipe` (configured at depth 2) from being applied when a
    // depth-1 PIN unlocks.
    final wiping =
        d >= 1 && await _repo.getStandInMode(d) == StandInMode.wipe;

    // A wipe is irreversible, so only then is the target tier validated up
    // front: every vault must decrypt with this tier's credential before a
    // single vault is destroyed, and a corrupt target must throw without
    // touching anything (see ADR-009 §7). The non-destructive path decrypts
    // exactly once, when the session loads below.
    if (wiping) {
      for (final v in vaults) {
        _assertVaultDecryptable(v, vaultKey);
      }
      await _clearTier(d - 1);
      _lastUnlockWiped = true;
      // Nothing left to erase on the next unlock.
      await _repo.setStandInMode(d, StandInMode.hide);
    }

    _beginSession(d, vaults, vaults.first.id);
    for (final v in vaults) {
      await _loadVaultIntoSession(v, vaultKey);
    }
    // The PIN is proven and the plaintext is cached, so a pre-Argon2id tier can
    // be upgraded in place without asking the user for anything.
    await _upgradeTierKdf(d, pin, cred.kdfVersion);
    await _pinAuth.resetPinAttempts();
    return accounts!;
  }

  /// Migrate tier [depth] from its legacy KDF to the current one (ADR-007).
  ///
  /// Re-derives the master key under [currentKdfVersion], re-encrypts every
  /// vault of the tier (mnemonic + passphrase) and rewrites the verifier. The
  /// vault writes and the credential write go through [_rekeyTier], so a
  /// failure rolls the ciphertexts back and the tier stays consistent — and
  /// merely legacy.
  ///
  /// **Best effort:** a failure here must not block an unlock whose PIN was
  /// just accepted; the next unlock simply retries.
  Future<void> _upgradeTierKdf(int depth, String pin, int version) async {
    if (version == currentKdfVersion) return;

    try {
      final newKey = await _pinAuth.deriveKeyWithVersion(pin, currentKdfVersion);

      final originals = {for (final v in _vaults) v.id: v};
      final rewritten = <Vault>[];
      for (final v in _vaults) {
        final encPass = v.passphraseEncrypted;
        rewritten.add(v.copyWith(
          mnemonicEncrypted:
              _pinAuth.encryptWithKey(_mnemonics[v.id]!, newKey),
          passphraseEncrypted: (encPass != null && encPass.isNotEmpty)
              ? _pinAuth.encryptWithKey(_passphrases[v.id] ?? '', newKey)
              : null,
        ));
      }

      await _rekeyTier(rewritten, originals, () async {
        await _repo.setCredential(
          WalletCredential(
            depth: depth,
            verifier: _pinAuth.sealVerifier(_pinAuth.verifyKey(newKey)),
            kdfVersion: currentKdfVersion,
          ),
        );
      });

      for (final v in rewritten) {
        _replaceVault(v);
      }
    } catch (_) {
      // Left on the legacy credential on purpose — retried next unlock.
    }
  }

  /// Decrypt [vault]'s secrets with the tier key [vaultKey], discarding the
  /// result. Throws (via the crypto layer) when the ciphertext cannot be
  /// opened, flagging a corrupted tier.
  void _assertVaultDecryptable(Vault vault, String vaultKey) {
    _pinAuth.decryptWithKey(vault.mnemonicEncrypted, vaultKey);
    final encPass = vault.passphraseEncrypted;
    if (encPass != null && encPass.isNotEmpty) {
      _pinAuth.decryptWithKey(encPass, vaultKey);
    }
  }

  /// Decrypt [vault] into the session cache and refresh its derived accounts.
  Future<void> _loadVaultIntoSession(Vault vault, String vaultKey) async {
    final mnemonic = _pinAuth.decryptWithKey(vault.mnemonicEncrypted, vaultKey);
    String passphrase = '';
    final encPass = vault.passphraseEncrypted;
    if (encPass != null && encPass.isNotEmpty) {
      passphrase = _pinAuth.decryptWithKey(encPass, vaultKey);
    }
    final seed = _mnemonicService.mnemonicToSeedHex(mnemonic, passphrase);

    _mnemonics[vault.id] = mnemonic;
    _passphrases[vault.id] = passphrase;
    _seeds[vault.id] = seed;

    // Re-derive defaults and merge persisted extras (pre-vault behaviour).
    var refreshed = await _accountService.deriveDefaultAccounts(
      mnemonic,
      passphrase,
      seed,
    );
    if (vault.accounts.accounts.isNotEmpty) {
      final defaults = refreshed.accounts.map((a) => a.address).toSet();
      final extras = vault.accounts.accounts.where(
        (a) => !defaults.contains(a.address),
      );
      refreshed = refreshed.copyWith(
        accounts: [...refreshed.accounts, ...extras],
      );
    }

    final updated = vault.copyWith(accounts: refreshed);
    // Only write back when the re-derived accounts actually differ — an
    // unchanged unlock must not rewrite every vault of the tier.
    if (refreshed != vault.accounts) {
      _replaceVault(updated);
      await _repo.saveVault(updated);
    }
  }

  /// Add a vault to the **current session's** tier.
  ///
  /// Works in any session; only the depth-0 tier is capped at
  /// [maxNormalVaults]. A wallet already present in this tier (same mnemonic
  /// *and* same passphrase) is rejected — that would be the same wallet twice.
  Future<WalletAccounts> addVault(
    String mnemonic, {
    required String pin,
    String passphrase = '',
    bool storePassphrase = false,
    String label = '',
    VaultSource source = VaultSource.imported,
    int enigmaLanguage = 0,
  }) async {
    _assertUnlocked();
    await _requireSessionPin(pin);
    // [_requireSessionPin] just derived the session key — reuse it instead of
    // paying for a second PBKDF2.
    final vaultKey = _pinAuth.lastMasterKey;
    if (vaultKey == null) throw StateError('Missing session key.');

    final d = _depth!;
    _assertWalletNotInTier(mnemonic, passphrase);
    if (d == 0 &&
        (await _repo.listVaults(depth: 0)).length >= maxNormalVaults) {
      throw StateError('Vault limit reached ($maxNormalVaults).');
    }

    final encrypted = _pinAuth.encryptWithKey(mnemonic, vaultKey);
    final fingerprint = _mnemonicService.fingerprintMnemonic(mnemonic);
    final seed = _mnemonicService.mnemonicToSeedHex(mnemonic, passphrase);
    final derived = await _accountService.deriveDefaultAccounts(
      mnemonic,
      passphrase,
      seed,
    );

    final vault = Vault(
      id: _repo.newVaultId(),
      label: label,
      depth: d,
      mnemonicEncrypted: encrypted,
      passphraseEncrypted: (storePassphrase && passphrase.isNotEmpty)
          ? _pinAuth.encryptWithKey(passphrase, vaultKey)
          : null,
      accounts: derived.copyWith(mnemonicFingerprint: fingerprint),
      createdAt: DateTime.now().millisecondsSinceEpoch,
      source: source,
      enigmaLanguage: enigmaLanguage,
    );

    await _repo.saveVault(vault);
    _vaults = [..._vaults, vault];
    _mnemonics[vault.id] = mnemonic;
    _seeds[vault.id] = seed;
    _passphrases[vault.id] = passphrase;
    _setActiveVault(_activeVaultId ?? vault.id);
    return vault.accounts;
  }

  /// Remove a vault from the current session (re-auth gate).
  Future<void> removeVault(String id, {required String pin}) async {
    _assertUnlocked();
    await _requireSessionPin(pin);
    if (_vaults.length <= 1) {
      throw StateError('Cannot remove the last vault of this session.');
    }
    if (!_vaults.any((v) => v.id == id)) {
      throw StateError('Unknown vault: $id');
    }

    await _repo.deleteVault(id);
    _vaults = _vaults.where((v) => v.id != id).toList();
    _mnemonics.remove(id);
    _seeds.remove(id);
    _passphrases.remove(id);
    if (_activeVaultId == id) _setActiveVault(_vaults.first.id);
    onVaultsDestroyed?.call({id});
  }

  /// Switch the active vault within the current session (no re-auth needed:
  /// every vault of the session is already decrypted).
  Future<void> switchVault(String id) async {
    _assertUnlocked();
    if (!_vaults.any((v) => v.id == id)) {
      throw StateError('Unknown vault: $id');
    }
    _setActiveVault(id);
  }

  /// Reveal the active vault's mnemonic.
  ///
  /// Requires [pin] to match the **session** tier (I6 re-verification).
  Future<String?> revealMnemonic(String pin) async {
    final matched = await _pinAuth.matchCredential(pin);
    if (matched == null || matched != _depth) return null;
    return mnemonic;
  }

  /// Whether [pin] matches the **current session's** tier credential.
  ///
  /// Session-scoped, unlike `IPinAuthService.verifyPin` (which accepts a PIN
  /// from *any* tier). Gates actions bound to the active session — changing
  /// the PIN, revealing the seed — so entering another tier's valid PIN is
  /// rejected up front instead of failing later with a misleading error.
  /// Returns `false` while locked.
  Future<bool> verifySessionPin(String pin) async {
    if (_depth == null) return false;
    return await _pinAuth.matchCredential(pin) == _depth;
  }

  /// Change the PIN of the current session's tier, re-encrypting every vault
  /// it protects.
  ///
  /// The new PIN must be globally unique. `matchCredential` resolves ties to
  /// the **lowest** depth, so reusing another tier's PIN would make that tier
  /// permanently unreachable — and would silently disable a `wipe` stand-in,
  /// whose whole purpose is to fire on its own PIN.
  Future<bool> updatePin(String oldPin, String newPin) async {
    if (!isUnlocked) return false;
    final d = _depth!;
    final matched = await _pinAuth.matchCredential(oldPin);
    if (matched != d) return false;
    if (await _pinAuth.matchesAnyCredential(newPin)) {
      throw StateError('The new PIN is already in use by another wallet.');
    }

    final newKey = await _pinAuth.deriveKey(newPin);

    final originals = <String, Vault>{};
    final rewritten = <Vault>[];
    for (final v in List<Vault>.of(_vaults)) {
      final m = _mnemonics[v.id];
      if (m == null) continue; // not loaded → nothing to re-encrypt
      final encPass = v.passphraseEncrypted;
      originals[v.id] = v;
      rewritten.add(v.copyWith(
        mnemonicEncrypted: _pinAuth.encryptWithKey(m, newKey),
        passphraseEncrypted: (encPass != null && encPass.isNotEmpty)
            ? _pinAuth.encryptWithKey(_passphrases[v.id] ?? '', newKey)
            : null,
      ));
    }

    await _rekeyTier(rewritten, originals, () async {
      // The device salt never changes, so only the verifier is rewritten here.
      await _repo.setCredential(
        WalletCredential(
          depth: d,
          verifier: _pinAuth.sealVerifier(_pinAuth.verifyKey(newKey)),
          kdfVersion: currentKdfVersion,
        ),
      );
    });

    // Storage is consistent — mirror it in the live session.
    for (final v in rewritten) {
      _replaceVault(v);
    }
    return true;
  }

  // ── Stand-in management (ADR-009) ──────────────────────────────────

  /// Create (or re-create) the stand-in for the **current session** — one
  /// tier deeper (`depth + 1`).
  ///
  /// [mainPin] re-authenticates the current session's PIN; [pin] is the new
  /// stand-in PIN, which must be globally unique (different from every other
  /// tier's PIN). Creates the child credential plus one child vault and stores
  /// [mode]. Reachable from any session, so stand-ins nest.
  Future<void> configureStandIn(
    String mnemonic, {
    required String pin,
    required String mainPin,
    StandInMode mode = StandInMode.hide,
    VaultSource source = VaultSource.imported,
    int enigmaLanguage = 0,
  }) async {
    _assertUnlocked();
    final child = _childDepth;
    if (child > maxDepth) {
      throw StateError('Maximum stand-in depth reached ($maxDepth).');
    }
    if (await _pinAuth.matchesAnyCredential(pin) || pin == mainPin) {
      throw StateError('The stand-in PIN must differ from your main PIN.');
    }
    final matched = await _pinAuth.matchCredential(mainPin);
    if (matched != _depth) throw StateError('Incorrect PIN');
    if (await _repo.getCredential(child) != null) {
      throw StateError('Stand-in wallet already configured.');
    }

    final childKey = await _pinAuth.deriveKey(pin);
    final fingerprint = _mnemonicService.fingerprintMnemonic(mnemonic);
    final derived = await _accountService.deriveDefaultAccounts(
      mnemonic,
      '',
      _mnemonicService.mnemonicToSeedHex(mnemonic, ''),
    );
    final vault = Vault(
      id: _repo.newVaultId(),
      label: '',
      depth: child,
      mnemonicEncrypted: _pinAuth.encryptWithKey(mnemonic, childKey),
      accounts: derived.copyWith(mnemonicFingerprint: fingerprint),
      createdAt: DateTime.now().millisecondsSinceEpoch,
      source: source,
      enigmaLanguage: enigmaLanguage,
    );

    // Write the vault first, then its credential, then the mode. A crash
    // between the first two writes would otherwise leave an *orphan
    // credential* (a PIN with no wallet → "data corrupted" on unlock), so on
    // a credential-write failure we roll the freshly written vault back.
    await _repo.saveVault(vault);
    try {
      await _repo.setCredential(
        WalletCredential(
          depth: child,
          verifier: _pinAuth.sealVerifier(_pinAuth.verifyKey(childKey)),
          kdfVersion: currentKdfVersion,
        ),
      );
    } catch (_) {
      // Best effort — never leave a vault whose tier credential is missing.
      try {
        await _repo.deleteVault(vault.id);
      } catch (_) {}
      rethrow;
    }
    // The mode belongs to the *child* tier's slot (this session's stand-in).
    await _repo.setStandInMode(child, mode);
  }

  /// Change the stand-in PIN of the current session's child tier (`depth+1`).
  ///
  /// Requires the **current stand-in PIN**: it both authorises the change and
  /// decrypts the child vaults for re-encryption. The new PIN must be globally
  /// unique.
  Future<void> updateStandInPin({
    required String oldPin,
    required String newPin,
  }) async {
    _assertUnlocked();
    final child = _childDepth;
    final cred = await _repo.getCredential(child);
    if (cred == null) throw StateError('No stand-in wallet configured.');
    if (await _pinAuth.matchesAnyCredential(newPin)) {
      throw StateError('The stand-in PIN must differ from your main PIN.');
    }
    final matched = await _pinAuth.matchCredential(oldPin);
    if (matched != child) throw StateError('Incorrect PIN');
    final oldChildKey = _pinAuth.lastMasterKey;
    if (oldChildKey == null) throw StateError('Incorrect PIN');
    final newChildKey = await _pinAuth.deriveKey(newPin);

    final hidden = await _repo.listVaults(depth: child);
    final originals = <String, Vault>{};
    final rewritten = <Vault>[];
    for (final v in hidden) {
      final mnemonic = _pinAuth.decryptWithKey(v.mnemonicEncrypted, oldChildKey);
      final encPass = v.passphraseEncrypted;
      originals[v.id] = v;
      rewritten.add(v.copyWith(
        mnemonicEncrypted: _pinAuth.encryptWithKey(mnemonic, newChildKey),
        // The passphrase ciphertext is bound to the same tier key, so it has
        // to be re-encrypted too — otherwise the tier becomes undecryptable.
        passphraseEncrypted: (encPass != null && encPass.isNotEmpty)
            ? _pinAuth.encryptWithKey(
                _pinAuth.decryptWithKey(encPass, oldChildKey),
                newChildKey,
              )
            : null,
      ));
    }

    await _rekeyTier(rewritten, originals, () async {
      await _repo.setCredential(
        WalletCredential(
          depth: child,
          verifier: _pinAuth.sealVerifier(_pinAuth.verifyKey(newChildKey)),
          kdfVersion: currentKdfVersion,
        ),
      );
    });
  }

  /// Change the stand-in behaviour mode (hide / wipe). No crypto involved —
  /// authorised by the **current session's** PIN.
  Future<void> updateStandInMode({
    required String pin,
    required StandInMode mode,
  }) async {
    _assertUnlocked();
    final matched = await _pinAuth.matchCredential(pin);
    if (matched != _depth) throw StateError('Incorrect PIN');
    if (await _repo.getCredential(_childDepth) == null) {
      throw StateError('No stand-in wallet configured.');
    }
    await _repo.setStandInMode(_childDepth, mode);
  }

  /// Remove the current session's stand-in (child vaults + child credential,
  /// cascading any deeper tiers). Authorised by the current session's PIN;
  /// never touches shallower tiers.
  Future<void> removeStandIn({required String pin}) async {
    _assertUnlocked();
    final matched = await _pinAuth.matchCredential(pin);
    if (matched != _depth) throw StateError('Incorrect PIN');

    await _clearDepthsFrom(_childDepth);
    // Reset the child tier's own mode slot (its stand-in is gone).
    await _repo.setStandInMode(_childDepth, StandInMode.hide);
  }

  // ── Account management (active vault) ──────────────────────────────

  Future<WalletAccounts> addAccount(String chain, String path) async {
    final vault = activeVault;
    final seed = seedHex;
    if (vault == null || seed == null) {
      throw StateError('Wallet is locked. Call unlockWallet() first.');
    }

    final account = await _accountService.deriveSingleAccount(
      chain,
      path,
      seed,
    );
    if (account == null) {
      throw StateError('Failed to derive account for $chain at $path');
    }

    final existing = vault.accounts.accounts.where(
      (a) => a.address == account.address && a.chain == account.chain,
    );
    if (existing.isNotEmpty) return vault.accounts;

    final updated = _accountService.addAccountToList(vault.accounts, account);
    await _saveActiveAccounts(updated);
    return updated;
  }

  Future<WalletAccounts> removeAccount(String chain, String address) async {
    final vault = activeVault;
    if (vault == null) {
      throw StateError('Wallet is locked. Call unlockWallet() first.');
    }
    final updated = _accountService.removeAccountFromList(
      vault.accounts,
      chain,
      address,
    );
    await _saveActiveAccounts(updated);
    return updated;
  }

  /// Rename a vault in the current session.
  Future<void> renameVault(String id, String label) async {
    _assertUnlocked();
    final vault = _vaults.where((v) => v.id == id).firstOrNull;
    if (vault == null) throw StateError('Unknown vault: $id');
    final updated = vault.copyWith(label: label);
    _replaceVault(updated);
    await _repo.saveVault(updated);
  }

  // ── Lock / clear ───────────────────────────────────────────────────

  /// Lock the wallet: drop every decrypted secret and the session.
  void lock() => _clearSession();

  /// Reset the current session's tier back to "no wallet".
  ///
  /// Session-scoped (ADR-009 I14): clears the current tier **and every deeper
  /// tier** (which would otherwise be orphaned), never a shallower one. When
  /// locked, the scope falls back to the primary tier (depth 0).
  Future<void> clearWallet() async {
    final d = _depth ?? 0;
    await _clearDepthsFrom(d);
    // The child tier of the primary session (depth 1) is cascade-cleared
    // above, so its own stand-in mode slot must be reset too.
    if (d == 0) await _repo.setStandInMode(1, StandInMode.hide);
    _clearSession();
  }

  /// Wipe **every** tier and credential (unlock screen's "forgot PIN → reset").
  Future<void> resetAll() async {
    await _repo.clearAll();
    // The attempt counter is cached in memory, so clearing only the storage
    // keys would leave the lockout state behind.
    await _pinAuth.resetPinAttempts();
    _clearSession();
  }

  // ── Private helpers ────────────────────────────────────────────────

  /// Point the session at [id] and fire [onActiveVaultChanged] when the
  /// active vault genuinely changed.
  ///
  /// Only in-session switches go through here (the new vault's seed is already
  /// cached); session open/close set [_activeVaultId] directly because the BLE
  /// layer refreshes its context on those transitions via its own hooks.
  void _setActiveVault(String id) {
    if (_activeVaultId == id) return;
    _activeVaultId = id;
    onActiveVaultChanged?.call();
  }

  void _beginSession(int depth, List<Vault> vaults, String activeId) {
    _clearSession();
    _depth = depth;
    _vaults = List<Vault>.of(vaults);
    _activeVaultId = activeId;
  }

  void _clearSession() {
    _depth = null;
    _vaults = const [];
    _activeVaultId = null;
    _mnemonics.clear();
    _seeds.clear();
    _passphrases.clear();
  }

  void _replaceVault(Vault updated) {
    _vaults = [for (final v in _vaults) v.id == updated.id ? updated : v];
  }

  /// Persist a tier's re-encrypted vaults, then hand the tier over to its new
  /// credential via [switchCredential].
  ///
  /// The two steps cannot be interleaved: a vault sealed under the new key
  /// while storage still holds the old verifier is permanently undecryptable
  /// (nothing can open it, and the PIN that could is no longer accepted), so
  /// every ciphertext is written **first** and any failure — including one in
  /// [switchCredential] — rolls the already-written vaults back to
  /// [originals].
  Future<void> _rekeyTier(
    List<Vault> rewritten,
    Map<String, Vault> originals,
    Future<void> Function() switchCredential,
  ) async {
    final written = <Vault>[];
    try {
      for (final v in rewritten) {
        await _repo.saveVault(v);
        written.add(v);
      }
      await switchCredential();
    } catch (_) {
      for (final v in written) {
        final original = originals[v.id];
        if (original == null) continue;
        try {
          await _repo.saveVault(original);
        } catch (_) {
          // Storage is failing; there is nothing better we can do.
        }
      }
      rethrow;
    }
  }

  /// Delete the vaults and credential of exactly tier [depth] (no cascade).
  Future<void> _clearTier(int depth) async {
    // Read the ids first — once the vaults are gone nothing is left to tell
    // the app assembly which signing history to drop.
    final doomed = await _repo.listVaults(depth: depth);
    await _repo.deleteVaultsAtDepth(depth);
    await _repo.deleteCredential(depth);
    if (doomed.isNotEmpty) {
      onVaultsDestroyed?.call(doomed.map((v) => v.id).toSet());
    }
  }

  /// Delete tier [from] and every deeper tier (vaults + credentials), leaving
  /// shallower tiers intact.
  Future<void> _clearDepthsFrom(int from) async {
    for (var d = from; d <= maxDepth; d++) {
      await _clearTier(d);
    }
  }

  Future<void> _saveActiveAccounts(WalletAccounts accounts) async {
    final vault = activeVault;
    if (vault == null) {
      throw StateError('Wallet is locked. Call unlockWallet() first.');
    }
    final updated = vault.copyWith(accounts: accounts);
    _replaceVault(updated);
    await _repo.saveVault(updated);
  }

  /// Reject a wallet already present in the current tier.
  ///
  /// Compares the **decrypted plaintext** — the session holds every vault of
  /// its tier — rather than `mnemonicFingerprint`, which is a 32-bit
  /// non-cryptographic hash of the mnemonic *alone* and would therefore also
  /// flag "same mnemonic, different passphrase": two genuinely different
  /// wallets that may legitimately coexist.
  ///
  /// Assumes the caller passes the mnemonic in canonical form; a differently
  /// formatted spelling of the same phrase would slip through.
  void _assertWalletNotInTier(String mnemonic, String passphrase) {
    for (final v in _vaults) {
      if (_mnemonics[v.id] == mnemonic &&
          (_passphrases[v.id] ?? '') == passphrase) {
        throw StateError('This wallet is already in this tier.');
      }
    }
  }

  Future<void> _requireSessionPin(String pin) async {
    final matched = await _pinAuth.matchCredential(pin);
    if (matched == null) throw StateError('Incorrect PIN');
    if (matched != _depth) {
      throw StateError('PIN does not match the current wallet.');
    }
  }

  void _assertUnlocked() {
    if (_activeVaultId == null) {
      throw StateError('Wallet is locked. Call unlockWallet() first.');
    }
  }
}
