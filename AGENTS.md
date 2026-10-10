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

The current credential model uses one random device salt, 100,000-round PBKDF2-HMAC-SHA256, domain-separated verifier encryption, and encrypted per-vault secrets. It does not store a plaintext PIN or a PBKDF2 output as a verifier. Do not reintroduce obsolete `wallet.pinKdf` migration advice; current single-wallet legacy keys are not read. Read the storage reference before modifying credential or deletion scopes.

Signing approval, rejection, timeout, locked-state handling and per-vault history must preserve the contract. Stand-in sessions isolate the current depth; the UI Reset Wallet action deliberately performs device-wide destruction. Secrets must not enter BLE responses, logs, files or clipboard in new flows. Preserve the documented legacy clipboard gap until it is fixed in a dedicated change.

Crypto FFI uses null-terminated encoded strings and matching Rust allocation/free contracts. Clear cached seed/session material when provider/passphrase changes. Wrap fallible FFI calls from gesture callbacks with explicit error handling. Maintain independent crypto test vectors.

## UI and protocol conventions

Use `ColorTokens` and `R` from `ui/theme/`; no hardcoded theme colors/radii. Localize user-visible strings. Every new interactive widget needs a stable `ValueKey`. Do not stack a bottom sheet on another bottom sheet; switch views within one modal.

The device uses tag-first BLE framing: first header 5 bytes (`tag + seq + length`), continuation 3 bytes. There is no `0x0101` channel prefix. App identity selects the CLA `0xE0` INS table; keep `LedgerApp` and `apdu_constants.dart` authoritative. Service discovery must use live advertisement events; do not interpret a stale BlueZ cache as evidence of missing UUIDs.

The native Android application ID is `app.openledger.mobile`. Use the existing router's `go()` behavior to clear authentication/reset navigation history. Startup must remain empty/splash until wallet existence resolves.

## Checks

Commands and host prerequisites are in [BUILDING.md](BUILDING.md). Use `--no-version-check --suppress-analytics` with Flutter. Mock only core interfaces; unit tests must not require Rust or a real device. Test files follow the existing `test/` structure.

Every changed user-visible flow or BLE/APDU behavior requires a real-device E2E case in `tool/e2e/tests/` as well as relevant unit coverage. State unavailable device coverage candidly. Gallery is web-only and may not import `dart:ffi`, native BLE or FFI implementations.

Keep screenshots, UI dumps and validation logs in ignored root `tmp/` using disposable test wallets. Review staged files, Git identity and all reachable history before publication. Report existing limitations from `SECURITY.md`; do not promote intended behavior into an established guarantee.
