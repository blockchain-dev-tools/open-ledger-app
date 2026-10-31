# Agent and contributor rules

This public repository contains only the Flutter device app, Rust SDK and their tests. Before changing product behavior, read [docs/product/contract.md](docs/product/contract.md). Screen inventory is in `apps/mobile-flutter/lib/core/router.dart`.

## Structure and dependencies

- `crates/`: Rust crypto primitives, chain logic and C FFI; device crypto source of truth.
- `apps/mobile-flutter/`: Flutter device app. Preserve its path and root `spec/apdu/` corpus.
- Root Node dependencies: independent E2E verifier only; do not add web wallet implementations here.
- No generated native libraries, local SDK configuration, signing secrets or private test data in Git.

Flutter layers are unidirectional:

| Layer | May import |
|---|---|
| `core/` | Pure Dart, no other app layer |
| `data/`, `infrastructure/`, `protocols/` | `core/` |
| `biz/` | `core/`, `protocols/` |
| `services/` | `core/`, `biz/` |
| `app/` | `services/`, `biz/`, `infrastructure/`, `protocols/`, `core/` |
| `ui/` | `services/`, `protocols/`, `core/` |

The composition root `lib/main.dart` assembles implementations. Data structures belong in `core/models/`, abstract contracts in `core/interfaces/`, I/O in `data/` or `infrastructure/`, logic in `biz/` or `services/`, and widgets in `ui/`.

## Security and behavior

The credential model uses one random device salt, 100,000-round PBKDF2-HMAC-SHA256, domain-separated verifier encryption, and encrypted per-vault secrets. It does not store a plaintext PIN or a PBKDF2 output as a verifier. Wallet keys are persisted only through keystore-backed `SecureStorage`; plaintext `SharedPreferencesStorage` survives solely as the one-time migration source and for tests. Do not reintroduce obsolete `wallet.pinKdf` migration advice; current single-wallet legacy keys are not read. Read the storage reference before modifying credential or deletion scopes. Do not add a stronger KDF (e.g. Argon2id) as a hardening measure: a six-digit PIN is the limiting factor, and keystore binding — not per-guess cost — is what protects extracted data.

Signing approval, rejection, timeout, locked-state handling and per-vault history must preserve the contract. Stand-in sessions isolate the current depth; the UI Reset Wallet action deliberately performs device-wide destruction. Secrets must not enter BLE responses, logs, files or clipboard in new flows. Preserve the documented legacy clipboard gap until it is fixed in a dedicated change.

Crypto FFI uses null-terminated encoded strings and matching Rust allocation/free contracts. Clear cached seed/session material when provider/passphrase changes. Wrap fallible FFI calls from gesture callbacks with explicit error handling. Maintain independent crypto test vectors.

Anything the UI claims about a derivation (match counts, validation, previews) must come from the same Rust function that derives it — never re-implement tokenisation, wordlists or index encoding in Dart or TypeScript. Verify a new export exists in the built artifact (`nm -D libopen_ledger_crypto.so | grep <symbol>`) before wiring it up. Dart bridges degrade instead of throwing when a symbol is missing (`flutter test` runs without Rust): return `null` and let the dependent UI hide itself.

Secret-phrase derivation parameters are frozen (see the workspace ADR-019): changing the tokenisation, the u16 big-endian index encoding, `MAX_INDICES`, `MAX_ENIGMA_CAP` or the fixed English output silently re-derives a different wallet for phrases that cross the changed bound. Treat such a change as a new mode with a migration path, never an in-place constant tweak.

## UI and protocol conventions

Use `ColorTokens` and `R` from `ui/theme/`; no hardcoded theme colors/radii. Localize user-visible strings. Every new interactive widget needs a stable `ValueKey`. Do not stack a bottom sheet on another bottom sheet; switch views within one modal. When a derivation consumes a capped or filtered input (secret-phrase tokens, imported word counts), show the effective size next to the input — the Secret Phrase screen surfaces its BIP-39 match count, and zero contribution warns instead of silently deriving.

Light mode speaks a neobrutalist chrome (per neobrutalism.dev): a hard `Neo.edge`-px black outline, flat fills and a blur-free `Neo.lift`-px offset shadow. It is opt-in per surface and light-only: gate every neo branch on `ColorTokens.neobrutalism` so dark keeps the flat grouped-list chrome. Reuse the shared `NeoCard` / `NeoButton` / `NeoCodeBlock` (`lib/ui/widgets/common/neo_*.dart`), the `Neo` metrics and the `ColorTokens.neo*` tokens (`lib/ui/theme/color_tokens.dart`) — never hardcode the black edge, shadow or lime fill. New screens render neo in light mode and fall back to the legacy chrome in dark (shared widgets expose an explicit `neo` flag, e.g. `TxDetailsCard`). How the mechanism is wired is documented in [docs/reference/ui-neobrutalism.md](docs/reference/ui-neobrutalism.md).

The device uses tag-first BLE framing: first header 5 bytes (`tag + seq + length`), continuation 3 bytes. There is no `0x0101` channel prefix. App identity selects the CLA table (`0xE0` for Ethereum/Solana/Tron and the legacy Bitcoin app, `0xE1` for the current Bitcoin app, `0xF8` only for Bitcoin's `CONTINUE`); keep `LedgerApp` and `apdu_constants.dart` authoritative. Service discovery must use live advertisement events; do not interpret a stale BlueZ cache as evidence of missing UUIDs.

Dart hands the chain host a re-serialized command (`ApduCommand.toBytes()`), which drops `Lc` for empty data: an empty `F8 01 CONTINUE` arrives at Rust as a 4-byte case-1 APDU. Every module's `Apdu::parse` must treat a 4-byte frame as empty data (a real-device-only bug: the Rust unit tests keep using 5 bytes).

APDU compatibility is a claim that must be proven, never asserted. Inside a standard CLA/INS namespace, implement the official semantics byte for byte and cite the source (`file:line @ version`) beside the constant. Extensions get their own INS/CLA and are labelled non-standard in the module header and in `AppDescriptor.protocol_profiles`. A command must never reuse an official number with different semantics. Bitcoin's old `E1 44 SIGN_DIGEST` was exactly that (legacy `0x44` is `HASH_INPUT_START`; the current app has none) and has been **deleted**: signing now goes only through `E1 04 SIGN_PSBT`, and `E1 40` remains the single explicitly-labelled address extension. The gate is a table-driven test: enumerate every official INS and assert each one is either implemented with official semantics or rejected (`official_bitcoin_commands_are_not_silently_reinterpreted` in `crates/chain-app-bitcoin/tests/` is the template). Real interoperability is only proven by driving the device with the official host library from `tool/e2e/`, not by our own harness.

PSBT bytes have two traps that our own host and device can agree on while both being wrong: the PSBTv2 global key types are `0x02 TX_VERSION / 0x03 FALLBACK_LOCKTIME / 0x04 INPUT_COUNT / 0x05 OUTPUT_COUNT`, and the `bip32_derivation` path components are **little-endian** (BIP-174). Both were wrong until `@ledgerhq/hw-app-btc` refused our PSBT; `btc_official.py` is the regression that keeps them honest. The same library also drives the device's whole command sequence: `E1 05 GET_MASTER_FINGERPRINT` (4-byte master fingerprint), `E1 00 GET_EXTENDED_PUBKEY` (ASCII xpub; the module asks the host for the account key + chain code and for the parent key to fill the parent fingerprint), then `E1 04`. Those two commands need `allow_chain_code` and depth-0/2/3 derivation rules in both the module descriptor and the FFI host policy.

The native Android application ID is `app.openledger.mobile`. Use the existing router's `go()` behavior to clear authentication/reset navigation history. Startup must remain empty/splash until wallet existence resolves.

## Checks

Commands and host prerequisites are in [BUILDING.md](BUILDING.md). Use `--no-version-check --suppress-analytics` with Flutter. Mock only core interfaces; unit tests must not require Rust or a real device. Test files follow the existing `test/` structure — a `*_test.dart` under `lib/` is never collected by `flutter test` and rots silently, so move or delete it instead of leaving it there.

When the worktree carries someone else's unfinished work, commit only your own change: stage per hunk (`git diff -- <file>` → keep your hunks → `git apply --cached`) and grep the staged diff for the other feature's identifiers before committing. Generated outputs (ARB-derived `lib/generated/l10n/*`, lockfiles) are rewritten wholesale and cannot be split — stage your keys' hunks, accept the temporary index/worktree skew, and say so in the commit body.

Every changed user-visible flow or BLE/APDU behavior requires a real-device E2E case in `tool/e2e/tests/` as well as relevant unit coverage. State unavailable device coverage candidly. Gallery is web-only and may not import `dart:ffi`, native BLE or FFI implementations.

Keep screenshots, UI dumps and validation logs in ignored root `tmp/` using disposable test wallets. Review staged files, Git identity and all reachable history before publication. Report existing limitations from [SECURITY.md](SECURITY.md); do not promote intended behavior into an established guarantee.

Commits must use the repository identity (`user.name` / `user.email`) for **both** author and committer. Agent runtimes may export `GIT_COMMITTER_NAME` / `GIT_COMMITTER_EMAIL` for an automation identity (for example `trae-solo-agent`); unset them before committing (`env -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL git commit …`). A local `.git/hooks/pre-commit` identity guard rejects mismatches.

On iOS a debug build cannot be launched from the home screen (iOS 14+ restriction), so `apps/mobile-flutter/scripts/build_and_install_ios.sh` defaults to release; use `--debug` only together with an attached debug session (`--run` or `flutter attach`). See [apps/mobile-flutter/scripts/README.md](apps/mobile-flutter/scripts/README.md).
