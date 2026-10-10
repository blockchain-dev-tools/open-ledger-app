import 'dart:convert';

import '../../core/interfaces/crypto_service.dart';
import '../../core/interfaces/history_repository.dart';
import '../../core/interfaces/storage.dart';
import '../../core/models/signature_record.dart';

/// [IHistoryRepository] backed by [Storage] and [ICryptoService].
///
/// One storage key holds a JSON map of `vaultId → ciphertext`. Each vault's
/// records are encrypted with a key derived from **its own** seed, so neither
/// vault can read (or overwrite) the other's history — the map merely keeps
/// them side by side instead of letting the last sign clobber the first.
/// Signing payloads and signatures therefore never touch disk in the clear.
/// Contains zero business logic.
class HistoryRepositoryImpl implements IHistoryRepository {
  final Storage _storage;
  final ICryptoService _crypto;

  HistoryRepositoryImpl(this._storage, this._crypto);

  static const _keyHistory = 'wallet.signHistory';

  @override
  Future<List<SignatureRecord>> load(String vaultId, String seedHex) async {
    try {
      final cipher = (await _readAll())[vaultId];
      if (cipher == null || cipher.isEmpty) return const [];
      final plaintext = _crypto.historyDecrypt(cipher, seedHex);
      if (plaintext == null) return const [];
      final decoded = jsonDecode(plaintext) as List<dynamic>;
      return decoded
          .map((e) => SignatureRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> save(
      List<SignatureRecord> records, String vaultId, String seedHex) async {
    final plaintext = jsonEncode(records.map((r) => r.toJson()).toList());
    final cipher = _crypto.historyEncrypt(plaintext, seedHex);
    if (cipher == null) return;
    final all = await _readAll();
    all[vaultId] = cipher;
    await _storage.setItem(_keyHistory, jsonEncode(all));
  }

  @override
  Future<void> removeVaults(Iterable<String> vaultIds) async {
    final ids = vaultIds.toSet();
    if (ids.isEmpty) return;
    final all = await _readAll();
    final before = all.length;
    all.removeWhere((vaultId, _) => ids.contains(vaultId));
    if (all.length == before) return;
    // Drop the key entirely once the last vault goes, so a reset device does
    // not keep an empty `{}` behind.
    if (all.isEmpty) {
      await _storage.removeItem(_keyHistory);
      return;
    }
    await _storage.setItem(_keyHistory, jsonEncode(all));
  }

  @override
  Future<void> clear() => _storage.removeItem(_keyHistory);

  /// Read the whole `vaultId → ciphertext` map, tolerating corrupt/legacy
  /// content (a non-map value yields an empty map rather than throwing).
  Future<Map<String, String>> _readAll() async {
    final raw = await _storage.getItem(_keyHistory);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }
}
