import '../models/signature_record.dart';

/// Abstract repository for signing-history persistence.
///
/// Implemented by `HistoryRepositoryImpl` in `lib/data/repositories/`.
/// Encryption is an implementation detail — callers only supply the current
/// wallet [seedHex] used to derive the encryption key.
///
/// History is **per vault**: a device holds several vaults (ADR-010) whose
/// seeds differ, so a single shared record would let one vault overwrite the
/// other's history. Callers scope every read/write by `vaultId`.
abstract class IHistoryRepository {
  /// Load the persisted records of [vaultId]. Returns an empty list when that
  /// vault has none, or when the data cannot be decrypted (wrong seed /
  /// corruption).
  Future<List<SignatureRecord>> load(String vaultId, String seedHex);

  /// Replace the persisted records of [vaultId].
  Future<void> save(
      List<SignatureRecord> records, String vaultId, String seedHex);

  /// Drop the persisted records of [vaultIds], leaving every other vault's
  /// history intact.
  ///
  /// Called when vaults are destroyed for good (a vault removed, a tier
  /// cleared, a `wipe` stand-in unlocking): their ciphertext is unreadable
  /// once the seed is gone, but leaving it in the map would still record how
  /// many wallets the device once held.
  Future<void> removeVaults(Iterable<String> vaultIds);

  /// Remove **all** persisted history, for every vault (device reset).
  Future<void> clear();
}
