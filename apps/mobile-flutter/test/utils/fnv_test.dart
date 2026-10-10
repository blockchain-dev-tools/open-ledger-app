/// Unit tests for [fnv1aFingerprint].
///
/// Covers determinism, collision resistance, edge cases, and
/// regression guard against known input/output pairs.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/utils/fnv.dart';

void main() {
  group('fnv1aFingerprint', () {
    // ── Regression guard ──────────────────────────────────────────────

    test('known input produces known output (regression guard)', () {
      const input = 'abandon abandon abandon abandon abandon abandon '
          'abandon abandon abandon abandon abandon about';
      final result = fnv1aFingerprint(input);
      // This MUST NOT change — if it does, mnemonic fingerprinting breaks.
      expect(result, '70624705');
    });

    test('another known input produces known output', () {
      const input = 'test mnemonic phrase for fingerprinting';
      final result = fnv1aFingerprint(input);
      expect(result, '48795685');
    });

    // ── Determinism ───────────────────────────────────────────────────

    test('same input produces same output across calls', () {
      const input = 'hello world';
      final r1 = fnv1aFingerprint(input);
      final r2 = fnv1aFingerprint(input);
      final r3 = fnv1aFingerprint(input);
      expect(r1, r2);
      expect(r2, r3);
    });

    test('same input with 10 calls is deterministic', () {
      const input = 'deterministic test 123';
      final results = <String>[];
      for (int i = 0; i < 10; i++) {
        results.add(fnv1aFingerprint(input));
      }
      final first = results.first;
      for (final r in results) {
        expect(r, first);
      }
    });

    // ── Different inputs → different outputs ──────────────────────────

    test('different inputs produce different outputs', () {
      final r1 = fnv1aFingerprint('apple');
      final r2 = fnv1aFingerprint('banana');
      final r3 = fnv1aFingerprint('cherry');
      expect(r1, isNot(r2));
      expect(r2, isNot(r3));
      expect(r1, isNot(r3));
    });

    test('one-character difference produces different output', () {
      final r1 = fnv1aFingerprint('testA');
      final r2 = fnv1aFingerprint('testB');
      expect(r1, isNot(r2));
    });

    test('case-sensitive inputs produce different outputs', () {
      final lower = fnv1aFingerprint('CaseSensitive');
      final upper = fnv1aFingerprint('CASESENSITIVE');
      expect(lower, isNot(upper));
    });

    test('trailing whitespace changes output', () {
      final noSpace = fnv1aFingerprint('text');
      final withSpace = fnv1aFingerprint('text ');
      expect(noSpace, isNot(withSpace));
    });

    // ── Empty string ──────────────────────────────────────────────────

    test('empty string returns 8 hex chars', () {
      final result = fnv1aFingerprint('');
      expect(result.length, 8);
      // Empty string should be deterministic too.
      final r2 = fnv1aFingerprint('');
      expect(result, r2);
    });

    test('empty string output is valid hex', () {
      final result = fnv1aFingerprint('');
      expect(RegExp(r'^[0-9a-f]{8}$').hasMatch(result), isTrue);
    });

    // ── Unicode ───────────────────────────────────────────────────────

    test('handles Unicode characters', () {
      final result = fnv1aFingerprint('héllo wörld 你好');
      expect(result.length, 8);
      expect(RegExp(r'^[0-9a-f]{8}$').hasMatch(result), isTrue);
    });

    test('Unicode determinism — same input, same output', () {
      const input = 'привет мир 🚀';
      final r1 = fnv1aFingerprint(input);
      final r2 = fnv1aFingerprint(input);
      expect(r1, r2);
    });

    test('similar Unicode but different normalized forms differ', () {
      // Different strings even if rendered similarly.
      final r1 = fnv1aFingerprint('café');
      final r2 = fnv1aFingerprint('cafe\u0301'); // combining accent
      // UTF-8 bytes differ, so hash should differ.
      expect(r1, isNot(r2));
    });

    test('emoji input returns valid 8-char hex', () {
      final result = fnv1aFingerprint('🔑🔒🔓');
      expect(result.length, 8);
      expect(RegExp(r'^[0-9a-f]{8}$').hasMatch(result), isTrue);
    });

    // ── Output format ─────────────────────────────────────────────────

    test('output is exactly 8 hex characters', () {
      final result = fnv1aFingerprint('any input here');
      expect(result.length, 8);
    });

    test('output is lowercase hex', () {
      final result = fnv1aFingerprint('Test Me 123');
      expect(result, result.toLowerCase());
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(result), isTrue);
    });

    test('output is zero-padded when hash value is small', () {
      // We can't easily force a small hash, but we can verify
      // the format includes leading zeros when needed.
      final result = fnv1aFingerprint('');
      // All 8 chars should be present even if leading zeros.
      expect(result.length, 8);
    });

    // ── Long input ────────────────────────────────────────────────────

    test('handles very long input (1000 chars)', () {
      final longInput = 'a' * 1000;
      final result = fnv1aFingerprint(longInput);
      expect(result.length, 8);
      expect(RegExp(r'^[0-9a-f]{8}$').hasMatch(result), isTrue);
    });

    test('long input is deterministic', () {
      final longInput = 'b' * 500;
      final r1 = fnv1aFingerprint(longInput);
      final r2 = fnv1aFingerprint(longInput);
      expect(r1, r2);
    });

    // ── Special characters ────────────────────────────────────────────

    test('handles newlines and tabs', () {
      final result = fnv1aFingerprint('line1\nline2\tindented');
      expect(result.length, 8);
    });

    test('handles only whitespace', () {
      final result = fnv1aFingerprint('   \t\n  ');
      expect(result.length, 8);
      final r2 = fnv1aFingerprint('   \t\n  ');
      expect(result, r2);
    });
  });
}
