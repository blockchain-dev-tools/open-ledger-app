import '../../core/interfaces/storage.dart';

/// In-memory [Storage] implementation for unit and widget tests.
///
/// Uses a [Map<String, String>] internally. Not suitable for production
/// — data is lost when the process exits.
class InMemoryStorage implements Storage {
  final Map<String, String> _store = {};

  @override
  Future<String?> getItem(String key) async {
    return _store[key];
  }

  @override
  Future<void> setItem(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<void> removeItem(String key) async {
    _store.remove(key);
  }

  /// Remove **all** keys from storage. Useful for test teardown.
  void clear() {
    _store.clear();
  }
}
