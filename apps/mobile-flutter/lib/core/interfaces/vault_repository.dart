import '../models/vault.dart';

/// Abstract repository for multi-vault wallet persistence (ADR-010 / depth).
///
/// Replaces the single-wallet [IWalletRepository]. Implemented by
/// [VaultRepositoryImpl] in `lib/data/repositories/`.
///
/// Storage layout:
/// - `wallet.salt`                   → device-level KDF salt (one per device)
/// - `wallet.vaultIndex`            → ordered list of vault ids
/// - `wallet.vault.<id>`            → one vault (JSON, carries `depth`)
/// - `wallet.verifier.<depth>`      → PIN verifier ciphertext for that tier
/// - `wallet.standIn.mode.<depth>`  → `hide` | `wipe` for that tier's child
/// - `wallet.pinAttempts`           → global failed-attempt counter (shared)
///
/// A tier (`depth`) owns one credential and any number of vaults. Removing a
/// tier must also prune every deeper tier or it leaves orphans behind — see
/// [deleteVaultsAtDepth] and [deleteCredential].
abstract class IVaultRepository {
  // ── Device salt (KDF input) ─────────────────────────────────────────

  /// Device-level PBKDF2 salt, or `null` before the first wallet is created.
  ///
  /// One salt covers the whole device: tier PINs are globally unique, so each
  /// tier's master key already differs. It never changes — rotating it would
  /// invalidate every verifier and vault ciphertext at once.
  Future<String?> getDeviceSalt();

  /// Persist the device-level salt (written once, at first setup).
  Future<void> setDeviceSalt(String saltHex);

  // ── Vault index ─────────────────────────────────────────────────────

  /// Ordered vault ids.
  Future<List<String>> getVaultIds();

  /// Replace the ordered vault id list.
  Future<void> setVaultIds(List<String> ids);

  // ── Vault CRUD ──────────────────────────────────────────────────────

  /// Load a vault by id, or `null` if absent.
  Future<Vault?> getVault(String id);

  /// Upsert a vault, ensuring its id is present in the index.
  Future<void> saveVault(Vault vault);

  /// Delete a vault and drop its id from the index.
  Future<void> deleteVault(String id);

  /// All vaults, optionally filtered by [depth], in index order.
  Future<List<Vault>> listVaults({int? depth});

  /// Delete every vault whose tier equals [depth] (does not touch other
  /// tiers — callers cascade explicitly when a tier is removed for good).
  Future<void> deleteVaultsAtDepth(int depth);

  /// Generate a fresh, opaque vault id (never a sequential number).
  String newVaultId();

  // ── Credentials (one per tier) ──────────────────────────────────────

  /// Load the credential for [depth], or `null` if not configured.
  ///
  /// The stored value is a **verifier ciphertext**, not a PIN hash — see
  /// [WalletCredential].
  Future<WalletCredential?> getCredential(int depth);

  /// Store (upsert) a credential — its own [WalletCredential.depth] decides
  /// which tier it belongs to.
  Future<void> setCredential(WalletCredential credential);

  /// Remove the credential for [depth].
  Future<void> deleteCredential(int depth);

  /// Depths that currently have a credential, ascending.
  Future<List<int>> listCredentialDepths();

  // ── Stand-in mode (ADR-009) ─────────────────────────────────────────

  /// Behaviour of the stand-in configured **by tier [depth]** for its child
  /// (`depth + 1`): `hide` (default) or `wipe`.
  ///
  /// Stored per tier so nested stand-ins never clobber each other — a
  /// `wipe` configured at depth 2 must not be read when the depth-1 PIN
  /// unlocks (which would erase the depth-0 real wallet).
  Future<StandInMode> getStandInMode(int depth);

  /// Persist the stand-in mode configured by tier [depth] for its child.
  Future<void> setStandInMode(int depth, StandInMode mode);

  // ── PIN attempt counter (global) ────────────────────────────────────

  /// Failed-attempt count shared by every tier.
  Future<int> getPinAttempts();

  /// Persist the failed-attempt count.
  Future<void> setPinAttempts(int attempts);

  // ── Existence / migration ───────────────────────────────────────────

  /// Whether a wallet exists (a credential at any tier).
  Future<bool> hasWallet();

  // ── Clearing ────────────────────────────────────────────────────────

  /// Delete **everything**: all vaults at every tier, all credentials, mode,
  /// attempts, and any legacy keys.
  Future<void> clearAll();
}
