import 'package:flutter_test/flutter_test.dart';
import 'package:open_ledger_app/data/bip39_wordlist.dart';

void main() {
  group('bip39LanguageCode', () {
    test('maps to the Rust SDK BIP-39 language codes', () {
      // Must match `Bip39Language` in
      // crates/open-ledger-biz/src/mnemonic.rs (0/1/6/7).
      expect(bip39LanguageCode(Bip39WordlistLanguage.english), 0);
      expect(bip39LanguageCode(Bip39WordlistLanguage.chineseSimplified), 1);
      expect(bip39LanguageCode(Bip39WordlistLanguage.japanese), 6);
      expect(bip39LanguageCode(Bip39WordlistLanguage.korean), 7);
    });

    test('does not track the enum index for the non-contiguous languages', () {
      // Guard: the enum indices are 0..3 while the FFI codes are 0,1,6,7.
      // Sending `enum.index` across FFI would silently derive the wrong
      // wordlist, so any new language must come with an explicit mapping.
      expect(bip39LanguageCode(Bip39WordlistLanguage.japanese),
          isNot(Bip39WordlistLanguage.japanese.index));
      expect(bip39LanguageCode(Bip39WordlistLanguage.korean),
          isNot(Bip39WordlistLanguage.korean.index));
    });
  });
}
