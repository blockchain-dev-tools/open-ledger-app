import 'package:flutter_test/flutter_test.dart';
import 'package:open_ledger_app/data/bip39_english.dart';

void main() {
  group('bip39English', () {
    test('is the canonical 2048-word list', () {
      expect(bip39English, hasLength(2048));
      expect(bip39English.toSet(), hasLength(2048), reason: 'no duplicates');
      expect(bip39English, equals([...bip39English]..sort()),
          reason: 'alphabetically sorted, like the BIP-39 spec');
      expect(bip39English.first, 'abandon');
      expect(bip39English.last, 'zoo');
      expect(bip39English, contains('art'));
      expect(bip39English, contains('zebra'));
    });
  });

  group('bip39Suggestions', () {
    test('returns alphabetical prefix matches capped at the limit', () {
      expect(
        bip39Suggestions('a'),
        ['abandon', 'ability', 'able', 'about', 'above'],
      );
      expect(
        bip39Suggestions('ab'),
        ['abandon', 'ability', 'able', 'about', 'above'],
      );
      expect(bip39Suggestions('aban'), ['abandon']);
    });

    test('honours a custom limit', () {
      expect(bip39Suggestions('a', limit: 2), ['abandon', 'ability']);
      expect(bip39Suggestions('a', limit: 0), isEmpty);
      expect(bip39Suggestions('a', limit: -1), isEmpty);
    });

    test('is case-insensitive and trims the prefix', () {
      expect(bip39Suggestions('  ABAN '), ['abandon']);
    });

    test('returns empty for no match or an empty prefix', () {
      expect(bip39Suggestions(''), isEmpty);
      expect(bip39Suggestions('notaword'), isEmpty);
    });
  });

  group('bip39InputSuggestions', () {
    test('suggests only while the current word is unfinished', () {
      expect(bip39InputSuggestions('aban'), ['abandon']);
      expect(bip39InputSuggestions('abandon aban'), ['abandon']);
      expect(bip39InputSuggestions('abandon '), isEmpty);
      expect(bip39InputSuggestions(''), isEmpty);
    });

    test('suppresses suggestions once the token is an exact word', () {
      expect(bip39InputSuggestions('abandon'), isEmpty);
      expect(bip39InputSuggestions('abandon art'), isEmpty);
    });

    test('ignores whitespace before the in-progress word', () {
      expect(bip39InputSuggestions('  aban'), ['abandon']);
    });
  });
}
