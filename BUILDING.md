# Building Open Ledger App

Run root commands from the clone's own Git root. The app remains at `apps/mobile-flutter/`; Rust remains at `crates/`. Do not move only one directory or build against files from another checkout.

## Toolchains

| Tool | Requirement |
|---|---|
| Flutter | Flutter 3.44.0 (official tag), Dart 3.12.0; lockfile requires Flutter >=3.44.0 |
| Rust | Stable Cargo/rustc; Android target `aarch64-linux-android` |
| Android | SDK, NDK, platform tools and Java 17; declare SDK paths locally |
| Node | `>=20.19.0`, only for independent E2E verification |
| pnpm | `10.34.5`, pinned in root `package.json` |
| Python | 3.10+ for the E2E harness; 3.9+ for font subsetting |
| E2E host | Linux with BlueZ, a BLE adapter, Python `dbus`/`gi`, and an Android test device |

Record `flutter --no-version-check --version`, `cargo --version`, `rustc --version`, Java and NDK versions when reporting a build. CI pins the official Flutter 3.44.0 tag (revision `559ffa3f75e7402d65a8def9c28389a9b2e6fe42`), matching project metadata and lockfile constraints. Local Flutter validation still requires that SDK; newer SDKs are not automatically covered. The Android NDK helper chooses an installed version; configure `ANDROID_NDK_HOME` explicitly for reproducibility. Some helper commands depend on GNU `sort -V`, Bash `mapfile`, or Linux sysfs. Linux is the documented Android/E2E build host; do not assume macOS helpers work unchanged.

## Dart checks and host Rust tests

From the root:

```bash
cargo test --locked --manifest-path crates/Cargo.toml
```

From `apps/mobile-flutter/`:

```bash
PUB_HOSTED_URL=https://pub.dev flutter --no-version-check --suppress-analytics pub get --enforce-lockfile
flutter --no-version-check --suppress-analytics analyze
flutter --no-version-check --suppress-analytics test
```

The committed lockfile uses `pub.dev`, matching CI. Package sources are part of the lockfile: changing `PUB_HOSTED_URL` to a mirror requires resolving a local lockfile for that source. Keep mirror-specific changes local; preserve the official-source lockfile in commits. Messages about newer incompatible package versions are informational and do not require an upgrade for a locked install.

`spec/apdu/` must be present at the repository root. Plain `flutter test` skips real-Rust conformance cases when the native library cannot load. On Linux, exercise those cases explicitly after a host build:

```bash
# Repository root
cargo build --locked --manifest-path crates/Cargo.toml --release
cd apps/mobile-flutter
LD_LIBRARY_PATH="$PWD/../../crates/target/release${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  flutter --no-version-check --suppress-analytics test \
  test/protocols/apdu/real_crypto_conformance_test.dart
```

On macOS the existing FFI loader uses `DynamicLibrary.process()` and expects statically linked native app symbols. Building a host `.dylib` alone does not enable the Flutter test runner; a passing skipped suite is not evidence of real FFI coverage there.

## Android APK

Install the Rust target once:

```bash
rustup target add aarch64-linux-android
```

Set `ANDROID_HOME` and `ANDROID_NDK_HOME` to your installed SDK/NDK outside the repository. Then from the root:

```bash
make build ARGS="--no-pull"
```

This compiles Rust for arm64 Android, copies `libopen_ledger_crypto.so` into the app's ignored `android/app/src/main/jniLibs/arm64-v8a/` directory, runs pub get and builds the debug APK. `--no-pull` keeps the inspected source revision fixed. Never use `--skip-rust` on a fresh clone; it requires an already-built, matching native library.

Verify native packaging:

```bash
unzip -l apps/mobile-flutter/build/app/outputs/flutter-apk/app-debug.apk \
  | rg 'lib/arm64-v8a/libopen_ledger_crypto.so'
```

Outputs, local SDK properties and signing keys are generated locally and must stay out of Git. The Android Gradle wrapper launchers/JAR are not tracked in this snapshot; Flutter's build tooling prepares wrapper support when needed. A fresh-clone build must verify that preparation on the supported SDK.

Device operations are explicit:

```bash
make check
make install ARGS="--launch"
```

Use a dedicated test device. Installing with replacement does not refresh a running app: the script force-stops the process; `--launch` cold-starts it. Test cases using fresh sessions clear App data. Read the E2E instructions before running them.

## E2E dependencies

From the root, install only the pinned host-verifier dependencies:

```bash
pnpm install --frozen-lockfile --ignore-scripts
```

The committed `pnpm-workspace.yaml` defines this clone as an independent workspace, including when it sits inside another checkout. Default pnpm commands therefore use this manifest and lockfile; no `--ignore-workspace` override is required. The small root dependency graph preserves the original resolved versions and BIP-39 package correction; it does not include website packages.

From `apps/mobile-flutter/`, install Python dependencies in a virtual environment:

```bash
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r tool/e2e/requirements.txt
bash tool/e2e/run.sh
```

The requirements file specifies the Python VM-service transport. `dbus-python` and PyGObject (`gi`) are supplied by the Linux distribution, together with BlueZ. A venv may need `--system-site-packages` to access them. See the [harness README](apps/mobile-flutter/tool/e2e/README.md) for permissions and device setup.

## Design gallery

From `apps/mobile-flutter/`:

```bash
flutter --no-version-check --suppress-analytics run \
  -t tool/gallery/main.dart -d chrome
flutter --no-version-check --suppress-analytics build web \
  --release -t tool/gallery/main.dart
```

Gallery mock data must never import FFI or native BLE. The subset font assets are committed; regeneration is optional and uses `fonttools` plus upstream Noto CJK fonts. Keep their OFL license with distributed assets.

## Experimental iOS and release builds

The iOS scaffold expects a device-arm64 static archive beside its Podspec. The generated archive is excluded from source control. On an appropriately configured macOS/Xcode host:

```bash
# Repository root
rustup target add aarch64-apple-ios
cargo build --locked --manifest-path crates/Cargo.toml \
  --target aarch64-apple-ios --release
cp crates/target/aarch64-apple-ios/release/libopen_ledger_crypto.a \
  apps/mobile-flutter/ios/libopen_ledger_crypto.a
cd apps/mobile-flutter
flutter --no-version-check --suppress-analytics pub get
cd ios
pod install
```

This describes archive preparation, not a validated iOS product. Simulator slices and BLE peripheral behavior require separate verification. The Podspec's symbol list must match the Rust FFI exports.

Android `--release` currently still uses debug signing. Before distributing an official APK, configure release signing with secrets supplied outside Git, verify the public certificate and native packaging, address the security limits in [SECURITY.md](SECURITY.md), and publish checksums against the corresponding source tag. A release build flag alone does not establish release readiness.
