import 'package:shared_preferences/shared_preferences.dart';

import '../../core/interfaces/storage.dart';

/// [Storage] backed by [SharedPreferences] for persistent key-value storage.
///
/// **No longer the production implementation** — `SecureStorage` replaced it
/// for wallet data (ADR-007). Kept as the source of the one-time migration
/// ([LegacyWalletMigration]) and for tests that need a plain key-value sink.
class SharedPreferencesStorage implements Storage {
  SharedPreferences? _prefs;

  Future<void> _ensureInit() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  @override
  Future<String?> getItem(String key) async {
    await _ensureInit();
    return _prefs!.getString(key);
  }

  @override
  Future<void> setItem(String key, String value) async {
    await _ensureInit();
    await _prefs!.setString(key, value);
  }

  @override
  Future<void> removeItem(String key) async {
    await _ensureInit();
    await _prefs!.remove(key);
  }
}
