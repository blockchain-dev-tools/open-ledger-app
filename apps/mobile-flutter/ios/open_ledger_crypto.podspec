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
  # Every #[no_mangle] export in crates/open-ledger-ffi (lib.rs + types.rs);
  # Mach-O names carry one leading underscore. KEEP IN SYNC with the crate:
  # if a symbol is renamed/removed here, the LINK fails loudly (undefined
  # symbol) instead of the app failing silently at runtime.
  ffi_symbols = %w[
    chacha20_decrypt chacha20_encrypt
    derive_btc_address_ffi derive_ed25519_private_key_ffi derive_eth_address_ffi
    derive_secp256k1_private_key_ffi derive_sol_address_ffi derive_sui_address_ffi
    derive_tron_address_ffi
    enigma_derive_mnemonic enigma_entropy_hex
    eth_address_from_private_key_ffi eth_public_key_bytes_ffi
    free_ffi_result free_string
    generate_mnemonic generate_mnemonic_lang
    mnemonic_from_entropy mnemonic_to_seed
    p2wpkh_address_ffi parse_sign_data pbkdf2_derive
    reencode_mnemonic
    sign_eth_eip712_ffi sign_eth_personal_message_ffi sign_eth_transaction_ffi
    sign_solana_message_ffi solana_public_key_bytes_ffi sui_address_ffi
    tron_address_from_pubkey_ffi
    validate_mnemonic validate_mnemonic_lang
  ].map { |sym| "-Wl,-u,_#{sym}" }.join(' ')

  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => "$(inherited) -force_load $(SRCROOT)/libopen_ledger_crypto.a #{ffi_symbols}"
  }

  # Symbols live in the .a; no public header needed (Dart FFI uses dynamic lookups).
  s.source_files = []
  s.public_header_files = []
  s.preserve_paths = 'libopen_ledger_crypto.a'
end
