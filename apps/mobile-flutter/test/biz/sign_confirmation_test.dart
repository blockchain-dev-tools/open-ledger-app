/// Unit tests for [SignConfirmation].
///
/// Covers parking a chain-host review, approve / reject, the timeout
/// backstops, supersede, history persistence, address confirmation, and
/// dispose.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/biz/sign_confirmation.dart';
import 'package:open_ledger_app/core/interfaces/crypto_service.dart';
import 'package:open_ledger_app/core/interfaces/history_repository.dart';
import 'package:open_ledger_app/core/models/signature_record.dart';
import 'package:open_ledger_app/protocols/apdu/apdu_constants.dart';
import '../support/inert_export.dart';
import '../support/inert_key_hierarchy.dart';

// ═══════════════════════════════════════════════════════════════════════
// Hand-written Mocks
// ═══════════════════════════════════════════════════════════════════════

/// Configurable mock of [ICryptoService] for SignConfirmation tests.
class _MockCryptoService with InertKeyHierarchy, InertExport implements ICryptoService {
  String? hexEncodeResult;

  final List<Uint8List> hexEncodeCalls = [];

  @override
  String hexEncode(Uint8List bytes) {
    hexEncodeCalls.add(bytes);
    return hexEncodeResult ?? 'hex-encoded';
  }

  // ── Unused ─────────────────────────────────────────────────────────

  @override String? deriveEthAddress(String s, String p) => throw UnimplementedError();
  @override String? deriveSolAddress(String s, String p) => throw UnimplementedError();
  @override String? deriveBtcAddress(String s, String p) => throw UnimplementedError();
  @override String? deriveTronAddress(String s, String p) => throw UnimplementedError();
  @override String? deriveSuiAddress(String s, String p) => throw UnimplementedError();
  @override String? deriveNearAddress(String s, String p) => throw UnimplementedError();
  @override String? deriveTonAddress(String s, String p) => throw UnimplementedError();
  @override String? parseSignData(String c, String p) => throw UnimplementedError();
  @override String generateMnemonic({int strength = 128}) => throw UnimplementedError();
  @override bool validateMnemonic(String m) => throw UnimplementedError();
  @override String reencodeMnemonic(String m) => throw UnimplementedError();
  @override String? generateMnemonicLang({int strength = 128, required int language}) => throw UnimplementedError();
  @override bool validateMnemonicLang(String m, int l) => throw UnimplementedError();
  @override Uint8List? deriveSecp256k1PrivateKey(String s, String p) => throw UnimplementedError();
  @override Uint8List? deriveSecp256k1Extended(String s, String p) => throw UnimplementedError();
  @override Uint8List? deriveEd25519PrivateKey(String s, String p) => throw UnimplementedError();
  @override Uint8List? signEthTransaction(String k, String r) => throw UnimplementedError();
  @override Uint8List? signEthPersonalMessage(String k, String m) => throw UnimplementedError();
  @override Uint8List? signEthEIP712(String k, String d, String s) => throw UnimplementedError();
  @override Uint8List? signSolanaMessage(String k, String m) => throw UnimplementedError();
  @override String? ethAddressFromPrivateKey(String k) => throw UnimplementedError();
  @override Uint8List? ethPublicKeyBytes(String k) => throw UnimplementedError();
  @override Uint8List? solanaPublicKeyBytes(String k) => throw UnimplementedError();
  @override String? p2wpkhAddress(String k) => throw UnimplementedError();
  @override String? tronAddressFromPubkey(String k) => throw UnimplementedError();
  @override String? suiAddress(String k) => throw UnimplementedError();
  @override String? enigmaDeriveMnemonic(String r, String s, int l) => throw UnimplementedError();
  @override String? enigmaEntropyHex(String r, String s, int l) => throw UnimplementedError();
  @override String? mnemonicFromEntropy(String e, int l) => throw UnimplementedError();
  @override String? pbkdf2Derive(String p, String s, int k) => throw UnimplementedError();
  @override String? mnemonicToSeed(String m, {String passphrase = ''}) => throw UnimplementedError();
  @override String? chacha20Encrypt(String p, String pi, String s) => throw UnimplementedError();
  @override String? chacha20Decrypt(String c, String pi, String s) => throw UnimplementedError();
  @override String? historyEncrypt(String p, String s) => throw UnimplementedError();
  @override String? historyDecrypt(String c, String s) => throw UnimplementedError();
  @override bool constantTimeEquals(String a, String b) => a == b;
  @override Uint8List hexToBytes(String h) => throw UnimplementedError();
}

/// In-memory [IHistoryRepository] capturing saves for assertions.
class _FakeHistoryRepository implements IHistoryRepository {
  List<SignatureRecord>? saved;
  String? savedSeed;
  String? savedVaultId;
  int saveCalls = 0;
  bool cleared = false;
  final List<String> removedVaultIds = [];

  @override
  Future<List<SignatureRecord>> load(String vaultId, String seedHex) async =>
      const [];

  @override
  Future<void> save(
      List<SignatureRecord> records, String vaultId, String seedHex) async {
    saved = records;
    savedSeed = seedHex;
    savedVaultId = vaultId;
    saveCalls++;
  }

  @override
  Future<void> removeVaults(Iterable<String> vaultIds) async {
    removedVaultIds.addAll(vaultIds);
  }

  @override
  Future<void> clear() async {
    cleared = true;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════

/// Park an Ethereum transaction review, as the Rust module would report it.
Future<bool> _parkSign(SignConfirmation sc, {String? seedHex}) {
  return sc.interceptChainReview(
    reviewId: 1,
    chain: 'eth_tx',
    derivationPath: "m/44'/60'/0'/0/0",
    signingAddress: '0xabc123',
    payloadHex: 'f86c',
    parsedData: const {'to': '0xdef'},
    seedHex: seedHex,
  );
}

/// Park an address-display review.
Future<bool> _parkAddress(SignConfirmation sc,
    {String address = '0xabc123', int reviewId = 1}) {
  return sc.interceptAddressCommand(
    address,
    "m/44'/60'/0'/0/0",
    chainReviewId: reviewId,
  );
}

// ═══════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════

void main() {
  late _MockCryptoService crypto;
  late SignConfirmation sc;

  setUp(() {
    crypto = _MockCryptoService();
    sc = SignConfirmation(crypto: crypto);
  });

  // ──────────────────────────────────────────────────────────────────
  // Interception
  // ──────────────────────────────────────────────────────────────────

  group('interceptChainReview', () {
    test('parks the review and triggers onRequestPending', () async {
      bool pendingCalled = false;
      sc.onRequestPending = () => pendingCalled = true;

      final result = await _parkSign(sc);

      expect(result, isTrue);
      expect(pendingCalled, isTrue);
      final req = sc.pendingRequest!;
      expect(req.chain, 'eth_tx');
      expect(req.chainReviewId, 1);
      expect(req.derivationPath, "m/44'/60'/0'/0/0");
      expect(req.signingAddress, '0xabc123');
      expect(req.payloadHex, 'f86c');
      expect(req.parsedData!['to'], '0xdef');
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // Resolution — approve / reject / timeout
  // ──────────────────────────────────────────────────────────────────

  group('approve', () {
    test('calls sign callback and stores result', () async {
      await _parkSign(sc);

      bool resolvedCalled = false;
      sc.onRequestResolved = () => resolvedCalled = true;

      final responseBytes = Uint8List.fromList([0x01, 0x02, 0x90, 0x00]);

      await sc.approve(() async => responseBytes);

      expect(sc.pendingRequest, isNull);
      expect(resolvedCalled, isTrue);
      expect(sc.lastSignResult, isNotNull);
      expect(sc.lastSignResult!['isSuccess'], isTrue);
      expect(sc.lastSignResult!['chain'], 'eth_tx');
      expect(sc.history.single.isApproved, isTrue);
    });

    test('no-op when no pending request', () async {
      bool resolvedCalled = false;
      sc.onRequestResolved = () => resolvedCalled = true;

      await sc.approve(() async => Uint8List(0));

      expect(resolvedCalled, isFalse);
    });
  });

  group('reject', () {
    test('clears pending and calls sendError, triggers onRequestResolved',
        () async {
      await _parkSign(sc);

      bool resolvedCalled = false;
      bool errorSent = false;
      sc.onRequestResolved = () => resolvedCalled = true;

      await sc.reject(() async {
        errorSent = true;
        return Uint8List(0);
      });

      expect(sc.pendingRequest, isNull);
      expect(resolvedCalled, isTrue);
      expect(errorSent, isTrue);
      expect(sc.history.single.statusWord, 0x6985);
    });

    test('swallows errors from sendError callback', () async {
      await _parkSign(sc);

      bool resolvedCalled = false;
      sc.onRequestResolved = () => resolvedCalled = true;

      // Should not throw
      await sc.reject(() => throw Exception('send failed'));

      expect(sc.pendingRequest, isNull);
      expect(resolvedCalled, isTrue);
    });
  });

  group('sign backstop', () {
    test('answers SW_TIMEOUT, clears pending and triggers onRequestResolved',
        () async {
      await _parkSign(sc);
      expect(sc.pendingRequest, isNotNull);

      int? sentSw;
      bool resolvedCalled = false;
      sc.sendTerminalStatus = (sw) async => sentSw = sw;
      sc.onRequestResolved = () => resolvedCalled = true;

      await sc.onSignBackstopTimeout();

      expect(sentSw, Sw.executionError);
      expect(sc.pendingRequest, isNull);
      expect(resolvedCalled, isTrue);
      expect(sc.history.single.statusWord, Sw.executionError);
    });

    test('is a no-op once the user already rejected', () async {
      await _parkSign(sc);
      await sc.reject(() async => Uint8List(0));

      int? sentSw;
      sc.sendTerminalStatus = (sw) async => sentSw = sw;

      await sc.onSignBackstopTimeout();

      expect(sentSw, isNull);
    });
  });

  group('cancelPending', () {
    test('drops a pending sign request and notifies', () async {
      await _parkSign(sc);

      bool resolvedCalled = false;
      sc.onRequestResolved = () => resolvedCalled = true;

      expect(sc.cancelPending(), isTrue);
      expect(sc.pendingRequest, isNull);
      expect(resolvedCalled, isTrue);
    });

    test('drops a pending address request and notifies', () async {
      await _parkAddress(sc);

      bool resolvedCalled = false;
      sc.onAddressRequestResolved = () => resolvedCalled = true;

      expect(sc.cancelPending(), isTrue);
      expect(sc.pendingAddressRequest, isNull);
      expect(resolvedCalled, isTrue);
    });

    test('is a no-op when nothing is pending', () {
      bool resolvedCalled = false;
      sc.onRequestResolved = () => resolvedCalled = true;

      expect(sc.cancelPending(), isFalse);
      expect(resolvedCalled, isFalse);
    });
  });

  group('clearLastSignResult', () {
    test('clears the last sign result', () async {
      await _parkSign(sc);
      await sc.approve(() async => Uint8List.fromList([0x90, 0x00]));
      expect(sc.lastSignResult, isNotNull);

      sc.clearLastSignResult();

      expect(sc.lastSignResult, isNull);
    });
  });

  group('dispose', () {
    test('clears all state', () async {
      await _parkSign(sc);
      await sc.approve(() async => Uint8List.fromList([0x90, 0x00]));

      sc.dispose();

      expect(sc.pendingRequest, isNull);
      expect(sc.lastSignResult, isNull);
      expect(sc.history, isEmpty);
    });
  });

  group('history persistence', () {
    SignatureRecord record(String chain) => SignatureRecord(
          timestamp: DateTime.now(),
          chain: chain,
          derivationPath: "m/44'/60'/0'/0/0",
          signingAddress: 'addr',
          payloadHex: '00',
          isApproved: true,
          statusWord: 0x9000,
        );

    test('hydrate replaces in-memory history', () {
      sc.hydrate([record('ethereum'), record('solana')]);
      expect(sc.history.length, 2);
      expect(sc.history.first.chain, 'ethereum');
    });

    test('clearHistory empties in-memory history only', () {
      sc.hydrate([record('ethereum')]);
      sc.clearHistory();
      expect(sc.history, isEmpty);
    });

    test('reject persists a record with the request seed', () async {
      final repo = _FakeHistoryRepository();
      sc.attachHistoryRepository(repo);
      sc.historyVaultId = () => 'v1';

      await _parkSign(sc, seedHex: 'seed-hex');
      await sc.reject(() async => Uint8List.fromList([0x69, 0x85]));
      await Future<void>.delayed(Duration.zero);

      expect(repo.saveCalls, 1);
      expect(repo.savedSeed, 'seed-hex');
      expect(repo.savedVaultId, 'v1');
      expect(repo.saved, isNotNull);
      expect(repo.saved!.length, 1);
      expect(repo.saved!.single.isApproved, isFalse);
      expect(repo.saved!.single.statusWord, 0x6985);
    });

    test('skips persistence when no vault is in scope', () async {
      final repo = _FakeHistoryRepository();
      sc.attachHistoryRepository(repo);

      await _parkSign(sc, seedHex: 'seed-hex');
      await sc.reject(() async => Uint8List.fromList([0x69, 0x85]));
      await Future<void>.delayed(Duration.zero);

      // Records stay in memory rather than landing in another vault's slot.
      expect(repo.saveCalls, 0);
      expect(sc.history.length, 1);
    });

    test('caps history at maxHistoryRecords', () async {
      final repo = _FakeHistoryRepository();
      sc.attachHistoryRepository(repo);
      sc.historyVaultId = () => 'v1';

      sc.hydrate(List.generate(
          SignConfirmation.maxHistoryRecords + 10, (i) => record('chain$i')));
      expect(sc.history.length, SignConfirmation.maxHistoryRecords + 10);

      await _parkSign(sc, seedHex: 'seed-hex');
      await sc.reject(() async => Uint8List.fromList([0x69, 0x85]));
      await Future<void>.delayed(Duration.zero);

      expect(sc.history.length, SignConfirmation.maxHistoryRecords);
      expect(repo.saved!.length, SignConfirmation.maxHistoryRecords);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // Address display + confirm
  // ──────────────────────────────────────────────────────────────────

  group('address confirmation', () {
    test('interceptAddressCommand stores a pending request and notifies',
        () async {
      bool pendingCalled = false;
      sc.onAddressRequestPending = () => pendingCalled = true;

      final result = await _parkAddress(sc, reviewId: 9);

      expect(result, isTrue);
      expect(pendingCalled, isTrue);
      expect(sc.pendingAddressRequest, isNotNull);
      expect(sc.pendingAddressRequest!.address, '0xabc123');
      expect(sc.pendingAddressRequest!.derivationPath, "m/44'/60'/0'/0/0");
      expect(sc.pendingAddressRequest!.chain, 'ethereum');
      expect(sc.pendingAddressRequest!.chainReviewId, 9);
    });

    test('interceptAddressCommand returns false for an empty address', () async {
      final result = await _parkAddress(sc, address: '');

      expect(result, isFalse);
      expect(sc.pendingAddressRequest, isNull);
    });

    test('approveAddress responds then clears the pending request', () async {
      await _parkAddress(sc);

      bool resolvedCalled = false;
      bool responded = false;
      sc.onAddressRequestResolved = () => resolvedCalled = true;

      await sc.approveAddress(() async {
        responded = true;
        return Uint8List.fromList([0x90, 0x00]);
      });

      expect(responded, isTrue);
      expect(resolvedCalled, isTrue);
      expect(sc.pendingAddressRequest, isNull);
    });

    test('rejectAddress sends the error then clears the pending request',
        () async {
      await _parkAddress(sc);

      bool resolvedCalled = false;
      bool errorSent = false;
      sc.onAddressRequestResolved = () => resolvedCalled = true;

      await sc.rejectAddress(() async {
        errorSent = true;
        return Uint8List.fromList([0x69, 0x85]);
      });

      expect(errorSent, isTrue);
      expect(resolvedCalled, isTrue);
      expect(sc.pendingAddressRequest, isNull);
    });

    test('rejectAddress swallows errors from the send callback', () async {
      await _parkAddress(sc);

      bool resolvedCalled = false;
      sc.onAddressRequestResolved = () => resolvedCalled = true;

      await sc.rejectAddress(() => throw Exception('send failed'));

      expect(sc.pendingAddressRequest, isNull);
      expect(resolvedCalled, isTrue);
    });

    test('approveAddress / rejectAddress are no-ops without a pending request',
        () async {
      bool responded = false;
      bool resolvedCalled = false;
      sc.onAddressRequestResolved = () => resolvedCalled = true;

      await sc.approveAddress(() async {
        responded = true;
        return Uint8List(0);
      });
      await sc.rejectAddress(() async {
        responded = true;
        return Uint8List(0);
      });

      expect(responded, isFalse);
      expect(resolvedCalled, isFalse);
    });

    test('address backstop answers SW_TIMEOUT and clears the request', () async {
      await _parkAddress(sc);

      int? sentSw;
      bool resolvedCalled = false;
      sc.sendTerminalStatus = (sw) async => sentSw = sw;
      sc.onAddressRequestResolved = () => resolvedCalled = true;

      await sc.onAddressBackstopTimeout();

      expect(sentSw, Sw.executionError);
      expect(sc.pendingAddressRequest, isNull);
      expect(resolvedCalled, isTrue);
    });

    test('address backstop is a no-op after the user rejected', () async {
      await _parkAddress(sc);
      await sc.rejectAddress(() async => Uint8List.fromList([0x69, 0x85]));

      int? sentSw;
      sc.sendTerminalStatus = (sw) async => sentSw = sw;

      await sc.onAddressBackstopTimeout();

      expect(sentSw, isNull);
    });

    testWidgets('backstop fires after the configured duration', (tester) async {
      final backstopped = SignConfirmation(
        crypto: crypto,
        confirmationBackstop: const Duration(seconds: 5),
      );
      addTearDown(backstopped.dispose);

      await _parkAddress(backstopped);

      int? sentSw;
      backstopped.sendTerminalStatus = (sw) async => sentSw = sw;

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();

      expect(sentSw, Sw.executionError);
      expect(backstopped.pendingAddressRequest, isNull);
    });

    testWidgets('resolving first cancels the backstop', (tester) async {
      final backstopped = SignConfirmation(
        crypto: crypto,
        confirmationBackstop: const Duration(seconds: 5),
      );
      addTearDown(backstopped.dispose);

      await _parkAddress(backstopped);

      int? sentSw;
      backstopped.sendTerminalStatus = (sw) async => sentSw = sw;

      await tester.pump(const Duration(seconds: 2));
      await backstopped
          .rejectAddress(() async => Uint8List.fromList([0x69, 0x85]));
      await tester.pump(const Duration(seconds: 10));

      expect(sentSw, isNull);
      expect(backstopped.pendingAddressRequest, isNull);
    });

    test('a new request answers the superseded one', () async {
      await _parkAddress(sc, address: '0xold', reviewId: 1);

      final sent = <int>[];
      bool resolvedCalled = false;
      sc.sendTerminalStatus = (sw) async => sent.add(sw);
      sc.onAddressRequestResolved = () => resolvedCalled = true;

      await _parkAddress(sc, address: '0xnew', reviewId: 2);

      expect(sent, [Sw.conditionsNotSatisfied]);
      expect(resolvedCalled, isTrue);
      expect(sc.pendingAddressRequest!.address, '0xnew');
      expect(sc.pendingAddressRequest!.chainReviewId, 2);
    });

    test('a sign request supersedes a pending address request', () async {
      await _parkAddress(sc);

      int? sentSw;
      bool addressResolved = false;
      sc.sendTerminalStatus = (sw) async => sentSw = sw;
      sc.onAddressRequestResolved = () => addressResolved = true;

      await _parkSign(sc);

      expect(sentSw, Sw.conditionsNotSatisfied);
      expect(addressResolved, isTrue);
      expect(sc.pendingAddressRequest, isNull);
      expect(sc.pendingRequest, isNotNull);
    });

    test('dispose clears the pending address request', () async {
      await _parkAddress(sc);

      sc.dispose();

      expect(sc.pendingAddressRequest, isNull);
    });
  });
}
