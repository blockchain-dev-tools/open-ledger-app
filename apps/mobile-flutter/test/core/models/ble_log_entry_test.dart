import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ledger_app/core/models/ble_log_entry.dart';
import 'package:open_ledger_app/protocols/apdu/apdu_command_name.dart';
import 'package:open_ledger_app/protocols/apdu/apdu_decoder.dart';

void main() {
  group('apduCommandName', () {
    test('maps known CLA+INS to readable names', () {
      expect(apduCommandName(_b([0xE0, 0x01])), 'GET_VERSION');
      expect(apduCommandName(_b([0xB0, 0x01])), 'GET_APP_AND_VERSION');
      expect(apduCommandName(_b([0xE0, 0x02])), 'GET_PUBKEY');
      expect(apduCommandName(_b([0xE0, 0x04])), 'ETH_SIGN_TX');
      expect(apduCommandName(_b([0xE0, 0x0C])), 'ETH_SIGN_EIP712');
      expect(apduCommandName(_b([0xE0, 0xD8])), 'OPEN_APP');
      expect(apduCommandName(_b([0xE0, 0x05])), 'SOL_GET_ADDR');
    });

    test('falls back to UNKNOWN for unmapped codes', () {
      final name = apduCommandName(_b([0xE0, 0x42]));
      expect(name, contains('UNKNOWN'));
      expect(name, contains('0xE0'));
      expect(name, contains('0x42'));
    });

    // ── EIP-712 command-name regression tests ──────────────────────────
    // The product implements EIP-712 V0 as a single INS 0x0C APDU carrying
    // path + domain hash + struct hash. The two-step 0x0C/0x0D flow is not
    // implemented, so 0x0D must never be mislabeled as a legacy ETH_SIGN_TX.

    test('raw INS 0x0C → ETH_SIGN_EIP712', () {
      expect(apduCommandName(_b([0xE0, 0x0C])), 'ETH_SIGN_EIP712');
    });

    test('unimplemented two-step struct INS 0x0D is UNKNOWN, not ETH_SIGN_TX',
        () {
      final name = apduCommandName(_b([0xE0, 0x0D]));
      expect(name, contains('UNKNOWN'));
      expect(name, isNot(contains('ETH_SIGN_TX')));
    });

    test('raw INS 0x06 → GET_APP_CONFIGURATION', () {
      expect(apduCommandName(_b([0xE0, 0x06])), 'GET_APP_CONFIGURATION');
    });

    test('inline EIP-712 INS 0x04 P1=0x02 → ETH_SIGN_EIP712', () {
      expect(apduCommandName(_b([0xE0, 0x04, 0x02, 0x00, 0x00])),
          'ETH_SIGN_EIP712');
    });

    test('inline EIP-712 INS 0x04 P1=0x42 → ETH_SIGN_EIP712', () {
      expect(apduCommandName(_b([0xE0, 0x04, 0x42, 0x00, 0x00])),
          'ETH_SIGN_EIP712');
    });

    test('INS 0x06 P1=0x42 remains GET_APP_CONFIGURATION', () {
      // Ledger hosts probe app configuration with INS 0x06; P1 is ignored.
      // It must never be treated as a legacy transaction or EIP-712 command.
      expect(apduCommandName(_b([0xE0, 0x06, 0x42, 0x00, 0x00])),
          'GET_APP_CONFIGURATION');
    });
  });

  group('swName', () {
    test('maps known status words', () {
      expect(swName(0x9000), 'SUCCESS');
      expect(swName(0x6985), 'REJECTED');
      expect(swName(0x6400), 'TIMEOUT');
      expect(swName(0x6D00), 'INS_NOT_SUPPORTED');
    });

    test('falls back to SW 0xXXXX for unknown', () {
      expect(swName(0x6ABC), 'SW 0x6ABC');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Command rows — emitted as pending until the response resolves them
  // ═══════════════════════════════════════════════════════════════════

  group('ApduLogDecoder — command params', () {
    test('GET_PUBKEY decodes BIP-32 path and awaits the response', () {
      final d = ApduLogDecoder();
      // E0 02 00 00 15 | 05 8000002C 8000003C 80000000 00000000 00000000
      const line = 'APDU command received: E0 02 00 00 15 05 80 00 00 2C '
          '80 00 00 3C 80 00 00 00 00 00 00 00 00 00 00 00';
      final e = d.decode(line)!;
      expect(e.summary,
          "GET_PUBKEY P1=0x00 P2=0x00 path=44'/60'/0'/0/0  →  …");
      expect(e.detail, startsWith('IN  '));
      expect(e.detail, contains('E0 02 00 00 15'));
      expect(e.status, BleLogStatus.pending);
    });

    test('GET_APP_AND_VERSION has no params', () {
      final d = ApduLogDecoder();
      final e = d.decode('APDU command received: B0 01 00 00 00')!;
      expect(e.summary, 'GET_APP_AND_VERSION  →  …');
      expect(e.status, BleLogStatus.pending);
    });

    test('OPEN_APP decodes app name', () {
      final d = ApduLogDecoder();
      // "Ethereum" = 45 74 68 65 72 65 75 6D
      final e = d.decode('APDU command received: E0 D8 00 00 08 45 74 68 65 '
          '72 65 75 6D')!;
      expect(e.summary, 'OPEN_APP "Ethereum"  →  …');
    });

    test('SOL_GET_ADDR decodes the derivation path', () {
      final d = ApduLogDecoder();
      // 04 8000002C 800001F5 80000000 80000000 = m/44'/501'/0'/0'
      final e = d.decode('APDU command received: E0 05 00 00 11 04 80 00 00 2C '
          '80 00 01 F5 80 00 00 00 80 00 00 00')!;
      expect(e.summary, "SOL_GET_ADDR path=44'/501'/0'/0'  →  …");
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Response rows — collapse onto the pending command row
  // ═══════════════════════════════════════════════════════════════════

  group('ApduLogDecoder — response content (stateful)', () {
    test('GET_APP_AND_VERSION response → app + version', () {
      final d = ApduLogDecoder();
      d.decode('APDU command received: B0 01 00 00 00'); // prime context
      final e = d.decode('APDU response: 01 08 45 74 68 65 72 65 75 6D 06 31 '
          '2E 31 30 2E 33 01 02 90 00')!;
      expect(e.summary, 'GET_APP_AND_VERSION  →  Ethereum 1.10.3 (SUCCESS)');
      expect(e.status, BleLogStatus.success);
      expect(e.detail, contains('IN  B0 01 00 00 00'));
      expect(e.detail, contains('OUT 01 08'));
    });

    test('GET_PUBKEY response → derived address', () {
      final d = ApduLogDecoder();
      d.decode('APDU command received: E0 02 00 00 15 05 80 00 00 2C 80 00 00 '
          '3C 80 00 00 00 00 00 00 00 00 00 00 00'); // prime context
      final e = d.decode(
          'APDU response: 41 04 1A 09 45 79 07 3B 3F 1C ED 91 D9 E8 AA 6F '
          '83 D7 6C 23 DF B2 9E 28 EE 74 B1 1E C8 4F 8C E4 58 8B F2 C8 52 31 '
          '40 E5 C3 C9 C1 25 5C 5B 4B 23 80 48 4A 7F F9 BE AB 8D 44 93 8D 01 '
          '46 63 9B A0 FC EF 28 66 30 34 66 30 30 64 38 30 35 30 41 64 42 39 '
          '35 66 66 32 66 63 38 33 44 37 39 65 39 31 38 37 36 38 66 32 61 35 '
          '32 37 35 90 00')!;
      expect(
          e.summary,
          "GET_PUBKEY P1=0x00 P2=0x00 path=44'/60'/0'/0/0  →  "
          'address=0xf04f00d8050AdB95ff2fc83D79e918768f2a5275 (SUCCESS)');
    });

    test('SOL_GET_ADDR response → base58 address', () {
      final d = ApduLogDecoder();
      d.decode('APDU command received: E0 05 00 00 11 04 80 00 00 2C 80 00 01 '
          'F5 80 00 00 00 80 00 00 00');
      // Bare 32-byte pubkey (no length prefix, as app-solana replies) + 9000.
      final e = d.decode('APDU response: 61 59 5F 7B 3F D3 0D 7B FF 60 5B '
          'F6 F3 10 93 50 57 38 4C C3 98 D1 CD F9 FA 2F 8C FC 38 55 8B A3 90 00')!;
      expect(
          e.summary,
          "SOL_GET_ADDR path=44'/501'/0'/0'  →  "
          '7Z1b92qmpkuMxqXyYLZgbmTToxzq2jZ7J83oVZ12rPbY (SUCCESS)');
      expect(e.status, BleLogStatus.success);
    });

    test('non-success SW is labeled and marked as an error', () {
      final d = ApduLogDecoder();
      d.decode('APDU command received: B0 01 00 00 00');
      final e = d.decode('APDU response: 6D 00')!;
      expect(e.summary, 'GET_APP_AND_VERSION  →  INS_NOT_SUPPORTED');
      expect(e.status, BleLogStatus.error);
      expect(e.level, BleLogLevel.error);
    });

    test('APDU response send error → error status (replaces pending)', () {
      final d = ApduLogDecoder();
      d.decode('APDU command received: B0 01 00 00 00');
      final e = d.decode('⚠ APDU response send error: notify failed')!;
      expect(e.status, BleLogStatus.error);
      expect(e.summary, contains('APDU response error'));
      expect(e.summary, contains('notify failed'));
    });
  });

  group('ApduLogDecoder — EIP-712 flow', () {
    // BIP-32 path: 44'/60'/0'/0/0 → 05 8000002C 8000003C 80000000 00000000 00000000
    const pathHex =
        '05 80 00 00 2C 80 00 00 3C 80 00 00 00 00 00 00 00 00 00 00 00';

    /// 32-byte hash as space-delimited uppercase hex.
    String hashHex(String byteHex) => List.filled(32, byteHex).join(' ');

    test('single-step INS 0x0C shows EIP-712 label with both hashes', () {
      final d = ApduLogDecoder();

      // E0 0C 00 00 LC(0x55) path(21B) + domainHash(32B) + structHash(32B)
      final line = 'APDU command received: E0 0C 00 00 55 $pathHex '
          '${hashHex('AA')} ${hashHex('BB')}';
      final entry = d.decode(line)!;
      expect(entry.summary, contains('ETH_SIGN_EIP712'));
      expect(entry.summary, isNot(contains('ETH_SIGN_TX')));
      expect(entry.summary, contains("path=44'/60'/0'/0/0"));
      expect(entry.summary, contains('hash=64 bytes'));
      expect(entry.status, BleLogStatus.pending);
    });

    test('single-step 0x0C response decodes v/r/s', () {
      final d = ApduLogDecoder();
      d.decode('APDU command received: E0 0C 00 00 55 $pathHex '
          '${hashHex('AA')} ${hashHex('BB')}');

      // Signature: 65-byte v||r||s + 90 00.
      final sigBytes = List.filled(65, 'CC').join(' ');
      final entry = d.decode('APDU response: $sigBytes 90 00')!;
      expect(entry.summary, contains('v='));
      expect(entry.summary, contains('r=0x'));
      expect(entry.summary, contains('s=0x'));
      expect(entry.summary, contains('SUCCESS'));
    });

    test('GET_APP_CONFIGURATION response decodes flags and version', () {
      final d = ApduLogDecoder();
      d.decode('APDU command received: E0 06 00 00 00');
      final entry = d.decode('APDU response: 01 01 0A 03 90 00')!;
      expect(entry.summary,
          'GET_APP_CONFIGURATION  →  4 bytes: 01010a03 (SUCCESS)');
    });

    test('inline EIP-712 via INS 0x04 P1=0x42 → ETH_SIGN_EIP712', () {
      final d = ApduLogDecoder();
      final inlineLine = 'APDU command received: E0 04 42 00 55 $pathHex '
          '${hashHex('AA')} ${hashHex('BB')}';
      final entry = d.decode(inlineLine)!;
      expect(entry.summary, contains('ETH_SIGN_EIP712'));
      expect(entry.summary, isNot(contains('ETH_SIGN_TX')));
    });
  });

  group('ApduLogDecoder — hidden chatter & other lines', () {
    test('fragment-level lines are dropped (null)', () {
      final d = ApduLogDecoder();
      expect(d.decode('GATT write: E0 05 00 00 11 04'), isNull);
      expect(d.decode('APDU incoming: total_len=22, seq=0, 11 bytes'), isNull);
    });

    test('non-APDU lines are plain and non-expandable', () {
      final d = ApduLogDecoder();
      const line = 'BLE state → connected';
      final e = d.decode(line)!;
      expect(e.summary, line);
      expect(e.detail, isNull);
    });

    test('⚠ prefix sets warn level', () {
      final d = ApduLogDecoder();
      expect(d.decode('⚠ Advertising start failed: code=1')!.level,
          BleLogLevel.warn);
    });
  });
}

Uint8List _b(List<int> bytes) => Uint8List.fromList(bytes);
