/// Abstract storage interface for wallet persistence.
///
/// Mirrors the simple key-value interface from open-ledger-mono.
///
/// Implementations:
///   - [SharedPreferencesStorage] in `lib/infrastructure/persistence/`
///   - [InMemoryStorage] in `lib/infrastructure/persistence/` (for tests)
library;

/// Key-value storage abstraction.
///
/// Production implementation will use [flutter_secure_storage]
/// for encrypted on-device persistence.
abstract class Storage {
  /// Retrieve a value by key. Returns `null` if the key does not exist.
  Future<String?> getItem(String key);

  /// Store a string value under the given key.
  Future<void> setItem(String key, String value);

  /// Remove a key and its associated value.
  Future<void> removeItem(String key);
}
