/// Abstract storage interface for wallet persistence.
///
/// Implementations:
///   - [SecureStorage] in `lib/infrastructure/persistence/` — production, backed
///     by the OS keystore (ADR-007)
///   - [SharedPreferencesStorage] in `lib/infrastructure/persistence/` — legacy
///     plaintext implementation, kept as the migration source and for tests
///   - [InMemoryStorage] in `lib/infrastructure/persistence/` (for tests)
library;

/// Key-value storage abstraction.
///
/// Every `wallet.*` key must go through the keystore-backed implementation in
/// release builds: the ciphertext is only as strong as the medium holding it.
abstract class Storage {
  /// Retrieve a value by key. Returns `null` if the key does not exist.
  Future<String?> getItem(String key);

  /// Store a string value under the given key.
  Future<void> setItem(String key, String value);

  /// Remove a key and its associated value.
  Future<void> removeItem(String key);
}
