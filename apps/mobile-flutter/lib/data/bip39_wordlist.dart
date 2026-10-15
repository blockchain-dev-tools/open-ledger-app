// ── Language Selection ─────────────────────────────────────────────

/// Supported BIP-39 wordlist languages.
///
/// The wordlists themselves are NOT held here: the Rust SDK owns them
/// (`crates/open-ledger-biz/src/mnemonic.rs`) and this file only maps a
/// language to the code that SDK expects.
///
/// Never send `enum.index` across FFI — it only happens to match the SDK's
/// codes while this list is `[english, chineseSimplified]`. Use
/// [bip39LanguageCode] instead.
enum Bip39WordlistLanguage {
  english,
  chineseSimplified,
  japanese,
  korean,
}

/// Maps a wordlist language to the Rust SDK's BIP-39 language code.
///
/// Must stay in sync with `Bip39Language` in
/// `crates/open-ledger-biz/src/mnemonic.rs` (0=English, 1=SimplifiedChinese,
/// 6=Japanese, 7=Korean). The Rust side is the only implementation that holds
/// the wordlists, so this is the single Dart→FFI mapping.
int bip39LanguageCode(Bip39WordlistLanguage lang) {
  switch (lang) {
    case Bip39WordlistLanguage.english:
      return 0;
    case Bip39WordlistLanguage.chineseSimplified:
      return 1;
    case Bip39WordlistLanguage.japanese:
      return 6;
    case Bip39WordlistLanguage.korean:
      return 7;
  }
}
