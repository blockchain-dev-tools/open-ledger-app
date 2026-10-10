import 'dart:typed_data';

import '../core/interfaces/crypto_service.dart';
import '../core/interfaces/export_service.dart';
import '../core/interfaces/wallet_service.dart';
import '../core/models/wallet_accounts.dart';

/// Derives the payloads the export screens display (ADR-011).
///
/// Thin composition over [IWalletService] (active vault, session PIN, seed)
/// and [ICryptoService] (raw key derivation + chain-specific encoding). It
/// holds no state of its own: every call reads the *current* session, so a
/// vault switch or a lock is reflected immediately.
///
/// Encoding rules live in Rust (`crates/open-ledger-biz/src/export.rs`); this
/// class only picks the derivation path and forwards the bytes.
class ExportService implements IExportService {
  final IWalletService _wallet;
  final ICryptoService _crypto;

  ExportService({required this._wallet, required this._crypto});

  /// Importable-encoding names, keyed by chain id. Data, never localized.
  static const Map<String, String> _encodingLabels = {
    'ethereum': '0x + 32B hex',
    'bitcoin': 'WIF (mainnet, compressed)',
    'solana': 'base58 (64B keypair)',
    'tron': '32B hex',
    'sui': 'bech32 suiprivkey',
  };

  @override
  bool get hasPassphrase => _wallet.activeVault?.passphraseEncrypted != null;

  @override
  String? get fingerprint => _wallet.getAccounts()?.mnemonicFingerprint;

  @override
  List<ChainAccount> get accounts =>
      _wallet.getAccounts()?.accounts ?? const [];

  @override
  Future<bool> verifySessionPin(String pin) => _wallet.verifySessionPin(pin);

  @override
  Future<String?> revealMnemonic(String pin) => _wallet.revealMnemonic(pin);

  @override
  String? encodePrivateKey(ChainAccount account) {
    final hex = _privateKeyHex(account);
    if (hex == null) return null;
    return _crypto.encodePrivateKey(account.chain, hex);
  }

  @override
  String? encodingLabel(ChainAccount account) => _encodingLabels[account.chain];

  /// Derive the account's raw private key at its path, hex-encoded.
  ///
  /// Mirror of `AccountService`'s chain → curve mapping: Ed25519 for
  /// Solana / Sui (SLIP-10), secp256k1 for Ethereum / Bitcoin / Tron.
  String? _privateKeyHex(ChainAccount account) {
    final seedHex = _wallet.seedHex;
    if (seedHex == null || seedHex.isEmpty) return null;

    final Uint8List? key = switch (account.chain) {
      'solana' || 'sui' =>
        _crypto.deriveEd25519PrivateKey(seedHex, account.derivationPath),
      'ethereum' || 'bitcoin' || 'tron' =>
        _crypto.deriveSecp256k1PrivateKey(seedHex, account.derivationPath),
      _ => null,
    };
    return key == null ? null : _crypto.hexEncode(key);
  }
}
