import 'package:shared_preferences/shared_preferences.dart';

import '../../core/interfaces/storage.dart';

/// [Storage] backed by [SharedPreferences] for persistent key-value storage.
///
/// Uses `shared_preferences` (already a project dependency) for persistence.
/// Data survives app restarts. Suitable for prototype phase.
///
/// In production, this should be replaced with [FlutterSecureStorage]
/// for encrypted on-device persistence (once `flutter_secure_storage`
/// is added as a dependency).
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
