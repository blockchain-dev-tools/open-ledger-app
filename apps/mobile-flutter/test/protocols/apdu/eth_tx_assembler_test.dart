/// Unit tests for [EthTxAssembler] and [rlpTotalLength].
///
/// Covers RLP length calculation, single/multi-chunk assembly, orphan
/// continuation, oversized payload, replacement/reset, immutable
/// payload, and one-confirmation-per-assembly.
///
/// All tests are pure Dart — no Rust FFI or real device required.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/protocols/apdu/rlp_parser.dart';
import 'package:open_ledger_app/protocols/apdu/eth_tx_assembler.dart';

// ═══════════════════════════════════════════════════════════════════════
// RLP test vectors
// ═══════════════════════════════════════════════════════════════════════

/// Build a minimal valid RLP list with a known total length.
///
/// RLP short list: `[0xc0 + N] [payload_N_bytes]` → total = 1 + N.
Uint8List _rlpShortList(int payloadLen) {
  final payload = Uint8List(payloadLen);
  return Uint8List.fromList([0xc0 + payloadLen, ...payload]);
}

/// Build an RLP long list with a 1-byte length prefix.
///
/// `[0xf8] [len_byte] [payload]` → total = 2 + len.
Uint8List _rlpLongList(int payloadLen) {
  final payload = Uint8List(payloadLen);
  return Uint8List.fromList([0xf8, payloadLen, ...payload]);
}

/// Build an EIP-1559 typed transaction prefix: `[0x02, <RLP list>]`.
Uint8List _eip1559Typed(Uint8List rlpList) {
  return Uint8List.fromList([0x02, ...rlpList]);
}

// ═══════════════════════════════════════════════════════════════════════
// Tests — rlpTotalLength
// ═══════════════════════════════════════════════════════════════════════

void main() {
  // ────────────────────────────────────────────────────────────────
  // rlpTotalLength
  // ────────────────────────────────────────────────────────────────

  group('rlpTotalLength', () {
    test('returns -1 for empty bytes', () {
      expect(rlpTotalLength([]), -1);
    });

    test('single byte (0x00–0x7f) → length = 1', () {
      expect(rlpTotalLength([0x00]), 1);
      expect(rlpTotalLength([0x7f]), 1);
      expect(rlpTotalLength([0x42]), 1);
    });

    test('short string (0x80–0xb7) → length = 1 + (first - 0x80)', () {
      // 0x80 = empty string → 1 byte
      expect(rlpTotalLength([0x80]), 1);
      // 0x83 = 3-byte string → 4 bytes total
      expect(rlpTotalLength([0x83, 0xaa, 0xbb, 0xcc]), 4);
      // Partial — only header, still determinable
      expect(rlpTotalLength([0x83]), 4);
    });

    test('long string (0xb8–0xbf) with 1-byte length prefix', () {
      // 0xb8 0x01 → 3 bytes total (header=2, payload=1)
      expect(rlpTotalLength([0xb8, 0x01, 0xaa]), 3);
      // 0xb8 0x10 → 18 bytes total
      final bytes = [0xb8, 0x10, ...List.filled(16, 0x00)];
      expect(rlpTotalLength(bytes), 18);
    });

    test('long string with 2-byte length prefix', () {
      // 0xb9 0x00 0x05 → 8 bytes total (header=3, payload=5)
      expect(rlpTotalLength([0xb9, 0x00, 0x05, 0, 0, 0, 0, 0]), 8);
    });

    test('long string returns -1 if length bytes are incomplete', () {
      // 0xb8 needs 1 length byte but we have 0
      expect(rlpTotalLength([0xb8]), -1);
      // 0xb9 needs 2 length bytes but we have 1
      expect(rlpTotalLength([0xb9, 0x01]), -1);
    });

    test('short list (0xc0–0xf7) → length = 1 + (first - 0xc0)', () {
      // 0xc0 = empty list → 1 byte
      expect(rlpTotalLength([0xc0]), 1);
      // 0xc5 = 5-byte list → 6 bytes total
      expect(rlpTotalLength([0xc5, 0, 0, 0, 0, 0]), 6);
    });

    test('long list (0xf8–0xff) with 1-byte length prefix', () {
      // 0xf8 0x0a → 12 bytes total (header=2, payload=10)
      final bytes = [0xf8, 0x0a, ...List.filled(10, 0x00)];
      expect(rlpTotalLength(bytes), 12);
    });

    test('long list returns -1 if length bytes are incomplete', () {
      expect(rlpTotalLength([0xf8]), -1);
      expect(rlpTotalLength([0xf9, 0x01]), -1);
    });

    test('EIP-1559 typed tx (0x02 prefix) adds 1 to RLP length', () {
      // [0x02, 0xc0] → type(1) + empty_list(1) = 2
      expect(rlpTotalLength([0x02, 0xc0]), 2);
      // [0x02, 0xc5, ...5 bytes] → type(1) + list_header(1) + 5 = 7
      expect(rlpTotalLength([0x02, 0xc5, 0, 0, 0, 0, 0]), 7);
    });

    test('EIP-2930 typed tx (0x01 prefix) adds 1 to RLP length', () {
      // [0x01, 0xc0] → type(1) + empty_list(1) = 2
      expect(rlpTotalLength([0x01, 0xc0]), 2);
    });

    test('typed tx returns -1 if only type byte is present', () {
      expect(rlpTotalLength([0x01]), -1);
      expect(rlpTotalLength([0x02]), -1);
    });

    test('non-typed, non-RLP bytes (0x03) are treated as single byte', () {
      // 0x03 < 0x80 → single byte value
      expect(rlpTotalLength([0x03]), 1);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // EthTxAssembler — single chunk
  // ────────────────────────────────────────────────────────────────

  group('EthTxAssembler single chunk', () {
    test('complete RLP in first chunk produces complete result', () {
      final asm = EthTxAssembler();
      // 5-byte RLP list: [0xc5, 0, 0, 0, 0] → total = 6
      final rlp = _rlpShortList(5);

      final result = asm.handleFirstChunk(
        derivationPath: "m/44'/60'/0'/0/0",
        seedHex: 'test-seed',
        rlpData: rlp,
      );

      expect(result.isComplete, isTrue);
      expect(result.isError, isFalse);
      expect(result.derivationPath, "m/44'/60'/0'/0/0");
      expect(result.seedHex, 'test-seed');
      expect(result.payload, equals(rlp));
      expect(asm.isActive, isFalse,
          reason: 'assembler should be reset after completion');
    });

    test('EIP-1559 typed tx in first chunk produces complete result', () {
      final asm = EthTxAssembler();
      // [0x02, 0xc5, ...5 bytes] → total = 7
      final rlp = _eip1559Typed(_rlpShortList(5));

      final result = asm.handleFirstChunk(
        derivationPath: "m/44'/60'/0'/0/0",
        seedHex: 'test-seed',
        rlpData: rlp,
      );

      expect(result.isComplete, isTrue);
      expect(result.payload, equals(rlp));
      expect(result.payload!.length, 7);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // EthTxAssembler — multiple chunks
  // ────────────────────────────────────────────────────────────────

  group('EthTxAssembler multiple chunks', () {
    test('first chunk incomplete, continuation completes', () {
      final asm = EthTxAssembler();
      // 50-byte RLP list: [0xf8, 0x32, ...50 bytes] → total = 52
      final fullRlp = _rlpLongList(50);
      expect(fullRlp.length, 52);

      // Send only the first 10 bytes in P1=0x00
      final firstChunk = Uint8List.sublistView(fullRlp, 0, 10);
      final r1 = asm.handleFirstChunk(
        derivationPath: "m/44'/60'/0'/0/0",
        seedHex: 'test-seed',
        rlpData: firstChunk,
      );
      expect(r1.isIncomplete, isTrue);
      expect(asm.isActive, isTrue);

      // Send the next 20 bytes in P1=0x80
      final chunk2 = Uint8List.sublistView(fullRlp, 10, 30);
      final r2 = asm.handleContinuation(chunk2);
      expect(r2.isIncomplete, isTrue);
      expect(asm.isActive, isTrue);

      // Send the final 22 bytes in P1=0x80
      final chunk3 = Uint8List.sublistView(fullRlp, 30);
      final r3 = asm.handleContinuation(chunk3);
      expect(r3.isComplete, isTrue);
      expect(r3.payload, equals(fullRlp));
      expect(asm.isActive, isFalse);
    });

    test('incomplete chunks never produce complete result', () {
      final asm = EthTxAssembler();
      final fullRlp = _rlpLongList(50);

      // Send only 5 bytes
      final r1 = asm.handleFirstChunk(
        derivationPath: "m/44'/60'/0'/0/0",
        seedHex: 'test-seed',
        rlpData: Uint8List.sublistView(fullRlp, 0, 5),
      );
      expect(r1.isIncomplete, isTrue);
      expect(r1.isComplete, isFalse);
      expect(r1.payload, isNull);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // EthTxAssembler — orphan continuation
  // ────────────────────────────────────────────────────────────────

  group('EthTxAssembler orphan continuation', () {
    test('P1=0x80 without prior P1=0x00 returns error', () {
      final asm = EthTxAssembler();
      // Fresh assembler — no prior first chunk.
      final result = asm.handleContinuation(Uint8List.fromList([0xc0]));

      expect(result.isError, isTrue);
      expect(result.errorSw, 0x6f00);
      expect(asm.isActive, isFalse);
    });

    test('continuation after reset returns error', () {
      final asm = EthTxAssembler();
      // Start assembly, then reset.
      asm.handleFirstChunk(
        derivationPath: "m/44'/60'/0'/0/0",
        seedHex: 'test-seed',
        rlpData: _rlpShortList(5),
      );
      asm.reset();

      // Orphan continuation after reset.
      final result = asm.handleContinuation(Uint8List.fromList([0xc0]));
      expect(result.isError, isTrue);
      expect(result.errorSw, 0x6f00);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // EthTxAssembler — oversized payload
  // ────────────────────────────────────────────────────────────────

  group('EthTxAssembler oversized payload', () {
    test('extra bytes beyond expected length are truncated', () {
      final asm = EthTxAssembler();
      // 5-byte RLP list → total = 6. Add 4 extra bytes.
      final rlp = _rlpShortList(5); // [0xc5, 0, 0, 0, 0, 0]
      final oversized = Uint8List.fromList([...rlp, 0xFF, 0xFF, 0xFF, 0xFF]);

      final result = asm.handleFirstChunk(
        derivationPath: "m/44'/60'/0'/0/0",
        seedHex: 'test-seed',
        rlpData: oversized,
      );

      expect(result.isComplete, isTrue);
      expect(result.payload!.length, 6,
          reason: 'payload should be truncated to expected length');
      expect(result.payload, equals(rlp),
          reason: 'extra bytes should be discarded');
    });

    test('extra continuation bytes beyond expected are truncated', () {
      final asm = EthTxAssembler();
      // 5-byte list → total = 6.
      final rlp = _rlpShortList(5);

      // Send 3 bytes in first chunk (incomplete).
      asm.handleFirstChunk(
        derivationPath: "m/44'/60'/0'/0/0",
        seedHex: 'test-seed',
        rlpData: Uint8List.sublistView(rlp, 0, 3),
      );

      // Send the remaining 3 bytes + 4 extra bytes.
      final extra = Uint8List.fromList([
        ...rlp.sublist(3), // 3 bytes
        0xFF, 0xFF, 0xFF, 0xFF, // 4 extra bytes
      ]);
      final result = asm.handleContinuation(extra);

      expect(result.isComplete, isTrue);
      expect(result.payload!.length, 6);
      expect(result.payload, equals(rlp));
    });
  });

  // ────────────────────────────────────────────────────────────────
  // EthTxAssembler — replacement / reset
  // ────────────────────────────────────────────────────────────────

  group('EthTxAssembler replacement / reset', () {
    test('new first chunk discards previous incomplete assembly', () {
      final asm = EthTxAssembler();
      // Start a large assembly (50-byte payload, total = 52).
      final rlp1 = _rlpLongList(50);
      asm.handleFirstChunk(
        derivationPath: "m/44'/60'/0'/0/0",
        seedHex: 'seed-1',
        rlpData: Uint8List.sublistView(rlp1, 0, 10),
      );
      expect(asm.isActive, isTrue);

      // New first chunk with a different, complete RLP.
      final rlp2 = _rlpShortList(5); // total = 6
      final result = asm.handleFirstChunk(
        derivationPath: "m/44'/60'/1'/0/0",
        seedHex: 'seed-2',
        rlpData: rlp2,
      );

      expect(result.isComplete, isTrue);
      expect(result.payload, equals(rlp2));
      expect(result.derivationPath, "m/44'/60'/1'/0/0",
          reason: 'new path should replace old path');
      expect(result.seedHex, 'seed-2');
    });

    test('reset clears all state', () {
      final asm = EthTxAssembler();
      // Use an INCOMPLETE RLP so the assembler stays active (a complete
      // RLP would auto-reset the assembler internally).
      final fullRlp = _rlpLongList(50); // total = 52
      asm.handleFirstChunk(
        derivationPath: "m/44'/60'/0'/0/0",
        seedHex: 'test-seed',
        rlpData: Uint8List.sublistView(fullRlp, 0, 10),
      );
      expect(asm.isActive, isTrue);

      asm.reset();

      expect(asm.isActive, isFalse);
      // Orphan continuation after reset.
      final result = asm.handleContinuation(Uint8List.fromList([0xc0]));
      expect(result.isError, isTrue);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // EthTxAssembler — immutable payload
  // ────────────────────────────────────────────────────────────────

  group('EthTxAssembler immutable payload', () {
    test('result payload is a defensive copy — modifying source does '
        'not affect result', () {
      final asm = EthTxAssembler();
      final rlp = Uint8List.fromList([0xc5, 1, 2, 3, 4, 5]);

      final result = asm.handleFirstChunk(
        derivationPath: "m/44'/60'/0'/0/0",
        seedHex: 'test-seed',
        rlpData: rlp,
      );

      // Modify the original bytes.
      rlp[0] = 0xFF;
      rlp[1] = 0xFF;

      // The result's payload should be unaffected.
      expect(result.payload, isNot(equals(rlp)));
      expect(result.payload, equals([0xc5, 1, 2, 3, 4, 5]));
    });

    test('EthAssemblyResult.complete factory makes defensive copy', () {
      final source = Uint8List.fromList([1, 2, 3]);
      final result = EthAssemblyResult.complete(
        derivationPath: 'm',
        seedHex: 's',
        payload: source,
      );

      // Modify source.
      source[0] = 0xFF;

      expect(result.payload, equals([1, 2, 3]),
          reason: 'defensive copy should insulate result from source mutations');
    });
  });

  // ────────────────────────────────────────────────────────────────
  // EthTxAssembler — one confirmation per assembly
  // ────────────────────────────────────────────────────────────────

  group('EthTxAssembler one confirmation', () {
    test('after completion, assembler is reset — further chunks are '
        'orphan errors', () {
      final asm = EthTxAssembler();
      final rlp = _rlpShortList(5); // total = 6

      // First chunk completes the assembly.
      final r1 = asm.handleFirstChunk(
        derivationPath: "m/44'/60'/0'/0/0",
        seedHex: 'test-seed',
        rlpData: rlp,
      );
      expect(r1.isComplete, isTrue);

      // After completion, a continuation should be an orphan error.
      final r2 = asm.handleContinuation(Uint8List.fromList([0xFF]));
      expect(r2.isError, isTrue);
      expect(r2.errorSw, 0x6f00);
    });

    test('only one complete result is produced per assembly', () {
      final asm = EthTxAssembler();
      final rlp = _rlpLongList(50); // total = 52

      // First chunk — incomplete.
      final r1 = asm.handleFirstChunk(
        derivationPath: "m/44'/60'/0'/0/0",
        seedHex: 'test-seed',
        rlpData: Uint8List.sublistView(rlp, 0, 20),
      );
      expect(r1.isIncomplete, isTrue);

      // Second chunk — completes.
      final r2 = asm.handleContinuation(Uint8List.sublistView(rlp, 20));
      expect(r2.isComplete, isTrue);

      // Third chunk — assembler is reset, so this is an orphan.
      final r3 = asm.handleContinuation(Uint8List.fromList([0xFF]));
      expect(r3.isError, isTrue);
    });
  });
}
