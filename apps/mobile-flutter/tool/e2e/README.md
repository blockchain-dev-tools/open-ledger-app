# Real-device E2E harness

The harness uses `flutter attach` and Dart VM Service `evaluate` to drive a debug App without rebuilding each test. A Rust GATT central (`ble-central`, CoreBluetooth on macOS and BlueZ on Linux) acts as the host for every case; independent Node cryptography verifies signing results. Runtime device behavior is unchanged by the harness.

## Environment

- Dedicated Android test device, Bluetooth on, ADB authorized. The harness may clear App data when a test requests a fresh session; never use it on a personal wallet installation.
- A debug APK with the Rust arm64 library. Build from the root using `make build ARGS="--no-pull"`. Device permission behavior varies; installing the test APK with `adb install -r -g <apk>` can grant runtime permissions at installation.
- Flutter SDK for attach, with `--no-version-check --suppress-analytics`.
- A BLE adapter. No extra setup is needed: `tool/e2e/ble-central` (Rust + `btleplug`) is built on demand and maps to CoreBluetooth on macOS and BlueZ on Linux. Linux hosts with `dbus-python` + PyGObject (`gi`) additionally use the Python BlueZ central for the signing cases; without them (e.g. macOS) those cases fall back to the Rust central.
- Python 3 with `websockets` from `requirements.txt` (`pip install -r tool/e2e/requirements.txt`).
- Node `>=20.19.0` and the root pinned `@noble`/`@scure` dependencies. Install from this repository's root with `pnpm install --frozen-lockfile --ignore-scripts`. The root workspace boundary keeps this dependency graph independent even when the repository is nested in another checkout.

From `apps/mobile-flutter/`:

```bash
python3 -m venv --system-site-packages .venv
. .venv/bin/activate
python -m pip install -r tool/e2e/requirements.txt
bash tool/e2e/run.sh
bash tool/e2e/run.sh sign
```

USB/MTP may be needed on Linux systems without dedicated ADB udev rules; use root `make check` to diagnose. Do not publish the output's device serial or local VM-service URI.

## Harness structure

`harness/attach.py` owns attach/start/cleanup and parses DDS URI; `rpc.py` speaks VM Service; `expr.py` makes short Dart evaluation expressions; `app.py` drives stable widget keys. `device.py` handles test-device reset/start (including the ROMs that refuse `pm clear`, via `run-as` deletion of the persisted preferences); `session.py` composes a test session and picks the GATT transport; `ble.py` is the Python BlueZ central, `ble_transport.py` the Rust central, and `ble_framing.py` holds the shared tag-first framing. `js/ethverify.mjs` independently derives/recover secp256k1 addresses; `js/edverify.mjs` does the same for SLIP-10 Ed25519 (derive + verify); `js/btcverify.mjs` derives Bitcoin's four address types and verifies BIP-340 Schnorr signatures (Taproot tweak included), with address strings encoded in Python by `harness/btcaddr.py` / `harness/base58x.py`. `harness/base58x.py` is an independent base58/base58check encoder for Solana and Tron address assertions.

The root `spec/apdu/` corpus and [device transport](../../../../docs/reference/ble.md) remain separate from UI-driver tooling. Tests currently include smoke, personal-message signing, legacy ETH transaction signing, EIP-712 V0 signing, Bitcoin four address types (P2PKH / P2SH-P2WPKH / P2WPKH / P2TR) plus ECDSA multi-input and Taproot Schnorr signing (`tests/btc_sign.py`), Solana address + Ed25519 signing (`tests/sol_sign.py`), Sui address + signing (`tests/sui_sign.py`), Tron address/version (`tests/tron_address.py`) and Tron `0x04`/`0x05`/`0x08` signing incl. the generic review for unknown contract types (`tests/tron_sign.py`), NEAR address + Borsh transfer signing (`tests/near_sign.py`), TON v4r2 `TransactionOrder` signing with an independent cell-hash recomputation (`tests/ton_sign.py`), recovery-phrase import (prefix autocomplete + 24-word acceptance, `tests/import_wallet.py`), adding a vault from a secret phrase (`tests/add_vault_secret_phrase.py`), address confirmation (`tests/address_confirm.py`: reject, 60s timeout and approve) and a general BLE regression suite (`tests/ble_regression.py`); they do not establish all-chain or all-host interoperability. Camera-based QR scanning cannot be driven over VM Service — verify it manually with [the checklist](../../../../docs/testing/e2e-checklist.md).

`tests/ble_regression.py` is the case to run after any BLE/APDU change. It covers discovery/connect/MTU, ETH version and configuration, a public-key request large enough to span fragments (verified against an independently derived address), error status words, `OPEN_APP` app switching, `QUIT_APP` back to the dashboard, disconnect/reconnect, and advertising recovery after a Bluetooth toggle. The GATT central is `tool/e2e/ble-central` (Rust + `btleplug`, built on demand): it uses CoreBluetooth on macOS and BlueZ on Linux, so the suite runs on either host without extra setup. On macOS the terminal needs Bluetooth permission on first use. The signing cases (`tests/sign_message.py`, `tests/sign_transaction.py`) use the same central, so they also run on macOS; their multi-chunk upload path relies on `prepare_recv` / `send_raw`, which both transports implement.

## Authoring cases

Put cases in `tests/<name>.py`, expose an async run returning a status, and use `DeviceSession`/`FlutterApp` helpers. Stable `ValueKey`s must identify every new interaction. Fresh cases must create their own disposable state. Validate signatures independently; byte count alone is insufficient.

VM Service evaluation must use a short return value because long `valueAsString` output can truncate. Attach must provide Flutter's `compileExpression` service; a bare connection to an unprepared VM Service is insufficient. The driver can scroll keyed widgets into view before injecting pointer events.

Use known public BIP-39 vectors, never production recovery data. The bundled `abandon` ×11 plus `about` vector is publicly predictable and must never receive assets. Examples of fixed PINs/keys in tests are fixtures, not recommended real credentials.

## BLE and lifecycle limits

The device uses tag-first fragments: initial header 5 bytes, continuation 3 bytes. Match live advertisements by UUID and collect BlueZ property signals during discovery. Scan-response placement alone does not explain absent UUIDs; post-scan cache reads can be misleading. Device names are only fallback clues.

Background locking is wired through `WidgetsBindingObserver` in `main.dart` (paused/hidden start the timer, resumed locks if the window elapsed). Foreground idle locking is a sliding five-minute window restarted by any pointer down. Both are covered by `tests/idle_lock.py` — a slow case (it waits out real time) that checks the sliding window, the idle lock, and the background→foreground lock. Tests of handler functions alone do not prove deployed App behavior. See [state machines](../../../../docs/reference/state-machines.md), [security policy](../../../../SECURITY.md), [manual checklist](../../../../docs/testing/e2e-checklist.md), and [host verification matrix](../../../../docs/testing/ble-wallets.md).
