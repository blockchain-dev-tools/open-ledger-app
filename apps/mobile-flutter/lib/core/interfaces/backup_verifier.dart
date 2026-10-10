/// Backup verification (ADR-011 §5).
///
/// The user retypes a secret from memory; the app **recomputes** the vault's
/// derived output and compares. The comparison is against a *derived result*
/// (an address), never a mnemonic fingerprint — a fingerprint is insensitive
/// to the passphrase and to the Enigma language, so it would pass forever
/// (ADR-011 §维度 E).
library;

/// Outcome of a single verification attempt.
enum VerifyResult {
  /// The retyped secret reproduces the vault's derived output.
  match,

  /// It does not — the user misremembered (or the vault has no such secret).
  mismatch,

  /// Cannot be checked: the session is locked, the vault lacks an Ethereum
  /// baseline account, or crypto returned null. Never surfaced as "wrong".
  unavailable,
}

/// Verifies retyped secrets against the **active** vault (ADR-011 §5).
///
/// Screens depend on this interface, never on the concrete verifier, so the
/// three paths can be widget-tested without storage, crypto, or FFI.
abstract class IBackupVerifier {
  /// Whether the active vault was created via the Enigma protocol.
  ///
  /// Only such vaults offer the riddle + secret verification path.
  bool get isEnigma;

  /// Whether the active vault carries a stored BIP-39 passphrase.
  bool get hasPassphrase;

  /// Verify a retyped mnemonic against the vault's ETH address.
  Future<VerifyResult> verifyMnemonic(String mnemonic);

  /// Verify a retyped BIP-39 passphrase against the vault's ETH address.
  Future<VerifyResult> verifyPassphrase(String passphrase);

  /// Verify a retyped riddle + secret against the vault's stored mnemonic.
  Future<VerifyResult> verifyEnigma(String riddle, String secret);
}
