import '../models/wallet_accounts.dart';

/// Read-only view over the active vault's exportable secrets (ADR-011).
///
/// Screens depend on this interface, never on the concrete [ExportService],
/// so widget tests can render the export flow without storage, crypto, or
/// the Rust FFI.
///
/// Scope is deliberately narrow — this is the **display** half of ADR-011,
/// not a second wallet API:
/// - it never stores anything, never touches BLE, clipboard or files
///   (the QR is the only exit);
/// - it reads the *active* vault only, so a stand-in session can never
///   export the tier above it (ADR-009 I14).
abstract class IExportService {
  /// Whether the active vault carries a BIP-39 passphrase.
  ///
  /// The passphrase itself is never exported; this drives the "not in this
  /// QR" note so the gap is visible before a restore, not discovered after.
  bool get hasPassphrase;

  /// The active vault's mnemonic fingerprint (the identity chip), or `null`
  /// while locked.
  String? get fingerprint;

  /// The active vault's accounts; empty while locked.
  List<ChainAccount> get accounts;

  /// Re-verify the **session** PIN before a secret is shown (contract I6).
  ///
  /// Session-scoped on purpose: another tier's valid PIN must be rejected,
  /// so a stand-in session cannot reveal the primary vault's secrets.
  Future<bool> verifySessionPin(String pin);

  /// Reveal the active vault's mnemonic for display (PIN-gated).
  ///
  /// Returns `null` when [pin] does not match the session tier.
  Future<String?> revealMnemonic(String pin);

  /// [account]'s private key in its chain-specific **importable** encoding
  /// (ETH `0x` hex, BTC WIF, SOL base58, Sui `suiprivkey1…`), or `null` when
  /// the wallet is locked or the key cannot be derived.
  String? encodePrivateKey(ChainAccount account);

  /// Human-readable name of [account]'s encoding (e.g. `WIF (mainnet)`).
  ///
  /// Technical data, not localizable UI copy.
  String? encodingLabel(ChainAccount account);
}
