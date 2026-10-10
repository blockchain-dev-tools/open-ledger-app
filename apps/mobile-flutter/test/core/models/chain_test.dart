/// Unit tests for the chain registry — the single source of truth for chain
/// identity, icons, account-0 derivation paths, and Ledger app identity.
///
/// These lock the values the rest of the app derives from, so a registry edit
/// that would silently change persisted ids, on-wire app names, or account
/// derivation is caught here.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/models/chain.dart';

void main() {
  group('Chain ids', () {
    test('ids are stable — they are persisted in accounts and history', () {
      expect(Chain.values.map((c) => c.id).toList(), [
        'ethereum',
        'solana',
        'bitcoin',
        'tron',
        'sui',
      ]);
    });

    test('fromId resolves every chain and rejects unknown/pseudo ids', () {
      for (final chain in Chain.values) {
        expect(Chain.fromId(chain.id), chain);
      }
      expect(Chain.fromId('cosmos'), isNull);
      expect(Chain.fromId('personal_msg'), isNull);
      expect(Chain.fromId('eip712'), isNull);
      expect(Chain.fromId(''), isNull);
      expect(Chain.fromId(null), isNull);
    });
  });

  group('Chain.defaultAccountPath', () {
    test('matches the product contract (§7 账户与链规则)', () {
      expect(Chain.ethereum.defaultAccountPath, "m/44'/60'/0'/0/0");
      expect(Chain.solana.defaultAccountPath, "m/44'/501'/0'/0'");
      expect(Chain.bitcoin.defaultAccountPath, "m/84'/0'/0'/0/0");
      expect(Chain.tron.defaultAccountPath, "m/44'/195'/0'/0/0");
      expect(Chain.sui.defaultAccountPath, "m/44'/784'/0'/0'/0'");
    });
  });

  group('Chain.iconAssetPath', () {
    test('every chain resolves to a distinct SVG asset', () {
      final paths = Chain.values.map((c) => c.iconAssetPath).toList();
      expect(paths.toSet().length, Chain.values.length);
      for (final path in paths) {
        expect(path, startsWith('assets/icons/chains/'));
        expect(path, endsWith('.svg'));
      }
    });
  });

  group('LedgerApp identity', () {
    test('each chain maps to a distinct app, and back', () {
      final apps = Chain.values.map((c) => c.ledgerApp).toList();
      expect(apps.toSet().length, Chain.values.length);
      for (final chain in Chain.values) {
        expect(chain.ledgerApp.chain, chain);
      }
    });

    test('reports the on-wire app names and versions hosts expect', () {
      expect(LedgerApp.ethereum.ledgerName, 'Ethereum');
      expect(LedgerApp.solana.ledgerName, 'Solana');
      expect(LedgerApp.bitcoin.ledgerName, 'Bitcoin');
      expect(LedgerApp.tron.ledgerName, 'Tron');
      expect(LedgerApp.sui.ledgerName, 'Sui');
      for (final app in LedgerApp.values) {
        expect(app.version, isNotEmpty);
      }
    });

    test('fromLedgerName parses an OPEN_APP payload', () {
      expect(LedgerApp.fromLedgerName('Ethereum'), LedgerApp.ethereum);
      expect(LedgerApp.fromLedgerName('ethereum'), LedgerApp.ethereum);
      expect(LedgerApp.fromLedgerName('  Bitcoin '), LedgerApp.bitcoin);
      expect(LedgerApp.fromLedgerName('Sui'), LedgerApp.sui);
      expect(LedgerApp.fromLedgerName('Tron'), LedgerApp.tron);
      expect(LedgerApp.fromLedgerName('Solana'), LedgerApp.solana);
    });

    test('fromLedgerName rejects unknown or empty names', () {
      expect(LedgerApp.fromLedgerName(''), isNull);
      expect(LedgerApp.fromLedgerName('Cosmos'), isNull);
      expect(LedgerApp.fromLedgerName('BOLOS'), isNull);
    });

    test('dashboard name is the BOLOS marker', () {
      expect(LedgerApp.dashboardName, 'BOLOS');
    });
  });
}
