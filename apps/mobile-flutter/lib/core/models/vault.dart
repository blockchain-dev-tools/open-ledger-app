/// Vault model — a self-contained wallet (one mnemonic + its derived accounts).
///
/// See ADR-010 (multi-vault): a device may hold several vaults. Vaults are
/// grouped by *depth* (tier):
/// - **depth 0** — the primary tier, unlocked by the primary PIN and freely
///   switchable in-session;
/// - **depth ≥ 1** — a stand-in tier (ADR-009), unlocked by its own PIN. Each
///   session may itself configure a stand-in one level deeper, so stand-ins
///   nest (`depth 0 ← 1 ← 2`).
///
/// All vaults of one depth share a single PIN (2A): unlocking that PIN loads
/// the whole tier at once.
library;

import 'wallet_accounts.dart';

/// Highest supported tier. `maxDepth = 2` → depths 0/1/2 (at most 3 PINs).
const int maxDepth = 2;

/// Maximum number of vaults in the **primary** tier (depth 0). Stand-in tiers
/// are unconstrained. Lives here (next to [maxDepth]) so both the business
/// layer and the UI read one value instead of the UI hardcoding its own copy.
const int maxNormalVaults = 2;

/// Fixed, non-secret plaintext sealed into every tier verifier.
///
/// Its only job is to be recognisable after a successful AEAD open: decryption
/// of the stored verifier *is* the PIN check. Versioned so the scheme can be
/// rotated later.
const String tierVerifyPlaintext = 'openledger-verify-v1';

/// HKDF-Expand label that separates the verifier key from the vault key, so one
/// PBKDF2 master key never encrypts two kinds of payload under the same bytes.
const String tierVerifyContext = 'openledger.verify.v1';

// ── KDF versions (ADR-007) ─────────────────────────────────────────────
//
// Keep in sync with `open-ledger-crypto::kdf` (`CURRENT_KDF_VERSION` is
// asserted against `KDF_VERSION_ARGON2ID_V1` there).

/// Legacy: PBKDF2-HMAC-SHA256, 100k rounds. Unlock only — never written anew.
const int kdfVersionPbkdf2Legacy = 0;

/// Current: Argon2id, memory-hard (64 MiB / 3 passes / 4 lanes).
const int kdfVersionArgon2id = 1;

/// Version every new credential is written with.
const int currentKdfVersion = kdfVersionArgon2id;

/// Stand-in behaviour (ADR-009): `hide` only switches the visible wallet,
/// `wipe` also erases the tier the stand-in replaced (`depth - 1`) before
/// loading this one.
enum StandInMode { hide, wipe }

/// How a vault's mnemonic came to exist (ADR-011 §4).
///
/// The backup-verification paths (§5) branch on this: an Enigma vault is
/// verified against its *riddle + secret* (re-derived with the persisted
/// [Vault.enigmaLanguage]); every other vault against its mnemonic.
enum VaultSource {
  /// Generated in-app (BIP-39 entropy / Enigma-independent generate flow).
  generated,

  /// Typed or pasted in by the user (the default — also the legacy value).
  imported,

  /// Derived via the Enigma protocol (riddle + secret → 24 English words).
  enigma;

  /// Stable wire token persisted in `wallet.vault.<id>`.
  String get wire => name;

  /// Parse a persisted token; anything unknown (incl. legacy `null`) is
  /// treated as [imported] so pre-ADR-011 JSON needs no migration.
  static VaultSource fromWire(String? v) => switch (v) {
        'generated' => VaultSource.generated,
        'enigma' => VaultSource.enigma,
        _ => VaultSource.imported,
      };
}

/// A self-contained wallet: one mnemonic plus the accounts derived from it.
class Vault {
  /// Opaque, randomly generated id (never a sequential number).
  final String id;

  /// User-facing name. Empty means "unnamed" — the UI renders a localized
  /// default, so no display string is ever persisted here.
  final String label;

  /// Tier this vault belongs to (0 = primary, ≥ 1 = stand-in).
  final int depth;

  /// Mnemonic ciphertext (PIN-derived ChaCha20-Poly1305).
  final String mnemonicEncrypted;

  /// Optional BIP-39 passphrase ciphertext. `null` when none is stored.
  final String? passphraseEncrypted;

  /// Derived accounts + mnemonic fingerprint for this vault.
  final WalletAccounts accounts;

  /// Creation time (epoch ms).
  final int createdAt;

  /// How this vault's mnemonic originated (ADR-011 §4).
  final VaultSource source;

  /// BIP-39 wordlist index used for the Enigma riddle→index lookup (ADR-011
  /// §4). Only meaningful when [source] is [VaultSource.enigma]; the output
  /// mnemonic is always 24 English words, so this cannot be recovered from
  /// the stored phrase — it must be persisted to re-derive on verify.
  final int enigmaLanguage;

  const Vault({
    required this.id,
    required this.label,
    required this.depth,
    required this.mnemonicEncrypted,
    this.passphraseEncrypted,
    required this.accounts,
    required this.createdAt,
    this.source = VaultSource.imported,
    this.enigmaLanguage = 0,
  });

  /// Whether this vault lives in a stand-in tier (`depth > 0`).
  bool get isHidden => depth > 0;

  factory Vault.fromJson(Map<String, dynamic> json) {
    return Vault(
      id: json['id'] as String,
      label: (json['label'] as String?) ?? '',
      // Legacy JSON has no `depth` → treat it as the primary tier.
      depth: (json['depth'] as num?)?.toInt() ?? 0,
      mnemonicEncrypted: json['mnemonicEncrypted'] as String,
      passphraseEncrypted: json['passphraseEncrypted'] as String?,
      accounts:
          WalletAccounts.fromJson(json['accounts'] as Map<String, dynamic>),
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      source: VaultSource.fromWire(json['source'] as String?),
      enigmaLanguage: (json['enigmaLanguage'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'depth': depth,
      'mnemonicEncrypted': mnemonicEncrypted,
      if (passphraseEncrypted != null)
        'passphraseEncrypted': passphraseEncrypted,
      'accounts': accounts.toJson(),
      'createdAt': createdAt,
      'source': source.wire,
      'enigmaLanguage': enigmaLanguage,
    };
  }

  Vault copyWith({
    String? label,
    int? depth,
    String? mnemonicEncrypted,
    String? passphraseEncrypted,
    WalletAccounts? accounts,
    VaultSource? source,
    int? enigmaLanguage,
  }) {
    return Vault(
      id: id,
      label: label ?? this.label,
      depth: depth ?? this.depth,
      mnemonicEncrypted: mnemonicEncrypted ?? this.mnemonicEncrypted,
      passphraseEncrypted: passphraseEncrypted ?? this.passphraseEncrypted,
      accounts: accounts ?? this.accounts,
      createdAt: createdAt,
      source: source ?? this.source,
      enigmaLanguage: enigmaLanguage ?? this.enigmaLanguage,
    );
  }

  @override
  String toString() => 'Vault(id: $id, label: "$label", depth: $depth)';
}

/// Proof that a tier's PIN is correct — scoped to one tier [depth].
///
/// It is a **ciphertext**: AEAD over [tierVerifyPlaintext] under a key derived
/// from that tier's PIN (ADR-009 §3 revision). Unlocking tries to open it, and
/// a successful open means "this PIN belongs to this tier" — so the PIN check
/// and the decryption key share a derivation without ever storing anything
/// equal to the vault key.
class WalletCredential {
  /// Tier this credential unlocks.
  final int depth;

  /// AEAD ciphertext (`nonce(12B) ‖ ciphertext+tag`) of the fixed verifier
  /// plaintext ([tierVerifyPlaintext]).
  final String verifier;

  /// KDF version that produced the key this [verifier] is sealed under
  /// (ADR-007). Stored **with** the verifier rather than in a separate key:
  /// the two must never disagree, and one write keeps them atomic. Absent in
  /// pre-upgrade JSON → [kdfVersionPbkdf2Legacy].
  final int kdfVersion;

  const WalletCredential({
    required this.depth,
    required this.verifier,
    this.kdfVersion = kdfVersionPbkdf2Legacy,
  });

  factory WalletCredential.fromJson(Map<String, dynamic> json) {
    return WalletCredential(
      depth: (json['depth'] as num?)?.toInt() ?? 0,
      verifier: json['verifier'] as String,
      kdfVersion:
          (json['kdfVersion'] as num?)?.toInt() ?? kdfVersionPbkdf2Legacy,
    );
  }

  Map<String, dynamic> toJson() => {
        'depth': depth,
        'verifier': verifier,
        'kdfVersion': kdfVersion,
      };
}
