import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_ledger_app/infrastructure/persistence/in_memory_storage.dart';
import 'package:open_ledger_app/infrastructure/persistence/secure_storage.dart';

/// ADR-007: wallet keys move from plaintext `SharedPreferences` into
/// keystore-backed storage exactly once, without losing data.
void main() {
  late InMemoryStorage secure;

  setUp(() {
    secure = InMemoryStorage();
  });

  test('moves every wallet key and removes the plaintext copies', () async {
    SharedPreferences.setMockInitialValues({
      'wallet.salt': 'aabb',
      'wallet.vault.v1': '{"id":"v1"}',
      'wallet.verifier.0': '{"depth":0,"verifier":"ct"}',
      'wallet.pinAttempts': '2',
      'settings.themeMode': 'dark',
    });

    final moved = await LegacyWalletMigration(secure).run();

    expect(moved, 4);
    expect(await secure.getItem('wallet.salt'), 'aabb');
    expect(await secure.getItem('wallet.vault.v1'), '{"id":"v1"}');
    expect(await secure.getItem('wallet.pinAttempts'), '2');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith('wallet.')), isEmpty);
  });

  test('leaves non-wallet settings alone', () async {
    SharedPreferences.setMockInitialValues({'settings.themeMode': 'dark'});

    final moved = await LegacyWalletMigration(secure).run();

    expect(moved, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings.themeMode'), 'dark');
  });

  test('is a no-op on an already-migrated device', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await LegacyWalletMigration(secure).run(), 0);
    expect(await secure.getItem('wallet.salt'), isNull);
  });

  test('a second run after a partial failure re-copies the same values',
      () async {
    SharedPreferences.setMockInitialValues({'wallet.salt': 'aabb'});

    // Copy succeeded but the delete did not (simulated by running again on a
    // device where the key is still present): the write must be idempotent and
    // the value identical.
    await LegacyWalletMigration(secure).run();
    expect(await secure.getItem('wallet.salt'), 'aabb');

    SharedPreferences.setMockInitialValues({'wallet.salt': 'aabb'});
    await LegacyWalletMigration(secure).run();
    expect(await secure.getItem('wallet.salt'), 'aabb');
  });
}
