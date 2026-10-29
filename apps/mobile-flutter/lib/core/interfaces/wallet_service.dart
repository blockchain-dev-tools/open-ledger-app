import '../models/vault.dart';
import '../models/wallet_accounts.dart';

/// Interface for wallet lifecycle orchestration.
///
/// Screens depend on this interface, never on the concrete [WalletService].
/// This allows widget tests to mock wallet behavior without touching storage,
/// crypto, or any platform code.
///
/// Depth model: a *session* is opened by a PIN and bound to one tier
/// (`depth`). All vaults of that tier are loaded; other tiers stay invisible
/// (ADR-009 I14). Each session may configure a stand-in one tier deeper.
abstract class IWalletService {
  // ── Wallet existence ───────────────────────────────────────────────

  /// Whether a wallet exists on this device.
  Future<bool> hasWallet();

  // ── Lock state ─────────────────────────────────────────────────────

  /// Whether the wallet is locked out after too many failed PIN attempts.
  Future<bool> isLocked();

  /// Whether the wallet is currently unlocked (a vault is active).
  bool get isUnlocked;

  /// Lock the wallet — clear cached mnemonics, seeds, and accounts.
  void lock();

  // ── PIN auth ───────────────────────────────────────────────────────

  /// Verify a PIN without decrypting any vault.
  ///
  /// Accepts a PIN from **any** tier — correct for the cold-start unlock gate
  /// (the tier a PIN matches decides which session opens). Actions bound to
  /// the active session must use [verifySessionPin] instead.
  Future<bool> verifyPin(String pin);

  /// Verify that [pin] matches the **current session's** tier credential.
  ///
  /// Use for session-scoped actions (change PIN, reveal seed): another tier's
  /// valid PIN must be rejected. Returns `false` while locked.
  Future<bool> verifySessionPin(String pin);

  /// Invoked when the active vault changes inside the session (switch / removal
  /// reassignment / first vault added). Lets the app assembly refresh the BLE
  /// signing context so a connected host never signs with a stale seed.
  set onActiveVaultChanged(void Function()? callback);

  /// Invoked with the ids of vaults destroyed for good (a removal, a cleared
  /// tier, or a `wipe` stand-in unlocking). Lets the app assembly drop their
  /// persisted signing history along with them.
  set onVaultsDestroyed(void Function(Set<String> vaultIds)? callback);

  /// Current PIN attempt count.
  int get pinAttempts;

  /// Max failed PIN attempts before lockout. Shared by every gate — the
  /// cold-start unlock gate and the session gates all count against the same
  /// persisted counter (T-003).
  int get maxPinAttempts;

  // ── Session (multi-vault) ──────────────────────────────────────────

  /// Vaults visible to the current session.
  List<Vault> get vaults;

  /// Id of the active vault.
  String? get activeVaultId;

  /// The active vault.
  Vault? get activeVault;

  /// Tier that opened the current session (`null` when locked).
  int? get sessionDepth;

  /// Whether the current session is a stand-in tier (`depth > 0`).
  bool get isStandInSession;

  /// Whether the current session has a stand-in configured one tier deeper.
  Future<bool> hasStandIn();

  /// Configured stand-in behaviour mode.
  Future<StandInMode> standInMode();

  /// Whether the most recent unlock ran a stand-in `wipe` mode (the replaced
  /// tier was erased). The caller clears the matching signing history.
  bool get lastUnlockWiped;

  /// Create the stand-in for the current session (one tier deeper).
  ///
  /// [source] / [enigmaLanguage] record how the stand-in mnemonic originated
  /// (ADR-011 §4); they default to an imported vault.
  Future<void> configureStandIn(
    String mnemonic, {
    required String pin,
    required String mainPin,
    StandInMode mode = StandInMode.hide,
    VaultSource source = VaultSource.imported,
    int enigmaLanguage = 0,
  });

  /// Change the child stand-in PIN (requires the current stand-in PIN).
  Future<void> updateStandInPin({
    required String oldPin,
    required String newPin,
  });

  /// Change the stand-in mode (requires the current session's PIN).
  Future<void> updateStandInMode({
    required String pin,
    required StandInMode mode,
  });

  /// Remove the current session's stand-in (requires the session PIN).
  Future<void> removeStandIn({required String pin});

  /// Switch the active vault within the current session.
  Future<void> switchVault(String id);

  /// Rename a vault within the current session.
  Future<void> renameVault(String id, String label);

  // ── Wallet lifecycle ───────────────────────────────────────────────

  /// Set up a brand-new wallet (primary credential + one normal vault).
  ///
  /// [source] / [enigmaLanguage] record how the mnemonic originated (ADR-011
  /// §4); they default to an imported vault.
  Future<WalletAccounts> setupWallet(
    String mnemonic, {
    required String pin,
    String passphrase = '',
    bool storePassphrase = false,
    VaultSource source = VaultSource.imported,
    int enigmaLanguage = 0,
  });

  /// Add a vault to the current session's tier.
  Future<WalletAccounts> addVault(
    String mnemonic, {
    required String pin,
    String passphrase = '',
    bool storePassphrase = false,
    String label = '',
    VaultSource source = VaultSource.imported,
    int enigmaLanguage = 0,
  });

  /// Remove a vault from the current session.
  Future<void> removeVault(String id, {required String pin});

  /// Unlock the wallet — open a session for the tier [pin] matches.
  Future<WalletAccounts> unlockWallet(String pin);

  /// Clear the current session's tier (and any deeper tier) — session-scoped
  /// (ADR-009 I14).
  Future<void> clearWallet();

  /// Wipe **every** tier and credential (unlock screen's "forgot PIN").
  Future<void> resetAll();

  // ── Account management ─────────────────────────────────────────────

  /// Get the active vault's accounts.
  WalletAccounts? getAccounts();

  /// Add a new account for [chain] at derivation [path].
  Future<WalletAccounts> addAccount(String chain, String path);

  /// Remove an account by [chain] and [address].
  Future<WalletAccounts> removeAccount(String chain, String address);

  // ── Chain management ───────────────────────────────────────────────

  /// Chain ids the active vault has turned off in "Manage chains".
  Set<String> get hiddenChains;

  /// Persist whether [chain] is hidden in the active vault.
  ///
  /// Hiding keeps the chain's accounts (and history) — it only removes the
  /// chain from the Vault and the BLE picker. Showing a chain with no account
  /// derives nothing here; the caller adds account 0 first.
  Future<void> setChainHidden(String chain, {required bool hidden});

  // ── Mnemonic / Seed ────────────────────────────────────────────────

  /// Reveal the active vault's mnemonic (PIN-gated, I6).
  Future<String?> revealMnemonic(String pin);

  /// The active vault's pre-computed seed hex.
  String? get seedHex;

  /// The active vault's cached mnemonic.
  String? get mnemonic;

  /// The active vault's cached BIP-39 passphrase for the current session.
  ///
  /// `null` while locked; `''` when the vault has none. Mirrors [mnemonic] —
  /// used by the backup verifier to recompute the seed (ADR-011 §5).
  String? get passphrase;

  // ── PIN management ─────────────────────────────────────────────────

  /// Change the current session credential's PIN.
  Future<bool> updatePin(String oldPin, String newPin);
}
