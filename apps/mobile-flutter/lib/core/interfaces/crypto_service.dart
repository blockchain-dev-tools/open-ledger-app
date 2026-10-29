import 'dart:typed_data';

/// Abstract interface for all cryptographic operations.
///
/// Implemented by [CryptoBridge] (`lib/infrastructure/ffi/crypto_bridge.dart`)
/// which delegates to the Rust `open_ledger_crypto` crate via `dart:ffi`.
///
/// Services depend on this interface, never on the concrete FFI implementation.
/// This enables unit testing with mock crypto providers (no Rust .so required).
abstract class ICryptoService {
  // ── BIP-39 Mnemonic ─────────────────────────────────────────────────

  /// Generate a BIP-39 mnemonic phrase.
  /// [strength] must be 128 (12 words) or 256 (24 words).
  String generateMnemonic({int strength = 128});

  /// Validate a BIP-39 mnemonic phrase.
  bool validateMnemonic(String mnemonic);

  /// Re-encode a mnemonic (normalize, validate, canonical form).
  String reencodeMnemonic(String mnemonic);

  /// Generate a BIP-39 mnemonic with a specific language.
  String? generateMnemonicLang({int strength = 128, required int language});

  /// Validate a BIP-39 mnemonic against a specific language.
  bool validateMnemonicLang(String mnemonic, int language);

  // ── HD Key Derivation ───────────────────────────────────────────────

  /// Derive a secp256k1 (Ethereum/Bitcoin) private key from seed.
  Uint8List? deriveSecp256k1PrivateKey(String seedHex, String path);

  /// Derive a secp256k1 extended key: private key ‖ BIP-32 chain code.
  ///
  /// Returns 64 bytes (`privKey[32] || chainCode[32]`), or null on failure.
  /// The chain code is a BIP-32 CKDpriv output that a Ledger host asks for
  /// explicitly (`GET_PUBLIC_KEY`, `P2 = 0x01`) to rebuild an xpub; it cannot
  /// be recomputed from the private key alone.
  Uint8List? deriveSecp256k1Extended(String seedHex, String path);

  /// Derive an Ed25519 (Solana/Sui) private key from seed.
  Uint8List? deriveEd25519PrivateKey(String seedHex, String path);

  // ── Signing ─────────────────────────────────────────────────────────

  /// Sign an Ethereum transaction (raw RLP).
  Uint8List? signEthTransaction(String privkeyHex, String rlpHex);

  /// Sign an Ethereum personal message (EIP-191).
  Uint8List? signEthPersonalMessage(String privkeyHex, String messageHex);

  /// Sign Ethereum EIP-712 typed structured data.
  Uint8List? signEthEIP712(
      String privkeyHex, String domainHashHex, String structHashHex);

  /// Sign a Solana message (Ed25519).
  Uint8List? signSolanaMessage(String privkeyHex, String messageHex);

  // ── Address from Private Key ────────────────────────────────────────

  /// Derive EIP-55 checksummed Ethereum address from private key.
  String? ethAddressFromPrivateKey(String privkeyHex);

  /// Get uncompressed secp256k1 public key (65 bytes).
  Uint8List? ethPublicKeyBytes(String privkeyHex);

  /// Extract Ed25519 public key bytes from Solana private key.
  Uint8List? solanaPublicKeyBytes(String privkeyHex);

  /// The chain's **real** public key bytes (ADR-011 §4).
  ///
  /// Replaces the historical bug where `ChainAccount.publicKey` held the
  /// *private* key hex: Ethereum/Tron → uncompressed 65B, Bitcoin → compressed
  /// 33B, Solana/Sui → Ed25519 32B. `chain` is one of the five chain ids.
  Uint8List? publicKeyForChain(String chain, String privkeyHex);

  /// Encode a private key in the chain's **importable** form (ADR-011 §3).
  ///
  /// ETH → `0x`+hex, BTC → WIF (compressed, mainnet), SOL → base58(64B
  /// keypair), Tron → bare hex, Sui → bech32 `suiprivkey1…`. A raw hex dump is
  /// not importable by most wallets, which is the whole point of exporting.
  String? encodePrivateKey(String chain, String privkeyHex);

  // ── Address from Seed + Path ────────────────────────────────────────

  /// Derive an Ethereum address from BIP-39 seed + BIP-32 path.
  String? deriveEthAddress(String seedHex, String path);

  /// Derive a Solana address from BIP-39 seed + SLIP-10 path.
  String? deriveSolAddress(String seedHex, String path);

  /// Derive a Bitcoin P2WPKH address (bech32) from seed + BIP-84 path.
  String? deriveBtcAddress(String seedHex, String path);

  /// Derive a Tron address (base58check) from seed + BIP-44 path.
  String? deriveTronAddress(String seedHex, String path);

  /// Derive a Sui address from seed + SLIP-10 path.
  String? deriveSuiAddress(String seedHex, String path);

  /// Derive a NEAR implicit-account id (hex ed25519 public key).
  String? deriveNearAddress(String seedHex, String path);

  /// Derive a TON Wallet v4r2 address (base64url, bounceable).
  String? deriveTonAddress(String seedHex, String path);

  // ── Address from Public Key ─────────────────────────────────────────

  /// Derive a Bitcoin P2WPKH bech32 address from compressed public key.
  String? p2wpkhAddress(String compressedPubkeyHex);

  /// Derive a Tron base58check address from uncompressed public key.
  String? tronAddressFromPubkey(String uncompressedPubkeyHex);

  /// Derive a Sui address from an Ed25519 public key.
  String? suiAddress(String ed25519PubkeyHex);

  // ── Enigma ─────────────────────────────────────────────────────────

  /// Generate a deterministic 24-word Enigma mnemonic from riddle + secret.
  ///
  /// [language] is the [Bip39Language] code (0–9). Uses that language for
  /// riddle tokenization and output wordlist. Returns null on error.
  String? enigmaDeriveMnemonic(String riddle, String secret, int language);

  /// Get the raw entropy hex for an Enigma mnemonic (before BIP-39 encoding).
  String? enigmaEntropyHex(String riddle, String secret, int language);

  /// Convert raw entropy hex to a BIP-39 mnemonic with the given language.
  String? mnemonicFromEntropy(String entropyHex, int language);

  // ── APDU Sign Data Parser ───────────────────────────────────────────

  /// Parse APDU signing payload into a JSON display structure.
  ///
  /// [chain] is one of: ethereum, personal_msg, eip712, solana, bitcoin, tron, sui.
  /// [payloadHex] is the hex-encoded payload (RLP/message) after the derivation path.
  /// Returns a JSON string on success, null on parse failure.
  String? parseSignData(String chain, String payloadHex);

  // ── PIN auth + Mnemonic Encryption ─────────────────────────────────

  /// Derive a key from PIN + salt using PBKDF2-HMAC-SHA256 (100k iterations).
  String? pbkdf2Derive(String pin, String saltHex, int keyLen);

  /// Derive a 64-byte BIP-39 seed from mnemonic + optional passphrase.
  String? mnemonicToSeed(String mnemonic, {String passphrase = ''});

  /// Encrypt plaintext using ChaCha20-Poly1305 with a PIN-derived key.
  String? chacha20Encrypt(String plaintext, String pin, String saltHex);

  /// Decrypt hex-encoded ciphertext (12B nonce || ciphertext+tag).
  String? chacha20Decrypt(String ciphertextHex, String pin, String saltHex);

  // ── Key hierarchy (tier verifier) ───────────────────────────────────

  /// HKDF-Expand (RFC 5869 §2.3) of the master key [prkHex] under the
  /// domain-separation label [info] → 32 bytes as hex.
  ///
  /// Lets one PBKDF2 master key serve several contexts (tier verifier vs vault
  /// payload) without ever using the same key bytes for two kinds of data.
  /// Cost is one HMAC — negligible next to PBKDF2.
  String? hkdfExpand32(String prkHex, String info);

  /// AEAD-encrypt [plaintext] under the raw 32-byte key [keyHex].
  ///
  /// Returns hex of `nonce(12B) ‖ ciphertext+tag`. Unlike [chacha20Encrypt]
  /// this does **not** derive the key from a PIN, so a caller that already
  /// holds a derived key never pays for a second PBKDF2.
  String? aeadEncryptWithKey(String plaintext, String keyHex);

  /// AEAD-decrypt [ciphertextHex] under [keyHex].
  ///
  /// Returns `null` when the key is wrong or the payload is corrupt — never a
  /// partial plaintext — so callers can treat `null` as "did not match".
  String? aeadDecryptWithKey(String ciphertextHex, String keyHex);

  /// Compare two strings in constant time (no early exit on first mismatch).
  ///
  /// Used to compare PIN hashes without leaking, via timing, the position of
  /// the first differing byte. Implemented in the Rust SDK.
  bool constantTimeEquals(String a, String b);

  /// Encrypt plaintext with a key derived from the BIP-39 [seedHex]
  /// (PBKDF2 domain-separated → ChaCha20-Poly1305).
  ///
  /// Used to persist the signing history at rest without involving the PIN.
  /// Returns hex-encoded ciphertext, or null on failure.
  String? historyEncrypt(String plaintext, String seedHex);

  /// Decrypt history ciphertext produced by [historyEncrypt].
  /// Returns the plaintext, or null on failure (wrong seed / corruption).
  String? historyDecrypt(String cipherHex, String seedHex);

  // ── Hex Utilities ──────────────────────────────────────────────────

  /// Encode bytes to lowercase hex string.
  String hexEncode(Uint8List bytes);

  /// Decode hex string to bytes.
  Uint8List hexToBytes(String hex);
}
