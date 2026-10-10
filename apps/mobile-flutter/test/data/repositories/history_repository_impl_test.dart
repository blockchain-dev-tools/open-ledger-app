import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/models/signature_record.dart';
import 'package:open_ledger_app/data/repositories/history_repository_impl.dart';
import 'package:open_ledger_app/infrastructure/persistence/in_memory_storage.dart';

import '../../support/fake_crypto_service.dart';

void main() {
  late InMemoryStorage storage;
  late HistoryRepositoryImpl repo;

  setUp(() {
    storage = InMemoryStorage();
    repo = HistoryRepositoryImpl(storage, const FakeCryptoService());
  });

  SignatureRecord makeRecord({bool approved = true}) => SignatureRecord(
        timestamp: DateTime.parse('2026-09-30T12:34:56.000Z'),
        chain: 'ethereum',
        derivationPath: "m/44'/60'/0'/0/0",
        signingAddress: '0xABCDEF',
        payloadHex: 'deadbeef',
        parsedData: const {'to': '0x1111', 'value': '42'},
        isApproved: approved,
        signatureHex: approved ? 'cafe' : null,
        statusWord: approved ? 0x9000 : 0x6985,
      );

  group('HistoryRepositoryImpl', () {
    test('load returns empty list when nothing is stored', () async {
      expect(await repo.load('v1', 'seed'), isEmpty);
    });

    test('save then load round-trips all fields', () async {
      await repo.save([makeRecord(), makeRecord(approved: false)], 'v1', 'seed');

      final loaded = await repo.load('v1', 'seed');

      expect(loaded.length, 2);
      expect(loaded.first.chain, 'ethereum');
      expect(loaded.first.derivationPath, "m/44'/60'/0'/0/0");
      expect(loaded.first.signingAddress, '0xABCDEF');
      expect(loaded.first.payloadHex, 'deadbeef');
      expect(loaded.first.parsedData?['to'], '0x1111');
      expect(loaded.first.timestamp.toUtc(),
          DateTime.parse('2026-09-30T12:34:56.000Z'));
      expect(loaded.first.signatureHex, 'cafe');
      expect(loaded.first.isSuccess, isTrue);

      expect(loaded.last.isApproved, isFalse);
      expect(loaded.last.signatureHex, isNull);
      expect(loaded.last.statusWord, 0x6985);
    });

    test('one vault cannot read or overwrite another vault history', () async {
      await repo.save([makeRecord()], 'v1', 'seed-a');

      await repo.save([makeRecord(), makeRecord(approved: false)], 'v2', 'seed-b');

      // v1 keeps its own record instead of being clobbered by v2's save.
      expect((await repo.load('v1', 'seed-a')).length, 1);
      expect((await repo.load('v2', 'seed-b')).length, 2);
    });

    test('load returns empty list when stored data is corrupt', () async {
      await storage.setItem('wallet.signHistory', 'not-json');
      expect(await repo.load('v1', 'seed'), isEmpty);
    });

    test('clear removes persisted history for every vault', () async {
      await repo.save([makeRecord()], 'v1', 'seed-a');
      await repo.save([makeRecord()], 'v2', 'seed-b');
      await repo.clear();
      expect(await repo.load('v1', 'seed-a'), isEmpty);
      expect(await repo.load('v2', 'seed-b'), isEmpty);
    });

    test('removeVaults drops only the named vaults', () async {
      await repo.save([makeRecord()], 'v1', 'seed-a');
      await repo.save([makeRecord(), makeRecord(approved: false)], 'v2', 'seed-b');

      await repo.removeVaults({'v1'});

      expect(await repo.load('v1', 'seed-a'), isEmpty);
      expect((await repo.load('v2', 'seed-b')).length, 2);
    });

    test('removeVaults drops the storage key once the last vault is gone',
        () async {
      await repo.save([makeRecord()], 'v1', 'seed-a');

      await repo.removeVaults({'v1'});

      expect(await storage.getItem('wallet.signHistory'), isNull);
    });

    test('removeVaults is a no-op for empty or unknown ids', () async {
      await repo.save([makeRecord()], 'v1', 'seed-a');

      await repo.removeVaults(const <String>{});
      await repo.removeVaults({'nope'});

      expect((await repo.load('v1', 'seed-a')).length, 1);
    });
  });
}
