import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/models/vault.dart';
import 'package:open_ledger_app/core/models/wallet_accounts.dart';

const _accounts = WalletAccounts(accounts: [], mnemonicFingerprint: 'fp');

Vault _vault({
  VaultSource source = VaultSource.imported,
  int enigmaLanguage = 0,
}) =>
    Vault(
      id: 'v1',
      label: '',
      depth: 0,
      mnemonicEncrypted: 'enc',
      accounts: _accounts,
      createdAt: 42,
      source: source,
      enigmaLanguage: enigmaLanguage,
    );

void main() {
  group('VaultSource wire codec', () {
    test('wire names match the enum', () {
      expect(VaultSource.generated.wire, 'generated');
      expect(VaultSource.imported.wire, 'imported');
      expect(VaultSource.enigma.wire, 'enigma');
    });

    test('fromWire maps known tokens and falls back to imported', () {
      expect(VaultSource.fromWire('generated'), VaultSource.generated);
      expect(VaultSource.fromWire('enigma'), VaultSource.enigma);
      expect(VaultSource.fromWire('imported'), VaultSource.imported);
      expect(VaultSource.fromWire('bogus'), VaultSource.imported);
      expect(VaultSource.fromWire(null), VaultSource.imported);
    });
  });

  group('Vault origin fields (ADR-011 §4)', () {
    test('toJson/fromJson round-trips source + enigmaLanguage', () {
      final vault = _vault(source: VaultSource.enigma, enigmaLanguage: 1);

      final restored = Vault.fromJson(vault.toJson());

      expect(restored.source, VaultSource.enigma);
      expect(restored.enigmaLanguage, 1);
      // The pre-existing fields survive alongside the new ones.
      expect(restored.id, 'v1');
      expect(restored.mnemonicEncrypted, 'enc');
      expect(restored.createdAt, 42);
    });

    test('toJson always includes source + enigmaLanguage', () {
      final json = _vault().toJson();

      expect(json['source'], 'imported');
      expect(json['enigmaLanguage'], 0);
    });

    test('legacy JSON missing both keys defaults to imported / 0', () {
      final legacy = {
        'id': 'legacy',
        'label': '',
        'depth': 0,
        'mnemonicEncrypted': 'enc',
        'accounts': {'accounts': <dynamic>[], 'mnemonicFingerprint': 'fp'},
        'createdAt': 0,
      };

      final restored = Vault.fromJson(legacy);

      expect(restored.source, VaultSource.imported);
      expect(restored.enigmaLanguage, 0);
    });

    test('copyWith overrides source + enigmaLanguage', () {
      final updated = _vault().copyWith(
        source: VaultSource.enigma,
        enigmaLanguage: 2,
      );

      expect(updated.source, VaultSource.enigma);
      expect(updated.enigmaLanguage, 2);
    });

    test('copyWith preserves origin when not overridden', () {
      final updated = _vault(source: VaultSource.generated).copyWith(
        label: 'Renamed',
      );

      expect(updated.label, 'Renamed');
      expect(updated.source, VaultSource.generated);
      expect(updated.enigmaLanguage, 0);
    });
  });
}
