# Open Ledger App product contract

This is the public behavior and security contract for the device App. The source of truth for screen inventory is [router.dart](../../apps/mobile-flutter/lib/core/router.dart). Contract requirements express intended guarantees; the [known gaps](#known-gaps-in-this-snapshot) below identify behavior that is not currently delivered. Any change to a requirement must explain the security tradeoff and update relevant tests.

## Product and trust boundary

Open Ledger App is an Android device-side signer with a Ledger Nano X-style BLE/APDU compatibility layer. Flutter owns presentation; Rust owns cryptographic derivation, payload parsing and signing. Supported implementations include ETH, Solana, BTC, Tron and Sui. Host-wallet interoperability is measured separately in the [verification matrix](../testing/ble-wallets.md).

The host wallet and BLE request origin are untrusted. They may submit malformed or adversarial payloads. Parse failures must return error status words; the confirmation screen must display locally parsed data rather than trust descriptions supplied by the host. Signing decisions belong to the device user. Queries can return public address/key/version data without signing approval.

This is not an in-App balance, price or transaction-broadcast service. USB is not implemented. iOS is experimental. QR air-gap codecs exist but have no product screen journey. Protocol emulation does not establish equivalence to dedicated hardware security.

## User journeys

| Journey | Required behavior |
|---|---|
| Create | Welcome → collect 200 touch points → SHA-256/BIP-39 → show 12 words → quiz positions 3, 7, 11 → set and confirm a six-digit PIN → Vault |
| Enigma | Secret Phrase + key + input language → deterministic 24-word English mnemonic → set PIN → Vault |
| Import | Validate imported BIP-39 text with autocomplete → set PIN → Vault |
| Cold start | Existing wallet → PIN gate; success decrypts secrets and derives accounts before Vault |
| Sign | BLE request while unlocked → locally parsed confirmation → approve/reject/60-second timeout → one terminal response → History |
| Backup | Fresh session PIN before secret display; current export flow uses locally displayed seed/private-key QR codes with 60-second hiding |
| Verify backup | Enter mnemonic/passphrase/Enigma recovery input and compare derived addresses; match/mismatch/unavailable result, without secret reveal |
| Change PIN | Verify current session PIN; re-encrypt every affected vault's mnemonic and saved passphrase and replace its verifier without changing the device salt |
| Reset | Explicit reset clears all wallet layers and signing history, then routes to Welcome; recovery requires separately held backup material |
| Launcher disguise | Android standard/calculator activity aliases change launcher presentation without changing wallet data |

BIP-39 passphrase is not encoded into backup QR codes. The UI must communicate its presence. Chain private-key exports use importable encodings: ETH prefixed hex, BTC compressed mainnet WIF, SOL base58 64-byte keypair, Tron 32-byte hex, and Sui bech32 `suiprivkey`.

## Security invariants

- **I1 Signing approval:** every APDU that produces a signature must pass device-side confirmation. Only explicit approval may release signature bytes. Address/public-key/version queries are separate.
- **I2 Terminal decision:** a pending request resolves exactly once: approve `9000`, reject `6985`, timeout `6400`. Guard repeated taps; await BLE response delivery before clearing the pending request.
- **I3 Locked state:** locked APDU context has no seed. Signing must fail with the appropriate security-status response and must never unlock implicitly.
- **I4 Encryption at rest:** mnemonic and saved passphrase use PIN-derived ChaCha20-Poly1305 encryption. Store the verifier ciphertext `AEAD(HKDF(PBKDF2(PIN, device salt), verify label), fixed verifier text)`, not a plaintext PIN, decryption key or PBKDF2 key used as a readable verifier. Never log secrets.
- **I5 Session cleanup:** lock clears cached mnemonic, passphrase, seed, accounts and credential key material.
- **I6 Reauthentication:** every secret display requires fresh verification of the current session layer's PIN. Prior unlocked state is insufficient.
- **I7 Attempt budget:** five consecutive failed credential attempts cause persisted lockout. All layers share the failure budget. Successful verification resets it; lockout has no timed recovery and requires destructive reset.
- **I8 Background lock:** intended behavior is lock after five minutes in the background and stop BLE advertising; returning after the threshold must lock immediately. Current lifecycle wiring is missing; see known gaps.
- **I9 Request isolation:** rejection, timeout, disconnect, error and lock clear EIP-712 domain and ETH chunk state. Clearing request caches must not itself remove the unlocked session seed.
- **I10 History:** persist at most 200 signing outcomes using a seed-derived key. Persistence failure must not block signing. Lock/reset clear in-memory history; deleting a vault/layer removes its stored history entries.
- **I11 Accounts:** do not add the same chain/address twice within a vault.
- **I12 Navigation:** authentication and reset use router `go()` to clear prior authentication history. Do not render the main app before `hasWallet()` resolves.
- **I13 Secret output:** BLE responses never contain mnemonic, seed or private keys. New local export flows must not write secrets to files, storage or clipboard. The permitted output is deliberately PIN-gated local QR display with automatic hiding; the legacy clipboard route currently violates this contract.
- **I14 Layer isolation:** a stand-in session exposes only its own layer's vaults and behaves like a normal wallet. PIN change/backup operations use the session's scope and never modify shallower layers. Configuring/removing stand-ins may affect child layers. The explicit UI Reset Wallet operation is deliberately device-wide even in a stand-in session. A wipe credential destroys the immediately shallower layer (`depth - 1`) after validating the requested session's vault data. These deletion scopes must not be changed as an incidental refactor.

## Vaults, credentials and storage

Vaults belong to `depth` layers; depth 0 allows up to two normal vaults. Stand-in depth is capped at 2. Vaults in one layer share its PIN-derived key. Credential matching does one PBKDF2 derivation and attempts every verifier slot through `maxDepth` without short-circuiting, using dummy ciphertext for empty slots. This keeps work independent of the number of configured credentials; it is not a proof of perfect timing uniformity on all devices.

Wallet encryption uses PBKDF2-HMAC-SHA256 with 100,000 iterations and a random 16-byte device salt, followed by domain separation for verifier encryption. Each encryption uses a fresh nonce. Salt is public and remains unchanged across PIN changes. Storage is currently SharedPreferences, not an OS-keystore-backed implementation. A six-digit PIN remains vulnerable to offline guessing after storage extraction; online attempt counters cannot prevent that attack.

| Storage key | Content |
|---|---|
| `wallet.salt` | Public random device salt |
| `wallet.verifier.<depth>` | Encrypted PIN verifier |
| `wallet.vaultIndex` | Ordered vault identifiers |
| `wallet.vault.<id>` | Layer, label, encrypted mnemonic/passphrase, public accounts and creation metadata |
| `wallet.standIn.mode.<depth>` | Stand-in hide/wipe mode |
| `wallet.pinAttempts` | Shared persisted attempt counter |
| `wallet.signHistory` | Per-vault seed-encrypted history entries |

Public keys in account records are true public keys: ETH/Tron uncompressed 65 bytes, BTC compressed 33 bytes, Solana/Sui Ed25519 32 bytes. Current storage does not migrate old single-wallet keys. Old installs with only those keys are treated as having no wallet; users must recover from backup. Settings persistence is separate and is not fully reset by wallet deletion. See the [storage reference](../reference/storage-state.md) for operations and deletion scopes.

## Chains and APDU identity

Default paths are ETH `m/44'/60'/0'/0/0`, SOL `m/44'/501'/0'/0'`, BTC `m/84'/0'/0'/0/0`, Tron `m/44'/195'/0'/0/0`, and Sui `m/44'/784'/0'/0'/0'`. ETH/BTC/Tron use secp256k1; ETH signatures enforce low-s. Solana/Sui use Ed25519.

The active Ledger app is separate from BLE connection state. Starting a chain opens that app and begins advertising; stopping returns to the dashboard. Dashboard `GET_APP_AND_VERSION` reports format `00`/BOLOS; an open app reports format `01`. CLA `E0` selects the open Ethereum/Solana/Tron INS table. With no app open, app-specific `E0` commands return `6D00`. Bitcoin uses `E1`/`F8`, Sui uses `07`, and Tron retains a legacy `14` alias. Codec constants and framing are documented in [ble.md](../reference/ble.md).

## Known gaps in this snapshot

1. `AppState.onAppBackgrounded`/`onAppForegrounded` are not called from an App lifecycle observer. The only lifecycle observer handles privacy shielding, not wallet locking. The intended five-minute background lock and BLE pause/resume cannot be relied upon. Foreground idle locking and a manual lock entry point are also absent.
2. The registered legacy `/backup-seed` route still supports clipboard export; it is separate from the current QR export journey.
3. SharedPreferences storage and the six-digit PIN allow offline guesses if an attacker extracts app data. Metadata and counters are not encrypted as a whole-store boundary.
4. BLE-name edits are UI state only and do not persist or update the advertiser name; the device default is `OpenLedger`.
5. Android release builds still use debug signing. An official APK requires a deliberate release-signing setup and independent validation.
6. iOS, host-wallet compatibility, air-gap product flow and recovery behavior require separate validation. The corpus includes regression snapshots and declared gaps; passing them is not a blanket protocol certification.

## Implementation references

[Wallet lifecycle](../../apps/mobile-flutter/lib/biz/wallet_biz.dart), [PIN logic](../../apps/mobile-flutter/lib/biz/pin_biz.dart), [signing gate](../../apps/mobile-flutter/lib/biz/sign_confirmation.dart), [BLE session](../../apps/mobile-flutter/lib/biz/ble_session.dart), [App assembly](../../apps/mobile-flutter/lib/app/app_state.dart), [Rust encryption](../../crates/open-ledger-crypto/src/pbkdf2_chacha20.rs), [storage repository](../../apps/mobile-flutter/lib/data/repositories/vault_repository_impl.dart).
