/// Unit tests for formatting utilities.
///
/// Covers chainLabel (localized), chainIconAssetPath, weiToEth, weiToGwei.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/generated/l10n/app_localizations.dart';
import 'package:open_ledger_app/utils/formatting.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  // ═════════════════════════════════════════════════════════════════════
  // chainLabel
  // ═════════════════════════════════════════════════════════════════════

  group('chainLabel', () {
    test('every registry chain has a label', () {
      expect(l10n.chainLabel('ethereum'), 'Ethereum');
      expect(l10n.chainLabel('solana'), 'Solana');
      expect(l10n.chainLabel('bitcoin'), 'Bitcoin');
      expect(l10n.chainLabel('tron'), 'Tron');
      expect(l10n.chainLabel('sui'), 'Sui');
    });

    test('pseudo-chains from signing history have their own labels', () {
      expect(l10n.chainLabel('personal_msg'), 'Ethereum — Personal Message');
      expect(l10n.chainLabel('eip712'), 'Ethereum — EIP-712');
    });

    test('unknown chain returns input unchanged', () {
      expect(l10n.chainLabel('cosmos'), 'cosmos');
      expect(l10n.chainLabel(''), '');
    });

    test('labels are localized', () async {
      final zh = await AppLocalizations.delegate.load(const Locale('zh'));
      // Chains with an established native name are translated...
      expect(zh.chainLabel('ethereum'), '以太坊');
      expect(zh.chainLabel('bitcoin'), '比特币');
      // ...while brand names with no common translation stay Latin.
      expect(zh.chainLabel('solana'), 'Solana');
      expect(zh.chainLabel('tron'), 'Tron');
      expect(zh.chainLabel('sui'), 'Sui');
      expect(zh.chainLabel('personal_msg'), 'Ethereum — 个人消息签名');
    });

    test('ja/ko translate the chains they have native names for', () async {
      final ja = await AppLocalizations.delegate.load(const Locale('ja'));
      expect(ja.chainLabel('ethereum'), 'イーサリアム');
      expect(ja.chainLabel('bitcoin'), 'ビットコイン');
      expect(ja.chainLabel('sui'), 'Sui');

      final ko = await AppLocalizations.delegate.load(const Locale('ko'));
      expect(ko.chainLabel('ethereum'), '이더리움');
      expect(ko.chainLabel('bitcoin'), '비트코인');
      expect(ko.chainLabel('sui'), 'Sui');
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  // chainIconAssetPath
  // ═════════════════════════════════════════════════════════════════════

  group('chainIconAssetPath', () {
    test('resolves every registry chain', () {
      expect(chainIconAssetPath('ethereum'), 'assets/icons/chains/eth.svg');
      expect(chainIconAssetPath('solana'), 'assets/icons/chains/sol.svg');
      expect(chainIconAssetPath('bitcoin'), 'assets/icons/chains/btc.svg');
      expect(chainIconAssetPath('tron'), 'assets/icons/chains/tron.svg');
      expect(chainIconAssetPath('sui'), 'assets/icons/chains/sui.svg');
    });

    test('unknown or pseudo ids fall back to the ETH icon', () {
      expect(chainIconAssetPath('cosmos'), 'assets/icons/chains/eth.svg');
      expect(chainIconAssetPath('personal_msg'), 'assets/icons/chains/eth.svg');
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  // weiToEth
  // ═════════════════════════════════════════════════════════════════════

  group('weiToEth', () {
    test('"0" → "0"', () {
      expect(weiToEth('0'), '0');
    });

    test('empty string → "0"', () {
      expect(weiToEth(''), '0');
    });

    test('"1000000000000000000" → "1" (1 ETH)', () {
      expect(weiToEth('1000000000000000000'), '1');
    });

    test('"2000000000000000000" → "2" (2 ETH)', () {
      expect(weiToEth('2000000000000000000'), '2');
    });

    test('"100000000000000000" → "0.1" (0.1 ETH)', () {
      expect(weiToEth('100000000000000000'), '0.1');
    });

    test('"1000000000000000" → "0.001" (0.001 ETH)', () {
      expect(weiToEth('1000000000000000'), '0.001');
    });

    test('trailing zeros are trimmed', () {
      expect(weiToEth('1000000000000000000'), '1');
      expect(weiToEth('2000000000000000000'), '2');
    });

    test('fractional value with significant decimals', () {
      // 1.234567890123456789 ETH
      expect(weiToEth('1234567890123456789'), '1.234567890123456789');
    });

    test('value less than 1 wei with padding', () {
      // 1 wei → 0.000000000000000001 ETH
      expect(weiToEth('1'), '0.000000000000000001');
    });

    test('10 wei → 0.00000000000000001 ETH', () {
      expect(weiToEth('10'), '0.00000000000000001');
    });

    test('very small value preserves all significant digits', () {
      // 123456789012345 wei
      expect(weiToEth('123456789012345'), '0.000123456789012345');
    });

    test('large value with decimals', () {
      // 1.5 ETH
      expect(weiToEth('1500000000000000000'), '1.5');
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  // weiToGwei
  // ═════════════════════════════════════════════════════════════════════

  group('weiToGwei', () {
    test('"0" → "0"', () {
      expect(weiToGwei('0'), '0');
    });

    test('empty string → "0"', () {
      expect(weiToGwei(''), '0');
    });

    test('"1000000000" → "1" (1 Gwei)', () {
      expect(weiToGwei('1000000000'), '1');
    });

    test('"2000000000" → "2" (2 Gwei)', () {
      expect(weiToGwei('2000000000'), '2');
    });

    test('"100000000" → "0.1" (0.1 Gwei)', () {
      expect(weiToGwei('100000000'), '0.1');
    });

    test('"1000000" → "0.001" (0.001 Gwei)', () {
      expect(weiToGwei('1000000'), '0.001');
    });

    test('trailing zeros are trimmed', () {
      expect(weiToGwei('1000000000'), '1');
      expect(weiToGwei('5000000000'), '5');
    });

    test('1 wei → minimal Gwei display', () {
      expect(weiToGwei('1'), '0.000000001');
    });

    test('fractional Gwei value', () {
      expect(weiToGwei('1234567890'), '1.23456789');
    });
  });
}
