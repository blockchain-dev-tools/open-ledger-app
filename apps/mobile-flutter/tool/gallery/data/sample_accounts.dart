library;

import 'package:open_ledger_app/core/models/wallet_accounts.dart';


/// Fixed script data for full-screen gallery mocks (ADR-005).
///
/// Deterministic on purpose: visual review and golden comparison must see the
/// same addresses on every run. Values are well-known example addresses /
/// fixed fake public keys — never real account material.

// secp256k1: 04 + X(32B) + Y(32B) = 65 bytes = 130 hex chars.
const String _secpPubKey =
    '04a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f'
    '90a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f'
    '0a';

// Ed25519: 32 bytes = 64 hex chars.
const String _ed25519PubKey =
    'e7f1a3b5c9d20486f0a2c4e68b1d3f57902468ace13579bdf02468ace13579bd';

const ChainAccount ethAccount = ChainAccount(
  address: '0x71C7656EC7ab88b098defB751B7401B5f6d8976F',
  derivationPath: "m/44'/60'/0'/0/0",
  publicKey: _secpPubKey,
  chain: 'ethereum',
);

const ChainAccount solAccount = ChainAccount(
  // Example token-mint address from the official Solana docs.
  address: '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM',
  derivationPath: "m/44'/501'/0'/0'",
  publicKey: _ed25519PubKey,
  chain: 'solana',
);

const ChainAccount btcAccount = ChainAccount(
  // BIP-173 test-vector address (documented invalid-key example).
  address: 'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh',
  derivationPath: "m/84'/0'/0'/0/0",
  publicKey: _secpPubKey,
  chain: 'bitcoin',
);

const ChainAccount tronAccount = ChainAccount(
  address: 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8',
  derivationPath: "m/44'/195'/0'/0/0",
  publicKey: _secpPubKey,
  chain: 'tron',
);

const ChainAccount suiAccount = ChainAccount(
  address:
      '0x85e9b14a02f8f4f0e9c5d4a3b2c109876543210fedcba9876543210abcdef01',
  derivationPath: "m/44'/784'/0'/0'/0'",
  publicKey: _ed25519PubKey,
  chain: 'sui',
);

// Second accounts — give a couple of chain sections more than one row so the
// Accounts tab preview shows its real list/count behaviour.
const ChainAccount ethAccount2 = ChainAccount(
  address: '0x5A0b54D5dc17e0AadC383d2db43B0a0D3E029c4c',
  derivationPath: "m/44'/60'/0'/0/1",
  publicKey: _secpPubKey,
  chain: 'ethereum',
);

const ChainAccount btcAccount2 = ChainAccount(
  // BIP-173 example address shape (fake key material).
  address: 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq',
  derivationPath: "m/84'/0'/0'/0/1",
  publicKey: _secpPubKey,
  chain: 'bitcoin',
);

/// Full wallet snapshot for the Main screen preview (Accounts tab).
final WalletAccounts sampleWalletAccounts = WalletAccounts(
  mnemonicFingerprint: 'c0ffee12',
  accounts: [
    ethAccount,
    ethAccount2,
    solAccount,
    btcAccount,
    btcAccount2,
    tronAccount,
    suiAccount,
  ],
);

/// Lookup keyed by the `chain` query parameter used by screen scenarios.
const Map<String, ChainAccount> sampleAccounts = {
  'eth': ethAccount,
  'sol': solAccount,
  'btc': btcAccount,
  'tron': tronAccount,
  'sui': suiAccount,
};
