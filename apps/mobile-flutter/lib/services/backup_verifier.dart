import '../core/interfaces/backup_verifier.dart';
import '../core/interfaces/crypto_service.dart';
import '../core/interfaces/wallet_service.dart';
import '../core/models/vault.dart';
import '../core/models/wallet_accounts.dart';

/// Verifies retyped secrets against the active vault (ADR-011 §5).
///
/// Thin composition over [IWalletService] (the live session: mnemonic,
/// passphrase, stored `enigmaLanguage`, accounts) and [ICryptoService] (BIP-39
/// seed + ETH address, Enigma re-derivation). It holds no state — every call
/// reads the *current* session, so a vault switch or a lock is reflected at
/// once.
///
/// **Baseline**: the vault's **ETH** account (address + derivation path). The
/// mnemonic and passphrase paths recompute that address and compare; the
/// Enigma path compares the re-derived phrase word-by-word. Any attempt whose
/// baseline or crypto result is missing returns [VerifyResult.unavailable] —
/// the verifier never throws.
class BackupVerifier implements IBackupVerifier {
  final IWalletService _wallet;
  final ICryptoService _crypto;

  BackupVerifier({required this._wallet, required this._crypto});

  @override
  bool get isEnigma => _wallet.activeVault?.source == VaultSource.enigma;

  @override
  bool get hasPassphrase => _wallet.activeVault?.passphraseEncrypted != null;

  /// The comparison baseline: the active vault's Ethereum account, or `null`
  /// while locked or when the vault has no ETH account.
  ChainAccount? get _ethAccount {
    if (_wallet.mnemonic == null) return null;
    final accounts = _wallet.getAccounts()?.accounts;
    if (accounts == null) return null;
    return accounts.where((a) => a.chain == 'ethereum').firstOrNull;
  }

  @override
  Future<VerifyResult> verifyMnemonic(String mnemonic) async {
    try {
      final baseline = _ethAccount;
      if (baseline == null) return VerifyResult.unavailable;

      final normalized = mnemonic.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (normalized.isEmpty || !_crypto.validateMnemonic(normalized)) {
        return VerifyResult.mismatch;
      }
      final seed = _crypto.mnemonicToSeed(
        normalized,
        passphrase: _wallet.passphrase ?? '',
      );
      return _compareAddress(seed, baseline);
    } catch (_) {
      return VerifyResult.unavailable;
    }
  }

  @override
  Future<VerifyResult> verifyPassphrase(String passphrase) async {
    try {
      final baseline = _ethAccount;
      final mnemonic = _wallet.mnemonic;
      if (baseline == null || mnemonic == null) {
        return VerifyResult.unavailable;
      }
      final seed = _crypto.mnemonicToSeed(mnemonic, passphrase: passphrase);
      return _compareAddress(seed, baseline);
    } catch (_) {
      return VerifyResult.unavailable;
    }
  }

  @override
  Future<VerifyResult> verifyEnigma(String riddle, String secret) async {
    try {
      // All three paths share the "locked / no ETH baseline" gate so the UI
      // can render a single unavailable state (ADR-011 §5).
      if (_ethAccount == null) return VerifyResult.unavailable;
      final vault = _wallet.activeVault;
      final mnemonic = _wallet.mnemonic;
      if (vault == null || mnemonic == null) {
        return VerifyResult.unavailable;
      }

      final derived = _crypto.enigmaDeriveMnemonic(
        riddle.trim(),
        secret.trim(),
        vault.enigmaLanguage,
      );
      if (derived == null) return VerifyResult.unavailable;

      return _sameWords(derived, mnemonic)
          ? VerifyResult.match
          : VerifyResult.mismatch;
    } catch (_) {
      return VerifyResult.unavailable;
    }
  }

  /// Recompute [baseline]'s address from [seed] and compare it.
  VerifyResult _compareAddress(String? seed, ChainAccount baseline) {
    if (seed == null) return VerifyResult.unavailable;
    final address = _crypto.deriveEthAddress(seed, baseline.derivationPath);
    if (address == null) return VerifyResult.unavailable;
    return address == baseline.address
        ? VerifyResult.match
        : VerifyResult.mismatch;
  }

  /// Word-by-word comparison of two space-separated phrases.
  static bool _sameWords(String a, String b) {
    final wa = a.trim().split(RegExp(r'\s+'));
    final wb = b.trim().split(RegExp(r'\s+'));
    if (wa.length != wb.length) return false;
    for (var i = 0; i < wa.length; i++) {
      if (wa[i] != wb[i]) return false;
    }
    return true;
  }
}
