# Storage and credential model

This reference describes the current device implementation. Security requirements and known gaps are in the [product contract](../product/contract.md). The production storage implementation is [SecureStorage](../../apps/mobile-flutter/lib/infrastructure/persistence/secure_storage.dart) (OS keystore); [SharedPreferencesStorage](../../apps/mobile-flutter/lib/infrastructure/persistence/shared_prefs_storage.dart) remains only as the one-time migration source and for tests.

## Keys and encrypted values

```text
PIN + random device salt
  → KDF (versioned, see below) → layer master key K
    ├→ ChaCha20-Poly1305 → mnemonic / saved passphrase ciphertext
    └→ HKDF-Expand(K, "openledger.verify.v1") → verifier encryption key
        → AEAD("openledger-verify-v1") → wallet.verifier.<depth>
```

| `kdfVersion` | KDF | Status |
|---|---|---|
| 0 | PBKDF2-HMAC-SHA256, 100,000 rounds | Legacy — unlock only |
| 1 | Argon2id, `m=64 MiB, t=3, p=4` | Current — every new credential |

The version is stored **inside** the credential record (`wallet.verifier.<d>` JSON, field `kdfVersion`) rather than in a separate key: the marker and the verifier it describes must never disagree, and one write keeps them atomic. A tier's version is upgraded in place the first time that tier's PIN unlocks (see "Operations and scopes").

Neither plaintext PIN nor the derived key is stored. Salt is public, 16 random bytes, created once and retained across PIN changes and KDF upgrades. Every new encryption uses a fresh 12-byte nonce, stored with the ciphertext and authentication tag.

Credential matching derives one key **per KDF version present on the device** and tries all slots from 0 through `maxDepth` without short-circuiting. Empty slots use equal-length dummy ciphertext. A fully upgraded device therefore pays exactly one Argon2id run; a partially upgraded one pays one per version. This avoids work scaling with configured layers; host scheduling and implementation details still require timing review.

A six-digit PIN has only one million possibilities, so the five-attempt counter governs online use only. What protects the offline case is the medium: wallet keys live in OS-protected storage (Android Keystore-wrapped AES-GCM, iOS Keychain), so a copy of the app data directory cannot be decrypted off-device. The KDF version raises the cost of a single guess on a device where an attacker can already execute code; it does not close that case.


## Data layout

| Key | Value | Protection |
|---|---|---|
| `wallet.salt` | Random 16-byte salt | Public; inside keystore storage |
| `wallet.verifier.<d>` | `{depth,verifier,kdfVersion}` — verifier ciphertext plus its KDF version | PIN-derived key; marker is public |
| `wallet.vaultIndex` | Ordered flat array of vault IDs | Public metadata |
| `wallet.vault.<id>` | `{depth,label,mnemonicEncrypted,passphraseEncrypted?,accounts,createdAt,source,enigmaLanguage}` | Secrets encrypted; metadata/public accounts readable |
| `wallet.standIn.mode.<d>` | `hide` / `wipe` | Public metadata |
| `wallet.pinAttempts` | Global failed-credential count | Persisted counter |
| `wallet.signHistory` | Map of vault ID to encrypted history | Each vault's seed-derived key |

All of these keys are stored through `SecureStorage`, i.e. the container is OS-protected. The per-value encryption below is a second, independent layer; neither alone is the whole guarantee.

Vault IDs use `v` plus eight random bytes encoded as hex. A vault belongs to exactly one depth; each layer shares a PIN/key. Depth 0 allows at most two vaults; max stand-in depth is 2. Account records are nested within a vault and contain addresses and actual public keys, not private keys.

Account key formats are ETH/Tron uncompressed 65-byte public keys, BTC compressed 33-byte keys and Solana/Sui 32-byte Ed25519 keys. The source records imported/generated/Enigma origin and Enigma language for recovery checks. Display translations of an Enigma mnemonic must not alter its underlying English seed derivation.

A device upgrading from a build that stored wallet keys in plaintext `SharedPreferences` runs `LegacyWalletMigration` once at startup: every `wallet.*` key is copied to secure storage, then deleted from preferences. Copy-then-delete makes an interrupted run safe to repeat; `settings.*` keys are out of scope.

Old single-wallet `wallet.pinKdf`, `wallet.pinSalt`, `wallet.credential.*` and global stand-in mode are not read or migrated. A user with only those old records must recover from backup. Settings keys remain separate: theme, locale, saved-passphrase preference and launcher disguise are outside wallet-reset scope. BLE name edits currently are not persisted.

## Operations and scopes

| Operation | Effect |
|---|---|
| Setup | Create salt if needed, layer-0 verifier, initial vault and public accounts; reset attempt count |
| Unlock | Match one layer PIN, decrypt that layer's vaults, derive/cache active seed and merge stored accounts; upgrade a legacy `kdfVersion` in place; rewrite accounts only if changed |
| Wrong PIN | Increment shared persistent attempts; five failures lock input until destructive reset |
| Lock | Clear in-memory secrets, active accounts, cached credential key and history; ciphertext remains |
| Add/remove account | Rewrite active vault's public account structure |
| Switch vault | Change active seed/APDU context and reload that vault's encrypted history |
| Add vault | Use current layer key; same-layer mnemonic+passphrase duplicates are rejected; no cross-layer duplicate check |
| Remove vault | Require current session PIN; remove index/data/history; do not remove the final vault in a session |
| Change PIN | Verify old PIN, derive new key, re-encrypt affected vault secrets, then replace verifier; retain device salt |
| Configure stand-in | Create child-layer vault before credential, with rollback if credential persistence fails |
| Remove stand-in | Cascade child/deeper vault and credential deletion and remove corresponding history |
| Wipe unlock | Validate the requested layer's vaults first, then destroy immediately shallower layer, reset mode to hide, and enter requested session |
| `clearWallet()` | Service-level session-scope deletion of current and deeper layers; not the UI Reset action |
| `resetAll()` | Delete all wallet layers, salt, verifiers and indexes; reset attempts |
| `AppState.resetWallet()` | Device-wide `resetAll()` plus signing history deletion; used by Settings/Unlock Reset actions |

PIN changes use compensating writes: save new vault ciphertext before replacing the verifier; if verifier replacement fails, restore the earlier ciphertext. This is not a database transaction or a claim of power-loss atomicity. Inspect failure-path tests when changing persistence ordering.

The same compensating pattern covers the KDF upgrade: vault ciphertext is written under the new key first, then the credential is replaced with `kdfVersion` bumped; a failure in either step restores the earlier ciphertext and leaves the tier on its old credential. An upgrade failure never blocks the unlock (the PIN was already proven) — the next unlock retries.

History is capped at 200 records and encrypted per vault using a seed-derived key. Destroyed vaults/layers remove their stored entries; deleting the last history entry removes the history key. A history-write failure must not block signing. Wallet reset does not remove unrelated `settings.*` keys.

## Source references

[PIN logic](../../apps/mobile-flutter/lib/biz/pin_biz.dart), [wallet logic](../../apps/mobile-flutter/lib/biz/wallet_biz.dart), [vault repository](../../apps/mobile-flutter/lib/data/repositories/vault_repository_impl.dart), [history repository](../../apps/mobile-flutter/lib/data/repositories/history_repository_impl.dart), [secure storage](../../apps/mobile-flutter/lib/infrastructure/persistence/secure_storage.dart), [Rust KDF](../../crates/open-ledger-crypto/src/kdf.rs), [Rust primitives](../../crates/open-ledger-crypto/src/pbkdf2_chacha20.rs).
