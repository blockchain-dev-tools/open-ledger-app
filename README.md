<picture>
  <source media="(prefers-color-scheme: dark)" srcset="branding/openledger-community-dark.svg">
  <img alt="OpenLedger" src="branding/openledger-community-light.svg" width="450">
</picture>

# Open Ledger App

[中文](README.zh-CN.md) · [Build instructions](BUILDING.md) · [Security](SECURITY.md)

Open Ledger App turns an Android phone into a signing device that implements a Ledger Nano X-style BLE GATT profile and APDU interface. The Flutter app presents accounts and approval screens; the Rust SDK derives keys, parses signing payloads and performs cryptography on the device.

This repository contains the device app and Rust SDK. The website and debugger are maintained separately. This is a curated source snapshot with new public Git history, rather than an export of the original development history.

## Status and security

The Android app is the current development target. iOS contains experimental integration scaffolding; simulator and end-to-end compatibility are not established. ETH, Solana, Bitcoin, Tron and Sui have protocol and crypto implementations, but that does not establish compatibility with every host wallet or every operation. See the [verification matrix](docs/testing/ble-wallets.md).

The source has not received an independent security audit. Current limitations include ordinary SharedPreferences storage, a six-digit PIN that remains susceptible to offline guessing if storage is extracted, unconnected background-lock lifecycle handlers, a legacy clipboard-capable seed route, and debug signing in the Android release configuration. Read [SECURITY.md](SECURITY.md) before evaluating the app with wallet data. Use public test vectors and disposable test wallets for development.

## Repository layout

```text
apps/mobile-flutter/    Flutter UI, Android/iOS projects, tests and tooling
crates/                Rust crypto, chain logic and C FFI workspace
spec/apdu/             APDU command coverage and conformance vectors
docs/                  Product contract, protocol and testing references
patches/               Pinned upstream correction for E2E dependencies
```

The directory layout is retained to keep build scripts and test corpus paths stable. Runtime cryptography is implemented in Rust. Root Node dependencies are used only by the independent host-side E2E verifier.

## Build and test

Install a Flutter SDK compatible with Dart `^3.12.0`, Rust stable, Java 17, and the Android SDK/NDK. See [BUILDING.md](BUILDING.md) for platform prerequisites, FFI packaging and release limitations.

From the repository root:

```bash
cargo test --locked --manifest-path crates/Cargo.toml
make build ARGS="--no-pull"
```

From `apps/mobile-flutter/`:

```bash
flutter --no-version-check --suppress-analytics pub get
flutter --no-version-check --suppress-analytics analyze
flutter --no-version-check --suppress-analytics test
```

The standalone [design gallery](apps/mobile-flutter/tool/gallery/main.dart) runs on Flutter web with mock data; the wallet device entry point requires native FFI and BLE.

## Documentation and contributions

- [Product contract and known gaps](docs/product/contract.md)
- [Storage and credential model](docs/reference/storage-state.md)
- [BLE/APDU transport](docs/reference/ble.md)
- [Enigma deterministic derivation](docs/reference/enigma.md)
- [State machines](docs/reference/state-machines.md)
- [Real-device E2E harness](apps/mobile-flutter/tool/e2e/README.md)
- [Contributing](CONTRIBUTING.md) and [architecture rules](AGENTS.md)

Project code is under the [MIT license](LICENSE). Third-party fonts, assets and dependencies have their own terms; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Ledger names describe protocol compatibility; this project is not an official Ledger product and a general-purpose phone does not provide Ledger hardware's security boundary.
