import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/models/signature_record.dart';

void main() {
  group('SignatureRecord JSON', () {
    test('toJson/fromJson round-trips all fields', () {
      final record = SignatureRecord(
        timestamp: DateTime.parse('2026-09-30T12:34:56.000Z'),
        chain: 'solana',
        derivationPath: "m/44'/501'/0'/0'",
        signingAddress: 'So1anaAddr',
        payloadHex: 'abcdef',
        parsedData: const {'hex': 'abcdef', 'size': 3},
        isApproved: true,
        signatureHex: '1234',
        statusWord: 0x9000,
      );

      final restored = SignatureRecord.fromJson(record.toJson());

      expect(restored.timestamp.toUtc(), record.timestamp.toUtc());
      expect(restored.chain, record.chain);
      expect(restored.derivationPath, record.derivationPath);
      expect(restored.signingAddress, record.signingAddress);
      expect(restored.payloadHex, record.payloadHex);
      expect(restored.parsedData, record.parsedData);
      expect(restored.isApproved, isTrue);
      expect(restored.signatureHex, record.signatureHex);
      expect(restored.statusWord, record.statusWord);
    });

    test('fromJson tolerates null parsedData and signatureHex', () {
      final json = {
        'timestamp': '2026-09-30T12:34:56.000Z',
        'chain': 'bitcoin',
        'derivationPath': "m/84'/0'/0'/0/0",
        'signingAddress': 'bc1qxyz',
        'payloadHex': '00',
        'parsedData': null,
        'isApproved': false,
        'signatureHex': null,
        'statusWord': 0x6985,
      };

      final record = SignatureRecord.fromJson(json);

      expect(record.parsedData, isNull);
      expect(record.signatureHex, isNull);
      expect(record.isApproved, isFalse);
      expect(record.isSuccess, isFalse);
    });
  });
}
