# ── Podspec for the Rust open-ledger-ffi static library (iOS) ──────────────────
# Wraps crates/target/aarch64-apple-ios/release/libopen_ledger_crypto.a as a
# vendored static library. When `pod install` runs, CocoaPods statically links
# the .a into the Runner executable — making all #[no_mangle] extern "C" symbols
# visible via DynamicLibrary.process() on the Dart side.
#
# Why a Podspec + Podfile rather than editing project.pbxproj by hand:
# - Xcode pbxproj is fragile to hand-edit; Podfile is text and version-controllable.
# - CocoaPods handles arm64 slice selection, linking order, and OTHER_LDFLAGS.
#
# The .a is built with:
#   cargo build --manifest-path crates/Cargo.toml \
#       --target aarch64-apple-ios --release
# (the staticlib crate-type is enabled in crates/open-ledger-ffi/Cargo.toml).
Pod::Spec.new do |s|
  s.name             = 'open_ledger_crypto'
  s.version          = '0.1.0'
  s.summary          = 'Rust crypto SDK for Open Ledger App (BIP-39/32, secp256k1, Ed25519, ChaCha20-Poly1305).'
  s.description      = <<-DESC
  Statically linked Rust crypto primitives consumed by the Flutter app via dart:ffi.
  Built from the crates/open-ledger-ffi crate as a staticlib (.a) for aarch64-apple-ios.
  DESC
  s.license          = { :type => 'MIT' }
  s.homepage         = 'https://github.com/blockchain-dev-tools/open-ledger-app'
  s.author           = 'Open Ledger App contributors'
  s.source           = { :path => '.' }

  # arm64 device only — sim slice (aarch64-apple-ios-sim) not wired up here yet.
  s.ios.deployment_target = '15.0'
  s.vendored_libraries = 'libopen_ledger_crypto.a'

  # ── Keep Rust FFI symbols alive through dead-strip ───────────────────
  # Dart FFI resolves #[no_mangle] symbols at RUNTIME (dlsym), so the linker
  # sees no static references to them. Even with -force_load, Xcode's default
  # -dead_strip then removes every Rust object again — FFI calls fail on the
  # device with lookup errors. Fix: mark each entry point as a required root
  # (-u), which both pulls it in and shields it from dead-strip.
  #
  # The required-root list is derived from the archive itself instead of being
  # hand-maintained: a stale hand-written list silently drops newly added
  # exports (that is exactly how aead_encrypt_with_key, hkdf_expand32,
  # constant_time_eq, history_encrypt/decrypt, public_key_for_chain,
  # encode_private_key and derive_secp256k1_extended_ffi went missing at
  # runtime while the link still succeeded).
  #
  # Selection rule: global text symbols with a SINGLE leading underscore are
  # the `#[no_mangle] extern "C"` entry points. Everything the toolchain adds
  # uses a double/triple underscore instead — Rust-mangled names (`__R…`) and
  # the bundled compiler-rt/libc runtime (`__aarch64_*`, `___absvdi2`) — so it
  # is filtered out. (A few single-underscore runtime helpers such as
  # `_atomic_thread_fence` may slip through; force-keeping them is harmless.)
  archive = File.join(__dir__, 'libopen_ledger_crypto.a')
  raise "open_ledger_crypto: #{archive} is missing — build the Rust SDK first" unless File.exist?(archive)

  ffi_symbols = `nm -gU "#{archive}" 2>/dev/null`
    .lines
    .map(&:split)
    .select { |parts| parts[1] == 'T' && parts[2].to_s.start_with?('_') }
    .map { |parts| parts[2] }
    .uniq
    .reject { |sym| sym.start_with?('__') }
  raise 'open_ledger_crypto: no exported symbols found in the archive' if ffi_symbols.empty?

  ffi_symbols = ffi_symbols.map { |sym| "-Wl,-u,#{sym}" }.join(' ')

  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => "$(inherited) -force_load $(SRCROOT)/libopen_ledger_crypto.a #{ffi_symbols}"
  }

  # Symbols live in the .a; no public header needed (Dart FFI uses dynamic lookups).
  s.source_files = []
  s.public_header_files = []
  s.preserve_paths = 'libopen_ledger_crypto.a'
end
