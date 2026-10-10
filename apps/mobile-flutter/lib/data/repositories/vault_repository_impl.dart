import 'dart:convert';
import 'dart:math';

import '../../core/interfaces/storage.dart';
import '../../core/interfaces/vault_repository.dart';
import '../../core/models/vault.dart';

/// [IVaultRepository] implementation backed by [Storage] (ADR-010 / depth).
///
/// Contains zero business logic: pure read/write of the vault model. Key layout
/// is documented on [IVaultRepository].
///
/// There is **no legacy (single-wallet) migration**: the pre-multi-vault format
/// never shipped, so a stale install is treated as "no wallet" and re-imported
/// from the user's own mnemonic backup.
class VaultRepositoryImpl implements IVaultRepository {
  final Storage _storage;

  VaultRepositoryImpl(this._storage);

  // ── Storage keys ────────────────────────────────────────────────────

  static const _keyDeviceSalt = 'wallet.salt';
  static const _keyVaultIndex = 'wallet.vaultIndex';
  static const _vaultPrefix = 'wallet.vault.';
  static const _credPrefix = 'wallet.verifier.';
  static const _standInModePrefix = 'wallet.standIn.mode.';
  static const _keyPinAttempts = 'wallet.pinAttempts';

  // ── Device salt ─────────────────────────────────────────────────────

  @override
  Future<String?> getDeviceSalt() => _storage.getItem(_keyDeviceSalt);

  @override
  Future<void> setDeviceSalt(String saltHex) =>
      _storage.setItem(_keyDeviceSalt, saltHex);

  // ── Vault index ─────────────────────────────────────────────────────

  @override
  Future<List<String>> getVaultIds() async {
    final raw = await _storage.getItem(_keyVaultIndex);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List<dynamic>).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> setVaultIds(List<String> ids) =>
      _storage.setItem(_keyVaultIndex, jsonEncode(ids));

  // ── Vault CRUD ──────────────────────────────────────────────────────

  @override
  Future<Vault?> getVault(String id) async {
    final raw = await _storage.getItem(_vaultPrefix + id);
    if (raw == null) return null;
    try {
      return Vault.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveVault(Vault vault) async {
    await _storage.setItem(_vaultPrefix + vault.id, jsonEncode(vault.toJson()));
    final ids = await getVaultIds();
    if (!ids.contains(vault.id)) {
      await setVaultIds([...ids, vault.id]);
    }
  }

  @override
  Future<void> deleteVault(String id) async {
    await _storage.removeItem(_vaultPrefix + id);
    final ids = await getVaultIds();
    if (ids.contains(id)) {
      await setVaultIds(ids.where((e) => e != id).toList());
    }
  }

  @override
  Future<List<Vault>> listVaults({int? depth}) async {
    final ids = await getVaultIds();
    final result = <Vault>[];
    for (final id in ids) {
      final vault = await getVault(id);
      if (vault == null) continue;
      if (depth == null || vault.depth == depth) result.add(vault);
    }
    return result;
  }

  @override
  Future<void> deleteVaultsAtDepth(int depth) async {
    final ids = await getVaultIds();
    final remaining = <String>[];
    for (final id in ids) {
      final vault = await getVault(id);
      if (vault != null && vault.depth == depth) {
        await _storage.removeItem(_vaultPrefix + id);
      } else {
        remaining.add(id);
      }
    }
    await setVaultIds(remaining);
  }

  // ── Credentials ─────────────────────────────────────────────────────

  @override
  Future<WalletCredential?> getCredential(int depth) async {
    final raw = await _storage.getItem(_credKey(depth));
    if (raw == null) return null;
    try {
      return WalletCredential.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setCredential(WalletCredential credential) => _storage.setItem(
      _credKey(credential.depth), jsonEncode(credential.toJson()));

  @override
  Future<void> deleteCredential(int depth) =>
      _storage.removeItem(_credKey(depth));

  @override
  Future<List<int>> listCredentialDepths() async {
    final depths = <int>[];
    for (var d = 0; d <= maxDepth; d++) {
      if (await _storage.getItem(_credKey(d)) != null) depths.add(d);
    }
    return depths;
  }

  // ── Stand-in mode ───────────────────────────────────────────────────

  @override
  Future<StandInMode> getStandInMode(int depth) async {
    final raw = await _storage.getItem(_standInModeKey(depth));
    return raw == 'wipe' ? StandInMode.wipe : StandInMode.hide;
  }

  @override
  Future<void> setStandInMode(int depth, StandInMode mode) =>
      _storage.setItem(_standInModeKey(depth), mode.name);

  // ── PIN attempt counter ─────────────────────────────────────────────

  @override
  Future<int> getPinAttempts() async {
    final stored = await _storage.getItem(_keyPinAttempts);
    return stored != null ? int.tryParse(stored) ?? 0 : 0;
  }

  @override
  Future<void> setPinAttempts(int attempts) =>
      _storage.setItem(_keyPinAttempts, attempts.toString());

  // ── Existence ───────────────────────────────────────────────────────

  @override
  Future<bool> hasWallet() async {
    // Any credential (at any tier) counts — a `wipe` stand-in may leave the
    // primary tier erased while a deeper tier survives.
    return (await listCredentialDepths()).isNotEmpty;
  }

  // ── Clearing ────────────────────────────────────────────────────────

  @override
  Future<void> clearAll() async {
    final ids = await getVaultIds();
    for (final id in ids) {
      await _storage.removeItem(_vaultPrefix + id);
    }
    await _storage.removeItem(_keyVaultIndex);
    await _storage.removeItem(_keyDeviceSalt);
    for (var d = 0; d <= maxDepth; d++) {
      await _storage.removeItem(_credKey(d));
      await _storage.removeItem(_standInModeKey(d));
    }
    await _storage.removeItem(_keyPinAttempts);
  }

  // ── Private helpers ─────────────────────────────────────────────────

  String _credKey(int depth) => '$_credPrefix$depth';

  String _standInModeKey(int depth) => '$_standInModePrefix$depth';

  /// Opaque random id — never a sequential number (ADR-010 §1).
  @override
  String newVaultId() {
    final r = Random.secure();
    final bytes = List<int>.generate(8, (_) => r.nextInt(256));
    final hex =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'v$hex';
  }
}
