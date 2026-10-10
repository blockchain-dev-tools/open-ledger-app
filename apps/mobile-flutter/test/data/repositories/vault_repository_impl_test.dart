import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/models/vault.dart';
import 'package:open_ledger_app/core/models/wallet_accounts.dart';
import 'package:open_ledger_app/data/repositories/vault_repository_impl.dart';
import 'package:open_ledger_app/infrastructure/persistence/in_memory_storage.dart';

Vault _vault(String id, int depth, {String label = ''}) => Vault(
      id: id,
      label: label,
      depth: depth,
      mnemonicEncrypted: 'enc-$id',
      accounts: WalletAccounts(
        accounts: const [],
        mnemonicFingerprint: 'fp-$id',
      ),
      createdAt: 1730000000000,
    );

void main() {
  late InMemoryStorage storage;
  late VaultRepositoryImpl repo;

  setUp(() {
    storage = InMemoryStorage();
    repo = VaultRepositoryImpl(storage);
  });

  group('existence', () {
    test('fresh device has no wallet', () async {
      expect(await repo.hasWallet(), isFalse);
    });

    test('any tier credential reports hasWallet', () async {
      await repo.setCredential(
        const WalletCredential(depth: 1, verifier: 'v1'),
      );
      expect(await repo.hasWallet(), isTrue);
    });

    test('a device salt alone does not count as a wallet', () async {
      await repo.setDeviceSalt('salt-hex');
      expect(await repo.hasWallet(), isFalse);
    });
  });

  group('device salt', () {
    test('is unset on a fresh device', () async {
      expect(await repo.getDeviceSalt(), isNull);
    });

    test('round-trips', () async {
      await repo.setDeviceSalt('salt-hex');
      expect(await repo.getDeviceSalt(), 'salt-hex');
    });
  });

  group('vault crud', () {
    test('saveVault adds to the index; deleteVault removes it', () async {
      await repo.saveVault(_vault('v1', 0));
      await repo.saveVault(_vault('v2', 1));
      expect(await repo.getVaultIds(), ['v1', 'v2']);

      await repo.saveVault(_vault('v1', 0, label: 'renamed'));
      expect(await repo.getVaultIds(), ['v1', 'v2']);
      expect((await repo.getVault('v1'))!.label, 'renamed');

      await repo.deleteVault('v1');
      expect(await repo.getVaultIds(), ['v2']);
      expect(await repo.getVault('v1'), isNull);
    });

    test('listVaults filters by depth', () async {
      await repo.saveVault(_vault('v1', 0));
      await repo.saveVault(_vault('v2', 0));
      await repo.saveVault(_vault('v3', 1));

      expect((await repo.listVaults(depth: 0)), hasLength(2));
      expect((await repo.listVaults(depth: 1)), hasLength(1));
      expect(await repo.listVaults(), hasLength(3));
    });

    test('deleteVaultsAtDepth removes only that tier', () async {
      await repo.saveVault(_vault('v1', 0));
      await repo.saveVault(_vault('v2', 1));
      await repo.saveVault(_vault('v3', 1));

      await repo.deleteVaultsAtDepth(1);

      expect(await repo.getVaultIds(), ['v1']);
      expect((await repo.listVaults(depth: 0)), hasLength(1));
      expect(await repo.listVaults(depth: 1), isEmpty);
    });
  });

  group('credentials', () {
    test('round-trips multiple tiers', () async {
      await repo.setCredential(
          const WalletCredential(depth: 0, verifier: 'v0'));
      await repo.setCredential(
          const WalletCredential(depth: 1, verifier: 'v1'));

      expect((await repo.getCredential(0))!.verifier, 'v0');
      expect((await repo.getCredential(1))!.verifier, 'v1');
      expect(await repo.listCredentialDepths(), [0, 1]);
    });

    test('a tier credential is null when not configured', () async {
      expect(await repo.getCredential(1), isNull);
    });

    test('deleteCredential drops only that tier', () async {
      await repo.setCredential(
          const WalletCredential(depth: 0, verifier: 'v0'));
      await repo.setCredential(
          const WalletCredential(depth: 1, verifier: 'v1'));

      await repo.deleteCredential(1);

      expect(await repo.getCredential(1), isNull);
      expect(await repo.getCredential(0), isNotNull);
      expect(await repo.listCredentialDepths(), [0]);
    });
  });

  group('stand-in mode', () {
    test('defaults to hide', () async {
      expect(await repo.getStandInMode(1), StandInMode.hide);
    });

    test('round-trips wipe', () async {
      await repo.setStandInMode(1, StandInMode.wipe);
      expect(await repo.getStandInMode(1), StandInMode.wipe);
    });

    test('is per tier', () async {
      await repo.setStandInMode(1, StandInMode.wipe);
      expect(await repo.getStandInMode(2), StandInMode.hide);
    });
  });

  group('clearing', () {
    test('clearAll wipes every tier, credential and the device salt', () async {
      await repo.setDeviceSalt('salt-hex');
      await repo.setCredential(
          const WalletCredential(depth: 0, verifier: 'v0'));
      await repo.setCredential(
          const WalletCredential(depth: 1, verifier: 'v1'));
      await repo.saveVault(_vault('n1', 0));
      await repo.saveVault(_vault('h1', 1));
      await repo.setStandInMode(1, StandInMode.wipe);
      await repo.setPinAttempts(3);

      await repo.clearAll();

      expect(await repo.getVaultIds(), isEmpty);
      expect(await repo.getCredential(0), isNull);
      expect(await repo.getCredential(1), isNull);
      expect(await repo.getDeviceSalt(), isNull);
      expect(await repo.getStandInMode(1), StandInMode.hide);
      expect(await repo.getPinAttempts(), 0);
      expect(await repo.hasWallet(), isFalse);
    });
  });
}
