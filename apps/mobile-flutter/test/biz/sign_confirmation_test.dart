/// Unit tests for [SignConfirmation].
///
/// Covers isSignCommand, chainFromCommand, interceptSignCommand,
/// approve, reject, the timeout backstops, supersede, and dispose.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/biz/sign_confirmation.dart';
import 'package:open_ledger_app/core/interfaces/crypto_service.dart';
import '../support/inert_export.dart';
import '../support/inert_key_hierarchy.dart';
import 'package:open_ledger_app/core/interfaces/history_repository.dart';
import 'package:open_ledger_app/core/models/apdu_message.dart';
import 'package:open_ledger_app/core/models/chain.dart';
import 'package:open_ledger_app/core/models/signature_record.dart';
import 'package:open_ledger_app/protocols/apdu/apdu_constants.dart';
import 'package:open_ledger_app/biz/apdu_handler.dart';

// ═══════════════════════════════════════════════════════════════════════
// Hand-written Mocks
// ═══════════════════════════════════════════════════════════════════════

/// Configurable mock of [ICryptoService] for SignConfirmation tests.
class _MockCryptoService with InertKeyHierarchy, InertExport implements ICryptoService {
  String? hexEncodeResult;
  String? deriveEthResult;
  String? deriveSolResult;
  String? deriveBtcResult;
  String? deriveTronResult;
  String? deriveSuiResult;
  String? parseSignDataResult;

  final List<Uint8List> hexEncodeCalls = [];
  final List<String> deriveEthCalls = [];
  final List<String> parseSignDataCalls = [];

  @override
  String hexEncode(Uint8List bytes) {
    hexEncodeCalls.add(bytes);
    return hexEncodeResult ?? 'hex-encoded';
  }

  @override
  String? deriveEthAddress(String seedHex, String path) {
    deriveEthCalls.add(path);
    return deriveEthResult ?? '0xmockethaddress1234';
  }

  @override
  String? deriveSolAddress(String seedHex, String path) =>
      deriveSolResult ?? 'MockSolAddr';

  @override
  String? deriveBtcAddress(String seedHex, String path) =>
      deriveBtcResult ?? 'bc1mockbtc';

  @override
  String? deriveTronAddress(String seedHex, String path) =>
      deriveTronResult ?? 'TMockTron';

  @override
  String? deriveSuiAddress(String seedHex, String path) =>
      deriveSuiResult ?? '0xmocksui';

  @override
  String? parseSignData(String chain, String payloadHex) {
    parseSignDataCalls.add(chain);
    return parseSignDataResult;
  }

  // ── Unused ─────────────────────────────────────────────────────────

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

/// Minimal mock of [ApduHandler] that extends the real class.
class _MockApduHandler extends ApduHandler {
  _MockApduHandler(ICryptoService crypto) : super(crypto: crypto) {
    // Production always has an app open before the radio is on; these
    // tests exercise the Ethereum app table.
    setCurrentApp(LedgerApp.ethereum);
  }

  LedgerApp? currentAppOverride;

  @override
  LedgerApp? get currentApp => currentAppOverride ?? super.currentApp;
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
// Helper: build a minimal APDU command with derivation path data
// ═══════════════════════════════════════════════════════════════════════

/// Build an APDU data blob: [depth(1B)] [4B components...] [remainder bytes]
Uint8List _buildPathData(int depth, List<int> components, {List<int>? remainder}) {
  final bytes = Uint8List(1 + depth * 4 + (remainder?.length ?? 0));
  bytes[0] = depth;
  for (int i = 0; i < depth; i++) {
    final offset = 1 + i * 4;
    final value = components[i];
    bytes[offset] = (value >> 24) & 0xFF;
    bytes[offset + 1] = (value >> 16) & 0xFF;
    bytes[offset + 2] = (value >> 8) & 0xFF;
    bytes[offset + 3] = value & 0xFF;
  }
  if (remainder != null) {
    bytes.setRange(1 + depth * 4, bytes.length, remainder);
  }
  return bytes;
}

/// Create a sign-capable APDU command with path data payload.
ApduCommand _makeSignCommand({
  int cla = Cla.os,
  int ins = Ins.ethSign,
  int p1 = 0x00,
  int p2 = 0x00,
  Uint8List? data,
}) {
  return ApduCommand(cla: cla, ins: ins, p1: p1, p2: p2, data: data);
}

// ═══════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════

void main() {
  late _MockCryptoService crypto;
  late _MockApduHandler apduHandler;
  late SignConfirmation sc;

  setUp(() {
    crypto = _MockCryptoService();
    apduHandler = _MockApduHandler(crypto);
    sc = SignConfirmation(crypto: crypto, apduHandler: apduHandler);
  });

  // ──────────────────────────────────────────────────────────────────
  // isSignCommand
  // ──────────────────────────────────────────────────────────────────

  group('isSignCommand', () {
    test('detects ETH_SIGN (INS 0x04)', () {
      final cmd = _makeSignCommand(ins: Ins.ethSign);
      expect(SignConfirmation.isSignCommand(cmd,
          currentApp: LedgerApp.ethereum), isTrue);
    });

    test('does not intercept GET_APP_CONFIGURATION (INS 0x06)', () {
      final cmd = _makeSignCommand(ins: Ins.getAppConfiguration);
      expect(SignConfirmation.isSignCommand(cmd,
          currentApp: LedgerApp.ethereum), isFalse);
    });

    test('detects signEthPersonalMessage (INS 0x08)', () {
      final cmd = _makeSignCommand(ins: Ins.signEthPersonalMessage);
      expect(SignConfirmation.isSignCommand(cmd,
          currentApp: LedgerApp.ethereum), isTrue);
    });

    test('does NOT intercept PROVIDE_ERC20_TOKEN_INFO (INS 0x0A, ETH app)', () {
      // Real Ledger Ethereum: host pushes ERC-20 metadata before token
      // transfers; device ACKs 9000 with no confirmation popup.
      final cmd = _makeSignCommand(ins: Ins.ethProvideErc20TokenInfo);
      expect(SignConfirmation.isSignCommand(cmd,
          currentApp: LedgerApp.ethereum), isFalse);
    });

    test('detects Solana SIGN (INS 0x06) only when Solana app is open', () {
      final cmd = _makeSignCommand(ins: Ins.solSignMessage);
      // Ethereum app context: 0x06 is GET_APP_CONFIGURATION, not signing.
      expect(SignConfirmation.isSignCommand(cmd,
          currentApp: LedgerApp.ethereum), isFalse);
      // Solana app context (set by OPEN_APP "Solana").
      expect(
        SignConfirmation.isSignCommand(cmd, currentApp: LedgerApp.solana),
        isTrue,
      );
    });

    test('does NOT route ETH_SIGN (INS 0x04) as Solana in Solana app', () {
      // INS 0x04 in the Solana app is GET_VERSION — never a sign popup.
      final cmd = _makeSignCommand(ins: Ins.ethSign);
      expect(
        SignConfirmation.isSignCommand(cmd, currentApp: LedgerApp.solana),
        isFalse,
      );
    });

    test('detects EIP-712 V0 sign (INS 0x0C with 64B remainder)', () {
      // 64-byte remainder = domain_hash(32) + struct_hash(32)
      final remainder = Uint8List(64);
      final data = _buildPathData(1, [0x8000002C], remainder: remainder);
      final cmd = _makeSignCommand(ins: Ins.ethSignEip712, data: data);
      expect(SignConfirmation.isSignCommand(cmd,
          currentApp: LedgerApp.ethereum), isTrue);
    });

    test('does NOT intercept EIP-712 with a short (<64B) payload', () {
      // A 32-byte remainder is not a valid V0 EIP-712 payload.
      final remainder = Uint8List(32);
      final data = _buildPathData(1, [0x8000002C], remainder: remainder);
      final cmd = _makeSignCommand(ins: Ins.ethSignEip712, data: data);
      expect(SignConfirmation.isSignCommand(cmd,
          currentApp: LedgerApp.ethereum), isFalse);
    });

    test('detects BTC sign (CLA 0xe1, INS 0x44)', () {
      final cmd = _makeSignCommand(cla: Cla.bitcoin, ins: Ins.btcSignTx);
      expect(SignConfirmation.isSignCommand(cmd,
          currentApp: LedgerApp.ethereum), isTrue);
    });

    test('detects BTC extended sign (CLA 0xf8, INS 0x44)', () {
      final cmd = _makeSignCommand(cla: Cla.bitcoinExt, ins: Ins.btcSignTx);
      expect(SignConfirmation.isSignCommand(cmd,
          currentApp: LedgerApp.ethereum), isTrue);
    });

    test('detects Tron sign (CLA 0x14, INS 0x04)', () {
      final cmd = _makeSignCommand(cla: Cla.tron, ins: Ins.tronSignTx);
      expect(SignConfirmation.isSignCommand(cmd,
          currentApp: LedgerApp.ethereum), isTrue);
    });

    test('detects Sui sign (CLA 0x07, INS 0x04)', () {
      final cmd = _makeSignCommand(cla: Cla.sui, ins: Ins.suiSignTx);
      expect(SignConfirmation.isSignCommand(cmd,
          currentApp: LedgerApp.ethereum), isTrue);
    });

    test('returns false for getVersion (INS 0x01)', () {
      final cmd = _makeSignCommand(ins: Ins.getVersion);
      expect(SignConfirmation.isSignCommand(cmd,
          currentApp: LedgerApp.ethereum), isFalse);
    });

    test('returns false for getPublicKey (INS 0x02)', () {
      final cmd = _makeSignCommand(ins: Ins.getPublicKey);
      expect(SignConfirmation.isSignCommand(cmd,
          currentApp: LedgerApp.ethereum), isFalse);
    });

    test('returns false for unsupported CLA', () {
      final cmd = _makeSignCommand(cla: 0xFF, ins: Ins.ethSign);
      expect(SignConfirmation.isSignCommand(cmd,
          currentApp: LedgerApp.ethereum), isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // chainFromCommand
  // ──────────────────────────────────────────────────────────────────

  group('chainFromCommand', () {
    test('ETH_SIGN returns ethereum', () {
      final cmd = _makeSignCommand(ins: Ins.ethSign);
      expect(SignConfirmation.chainFromCommand(cmd), 'ethereum');
    });

    test('GET_APP_CONFIGURATION is classified as ethereum app metadata', () {
      final cmd = _makeSignCommand(ins: Ins.getAppConfiguration);
      expect(SignConfirmation.chainFromCommand(cmd), 'ethereum');
    });

    test('signEthPersonalMessage returns personal_msg', () {
      final cmd = _makeSignCommand(ins: Ins.signEthPersonalMessage);
      expect(SignConfirmation.chainFromCommand(cmd), 'personal_msg');
    });

    test('EIP-712 V0 (INS 0x0C with 64B) returns eip712', () {
      final remainder = Uint8List(64);
      final data = _buildPathData(1, [0x8000002C], remainder: remainder);
      final cmd = _makeSignCommand(ins: Ins.ethSignEip712, data: data);
      expect(SignConfirmation.chainFromCommand(cmd), 'eip712');
    });

    test('EIP-712 with a short (<64B) payload returns ethereum', () {
      // A short 0x0C payload is not a sign request — chainFromCommand falls
      // through to 'ethereum' (and the handler rejects it with wrongData).
      final remainder = Uint8List(32);
      final data = _buildPathData(1, [0x8000002C], remainder: remainder);
      final cmd = _makeSignCommand(ins: Ins.ethSignEip712, data: data);
      expect(SignConfirmation.chainFromCommand(cmd), 'ethereum');
    });

    test('legacy INS 0x06 is GET_APP_CONFIGURATION, not EIP-712', () {
      final cmd = _makeSignCommand(ins: Ins.getAppConfiguration, p1: 0x02);
      expect(SignConfirmation.chainFromCommand(cmd), 'ethereum');
    });

    test('Solana returns solana only with Solana app context (INS 0x06)', () {
      final cmd = _makeSignCommand(ins: Ins.solSignMessage);
      // Ethereum app context: 0x06 is ETH GET_APP_CONFIGURATION → ethereum.
      expect(SignConfirmation.chainFromCommand(cmd), 'ethereum');
      // Solana app context after OPEN_APP "Solana".
      expect(
        SignConfirmation.chainFromCommand(cmd, currentApp: LedgerApp.solana),
        'solana',
      );
    });

    test('ERC-20 provisioning (INS 0x0A) stays ethereum, not solana', () {
      final cmd = _makeSignCommand(ins: Ins.ethProvideErc20TokenInfo);
      expect(SignConfirmation.chainFromCommand(cmd), 'ethereum');
    });

    test('Bitcoin returns bitcoin', () {
      final cmd = _makeSignCommand(cla: Cla.bitcoin, ins: Ins.btcSignTx);
      expect(SignConfirmation.chainFromCommand(cmd), 'bitcoin');
    });

    test('Tron returns tron', () {
      final cmd = _makeSignCommand(cla: Cla.tron, ins: Ins.tronSignTx);
      expect(SignConfirmation.chainFromCommand(cmd), 'tron');
    });

    test('Sui returns sui', () {
      final cmd = _makeSignCommand(cla: Cla.sui, ins: Ins.suiSignTx);
      expect(SignConfirmation.chainFromCommand(cmd), 'sui');
    });

    test('unknown CLA returns unknown', () {
      final cmd = _makeSignCommand(cla: 0xFF, ins: 0xFF);
      expect(SignConfirmation.chainFromCommand(cmd), 'unknown');
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // interceptSignCommand
  // ──────────────────────────────────────────────────────────────────

  group('interceptSignCommand', () {
    test('creates pending request and triggers onRequestPending', () async {
      final pathData = _buildPathData(3, [
        0x8000002C, // 44'
        0x8000003C, // 60'
        0x80000000, // 0'
      ], remainder: [0xAB, 0xCD]);

      final cmd = _makeSignCommand(
        ins: Ins.ethSign,
        data: pathData,
      );

      bool pendingCalled = false;
      sc.onRequestPending = () => pendingCalled = true;

      crypto.parseSignDataResult = '{"to":"0xabc","value":"0"}';

      final result = await sc.interceptSignCommand(cmd, 'seed-hex');

      expect(result, isTrue);
      expect(pendingCalled, isTrue);
      expect(sc.pendingRequest, isNotNull);
      expect(sc.pendingRequest!.chain, 'ethereum');
      expect(sc.pendingRequest!.derivationPath, "m/44'/60'/0'");
    });

    test('returns false when data is null', () async {
      final cmd = _makeSignCommand(ins: Ins.ethSign, data: null);
      final result = await sc.interceptSignCommand(cmd, 'seed-hex');
      expect(result, isFalse);
    });

    test('returns false when data is empty', () async {
      final cmd = _makeSignCommand(ins: Ins.ethSign, data: Uint8List(0));
      final result = await sc.interceptSignCommand(cmd, 'seed-hex');
      expect(result, isFalse);
    });

    test('strips OKX num_signers prefix on Solana sign frames', () async {
      // Real OKX frame: 01 (num_signers) + path m/44'/501'/0'/0' + message.
      final body = _buildPathData(4, [
        0x8000002C, // 44'
        0x800001F5, // 501'
        0x80000000, // 0'
        0x80000000, // 0'
      ], remainder: [0x01, 0x00, 0x01]);
      final data = Uint8List(body.length + 1);
      data[0] = 0x01; // OKX num_signers prefix
      data.setRange(1, data.length, body);

      apduHandler.currentAppOverride = LedgerApp.solana;
      crypto.parseSignDataResult = '{"type":"solana_tx"}';

      final cmd = _makeSignCommand(ins: Ins.solSignMessage, p1: 0x01, data: data);
      final result = await sc.interceptSignCommand(cmd, 'seed-hex');

      expect(result, isTrue);
      expect(sc.pendingRequest!.chain, 'solana');
      expect(sc.pendingRequest!.derivationPath, "m/44'/501'/0'/0'");
      // Remainder must be the message only — the prefix must not leak in.
      expect(sc.pendingRequest!.payloadHex, 'hex-encoded');
      expect(crypto.hexEncodeCalls.single, equals(Uint8List.fromList([0x01, 0x00, 0x01])));
    });

    test('returns false when path parsing fails (depth > 10)', () async {
      final badData = Uint8List(1 + 11 * 4);
      badData[0] = 11; // depth=11
      final cmd = _makeSignCommand(ins: Ins.ethSign, data: badData);
      final result = await sc.interceptSignCommand(cmd, 'seed-hex');
      expect(result, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // Resolution — approve / reject / timeout
  // ──────────────────────────────────────────────────────────────────

  group('approve', () {
    test('calls sign callback and stores result', () async {
      // First, create a pending request via intercept.
      final pathData = _buildPathData(1, [0x80000000]);
      final cmd = _makeSignCommand(ins: Ins.ethSign, data: pathData);
      crypto.parseSignDataResult = '{"to":"0xdef"}';
      await sc.interceptSignCommand(cmd, 'seed-hex');

      bool resolvedCalled = false;
      sc.onRequestResolved = () => resolvedCalled = true;

      final responseBytes = Uint8List.fromList([0x01, 0x02, 0x90, 0x00]);

      await sc.approve(() async => responseBytes);

      expect(sc.pendingRequest, isNull);
      expect(resolvedCalled, isTrue);
      expect(sc.lastSignResult, isNotNull);
      expect(sc.lastSignResult!['isSuccess'], isTrue);
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
      // Create pending request
      final pathData = _buildPathData(1, [0x80000000]);
      final cmd = _makeSignCommand(ins: Ins.ethSign, data: pathData);
      await sc.interceptSignCommand(cmd, 'seed-hex');

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
    });

    test('swallows errors from sendError callback', () async {
      // Create pending request
      final pathData = _buildPathData(1, [0x80000000]);
      final cmd = _makeSignCommand(ins: Ins.ethSign, data: pathData);
      await sc.interceptSignCommand(cmd, 'seed-hex');

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
      // Create pending request
      final pathData = _buildPathData(1, [0x80000000]);
      final cmd = _makeSignCommand(ins: Ins.ethSign, data: pathData);
      await sc.interceptSignCommand(cmd, 'seed-hex');
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
      // Create pending request
      final pathData = _buildPathData(1, [0x80000000]);
      final cmd = _makeSignCommand(ins: Ins.ethSign, data: pathData);
      await sc.interceptSignCommand(cmd, 'seed-hex');
      await sc.reject(() async => Uint8List(0));

      int? sentSw;
      sc.sendTerminalStatus = (sw) async => sentSw = sw;

      await sc.onSignBackstopTimeout();

      expect(sentSw, isNull);
    });
  });

  group('cancelPending', () {
    test('drops a pending sign request and notifies', () async {
      final pathData = _buildPathData(1, [0x80000000]);
      final cmd = _makeSignCommand(ins: Ins.ethSign, data: pathData);
      await sc.interceptSignCommand(cmd, 'seed-hex');

      bool resolvedCalled = false;
      sc.onRequestResolved = () => resolvedCalled = true;

      expect(sc.cancelPending(), isTrue);
      expect(sc.pendingRequest, isNull);
      expect(resolvedCalled, isTrue);
    });

    test('drops a pending address request and notifies', () async {
      await sc.interceptAddressCommand(
          const ApduCommand(
            cla: Cla.os,
            ins: Ins.getPublicKey,
            p1: P1.ethConfirm,
            p2: P2.ethNoChainCode,
          ),
          '0xabc123',
          "m/44'/60'/0'/0/0");

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
      // Create pending and approve
      final pathData = _buildPathData(1, [0x80000000]);
      final cmd = _makeSignCommand(ins: Ins.ethSign, data: pathData);
      await sc.interceptSignCommand(cmd, 'seed-hex');
      await sc.approve(() async => Uint8List.fromList([0x90, 0x00]));
      expect(sc.lastSignResult, isNotNull);

      sc.clearLastSignResult();

      expect(sc.lastSignResult, isNull);
    });
  });

  group('dispose', () {
    test('clears all state', () async {
      final pathData = _buildPathData(1, [0x80000000]);
      final cmd = _makeSignCommand(ins: Ins.ethSign, data: pathData);
      await sc.interceptSignCommand(cmd, 'seed-hex');
      await sc.approve(() async => Uint8List.fromList([0x90, 0x00]));

      sc.dispose();

      expect(sc.pendingRequest, isNull);
      expect(sc.lastSignResult, isNull);
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

      await sc.interceptSignCommand(
          _makeSignCommand(
              ins: Ins.ethSign, data: _buildPathData(1, [0x80000000])),
          'seed-hex');
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

      await sc.interceptSignCommand(
          _makeSignCommand(
              ins: Ins.ethSign, data: _buildPathData(1, [0x80000000])),
          'seed-hex');
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

      await sc.interceptSignCommand(
          _makeSignCommand(
              ins: Ins.ethSign, data: _buildPathData(1, [0x80000000])),
          'seed-hex');
      await sc.reject(() async => Uint8List.fromList([0x69, 0x85]));
      await Future<void>.delayed(Duration.zero);

      expect(sc.history.length, SignConfirmation.maxHistoryRecords);
      expect(repo.saved!.length, SignConfirmation.maxHistoryRecords);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // Address display + confirm (ETH GET_PUBLIC_KEY P1=0x01)
  // ──────────────────────────────────────────────────────────────────

  group('address confirmation (GET_PUBLIC_KEY P1=0x01)', () {
    ApduCommand addressCommand() => const ApduCommand(
          cla: Cla.os,
          ins: Ins.getPublicKey,
          p1: P1.ethConfirm,
          p2: P2.ethNoChainCode,
        );

    test('interceptAddressCommand stores a pending request and notifies',
        () async {
      bool pendingCalled = false;
      sc.onAddressRequestPending = () => pendingCalled = true;

      final result = await sc.interceptAddressCommand(
          addressCommand(), '0xabc123', "m/44'/60'/0'/0/0");

      expect(result, isTrue);
      expect(pendingCalled, isTrue);
      expect(sc.pendingAddressRequest, isNotNull);
      expect(sc.pendingAddressRequest!.address, '0xabc123');
      expect(sc.pendingAddressRequest!.derivationPath, "m/44'/60'/0'/0/0");
      expect(sc.pendingAddressRequest!.chain, 'ethereum');
    });

    test('interceptAddressCommand returns false for an empty address', () async {
      final result = await sc.interceptAddressCommand(
          addressCommand(), '', "m/44'/60'/0'/0/0");

      expect(result, isFalse);
      expect(sc.pendingAddressRequest, isNull);
    });

    test('approveAddress responds then clears the pending request', () async {
      await sc.interceptAddressCommand(
          addressCommand(), '0xabc123', "m/44'/60'/0'/0/0");

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
      await sc.interceptAddressCommand(
          addressCommand(), '0xabc123', "m/44'/60'/0'/0/0");

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
      await sc.interceptAddressCommand(
          addressCommand(), '0xabc123', "m/44'/60'/0'/0/0");

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
      await sc.interceptAddressCommand(
          addressCommand(), '0xabc123', "m/44'/60'/0'/0/0");

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
      await sc.interceptAddressCommand(
          addressCommand(), '0xabc123', "m/44'/60'/0'/0/0");
      await sc.rejectAddress(() async => Uint8List.fromList([0x69, 0x85]));

      int? sentSw;
      sc.sendTerminalStatus = (sw) async => sentSw = sw;

      await sc.onAddressBackstopTimeout();

      expect(sentSw, isNull);
    });

    testWidgets('backstop fires after the configured duration', (tester) async {
      final backstopped = SignConfirmation(
        crypto: crypto,
        apduHandler: apduHandler,
        confirmationBackstop: const Duration(seconds: 5),
      );
      addTearDown(backstopped.dispose);

      await backstopped.interceptAddressCommand(
          addressCommand(), '0xabc123', "m/44'/60'/0'/0/0");

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
        apduHandler: apduHandler,
        confirmationBackstop: const Duration(seconds: 5),
      );
      addTearDown(backstopped.dispose);

      await backstopped.interceptAddressCommand(
          addressCommand(), '0xabc123', "m/44'/60'/0'/0/0");

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
      await sc.interceptAddressCommand(
          addressCommand(), '0xold', "m/44'/60'/0'/0/0");

      final sent = <int>[];
      bool resolvedCalled = false;
      sc.sendTerminalStatus = (sw) async => sent.add(sw);
      sc.onAddressRequestResolved = () => resolvedCalled = true;

      await sc.interceptAddressCommand(
          addressCommand(), '0xnew', "m/44'/60'/0'/0/0");

      expect(sent, [Sw.conditionsNotSatisfied]);
      expect(resolvedCalled, isTrue);
      expect(sc.pendingAddressRequest!.address, '0xnew');
    });

    test('a sign request supersedes a pending address request', () async {
      await sc.interceptAddressCommand(
          addressCommand(), '0xabc123', "m/44'/60'/0'/0/0");

      int? sentSw;
      bool addressResolved = false;
      sc.sendTerminalStatus = (sw) async => sentSw = sw;
      sc.onAddressRequestResolved = () => addressResolved = true;

      final pathData = _buildPathData(1, [0x80000000]);
      await sc.interceptSignCommand(
          _makeSignCommand(ins: Ins.ethSign, data: pathData), 'seed-hex');

      expect(sentSw, Sw.conditionsNotSatisfied);
      expect(addressResolved, isTrue);
      expect(sc.pendingAddressRequest, isNull);
      expect(sc.pendingRequest, isNotNull);
    });

    test('dispose clears the pending address request', () async {
      await sc.interceptAddressCommand(
          addressCommand(), '0xabc123', "m/44'/60'/0'/0/0");

      sc.dispose();

      expect(sc.pendingAddressRequest, isNull);
    });
  });
}
