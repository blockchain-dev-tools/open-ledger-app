import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/interfaces/storage.dart';

/// [Storage] backed by OS-protected storage — Android Keystore-wrapped
/// encryption, iOS/macOS Keychain (ADR-007).
///
/// This is the production implementation: the key that unwraps the data never
/// leaves the platform keystore, so a copy of the app's data directory cannot be
/// decrypted off-device. That is what closes the "extract the files, then guess
/// the 6-digit PIN offline" vector — the KDF version bump only raises the cost
/// of a single guess.
///
/// [SharedPreferencesStorage] is kept for tests and as the migration source.
class SecureStorage implements Storage {
  /// Android keeps the wrapping key in the Keystore; `migrateWithBackup` makes
  /// the plugin's own cipher migration crash-safe (it is a no-op until a future
  /// algorithm change). Legacy `encryptedSharedPreferences` data is migrated
  /// automatically by the plugin.
  static final FlutterSecureStorage _defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(migrateWithBackup: true),
  );

  final FlutterSecureStorage _storage;

  SecureStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? _defaultStorage;

  @override
  Future<String?> getItem(String key) => _storage.read(key: key);

  @override
  Future<void> setItem(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> removeItem(String key) => _storage.delete(key: key);

  /// Every entry written by this app. The device E2E harness uses it to
  /// snapshot and restore a real wallet; product code reads keys by name.
  Future<Map<String, String>> readAll() => _storage.readAll();

  /// Removes every entry — same reason as [readAll].
  Future<void> deleteAll() => _storage.deleteAll();
}

/// One-time move of the `wallet.*` keys from plaintext `SharedPreferences`
/// into [SecureStorage] (ADR-007).
///
/// Copy-then-delete, in that order: an interrupted run leaves the legacy copy
/// intact and the next launch repeats it (the copy is idempotent). A key is
/// only deleted after its value was written to secure storage.
///
/// No marker key is needed — once the legacy keys are gone the scan finds
/// nothing, so the migration is its own flag.
class LegacyWalletMigration {
  /// Every wallet key shares this prefix; `SettingsRepositoryImpl` uses
  /// `settings.*` and is deliberately out of scope (see the storage reference).
  static const String _walletPrefix = 'wallet.';

  final Storage _target;

  LegacyWalletMigration(this._target);

  /// Returns the number of keys moved (0 on an already-migrated device).
  Future<int> run() async {
    final prefs = await SharedPreferences.getInstance();
    final legacyKeys = prefs
        .getKeys()
        .where((key) => key.startsWith(_walletPrefix))
        .toList();
    if (legacyKeys.isEmpty) return 0;

    final copied = <String>[];
    for (final key in legacyKeys) {
      final value = prefs.getString(key);
      // A non-string legacy value cannot hold wallet data; skipping it keeps
      // the delete step below from destroying something we did not move.
      if (value == null) continue;
      await _target.setItem(key, value);
      copied.add(key);
    }

    for (final key in copied) {
      await prefs.remove(key);
    }
    return copied.length;
  }
}
