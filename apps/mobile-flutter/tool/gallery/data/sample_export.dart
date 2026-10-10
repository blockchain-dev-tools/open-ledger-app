/// Fixed script data for the seed / private-key export screens (ADR-005).
///
/// Deterministic on purpose so visual review sees the same QR on every run.
/// The key strings are well-formed but **fake** — never real key material.
library;

/// Fingerprint chip shown on the seed-QR screen. Matches the wallet snapshot
/// in [sampleWalletAccounts] so the two screens read as the same wallet.
const String sampleWalletFingerprint = 'c0ffee12';

/// Chain-specific importable encodings, keyed by chain id.
///
/// A raw 32-byte hex dump is not importable by most wallets (BTC wants WIF,
/// Solana base58, Sui bech32), so the export screens show the encoding each
/// chain actually uses.
const Map<String, String> samplePrivateKeyEncodings = {
  'ethereum':
      '0xa1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
  'bitcoin': 'L1aW4aubDFB7yfras2S1mN3bqg9nwySY8nkoLmJebSLD5BWv3ENZ',
  'solana':
      '4YFq9Yx7kS2m8nP1qR3tU5vW6xY7zA8bC9dE1fG2hJ3kL4mN5pQ6rS7tU8vW9xY1zA2b',
  'tron':
      'b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90a1',
  'sui': 'suiprivkey1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh9d8c7b6a5',
};

/// Human-readable name of the encoding, shown as a metadata row.
const Map<String, String> samplePrivateKeyEncodingLabels = {
  'ethereum': '0x + 32B hex',
  'bitcoin': 'WIF (mainnet, compressed)',
  'solana': 'base58 (64B keypair)',
  'tron': '32B hex',
  'sui': 'bech32 suiprivkey',
};
