/// Unit tests for [BleSession].
///
/// Covers auto-lock timer, BLE advertising lifecycle, APDU context
/// management, and dispose. Uses hand-written mocks.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/biz/ble_session.dart';
import 'package:open_ledger_app/biz/sign_confirmation.dart';
import 'package:open_ledger_app/core/interfaces/ble_peripheral.dart';
import 'package:open_ledger_app/core/models/chain.dart';
import 'package:open_ledger_app/core/interfaces/crypto_service.dart';
import '../support/inert_export.dart';
import '../support/inert_key_hierarchy.dart';
import 'package:open_ledger_app/core/interfaces/wallet_service.dart';
import 'package:open_ledger_app/core/models/apdu_message.dart';
import 'package:open_ledger_app/core/models/ble_types.dart';
import 'package:open_ledger_app/core/models/vault.dart';
import 'package:open_ledger_app/core/models/wallet_accounts.dart';
import 'package:open_ledger_app/protocols/apdu/apdu_constants.dart';
import 'package:open_ledger_app/biz/apdu_handler.dart';

import '../support/fake_crypto_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// Hand-written Mocks
// ═══════════════════════════════════════════════════════════════════════

class _MockWalletService implements IWalletService {
  @override
  void Function()? onActiveVaultChanged;

  @override
  void Function(Set<String> vaultIds)? onVaultsDestroyed;

  @override
  Future<bool> verifySessionPin(String pin) async => true;
  bool _isUnlocked = false;
  String? _seedHex;

  final List<String> calls = [];

  @override bool get isUnlocked => _isUnlocked;
  set isUnlocked(bool v) => _isUnlocked = v;

  @override String? get seedHex => _seedHex;
  set seedHex(String? v) => _seedHex = v;

  @override int get pinAttempts => 0;
  @override int get maxPinAttempts => 5;

  @override Future<bool> hasWallet() async { calls.add('hasWallet'); return true; }
  @override Future<bool> isLocked() async { calls.add('isLocked'); return false; }
  @override void lock() { calls.add('lock'); _isUnlocked = false; }
  @override Future<bool> verifyPin(String pin) async { calls.add('verifyPin'); return true; }
  @override Future<WalletAccounts> setupWallet(String mnemonic, {required String pin, String passphrase = '', bool storePassphrase = false, VaultSource source = VaultSource.imported, int enigmaLanguage = 0}) async { calls.add('setupWallet'); return WalletAccounts(accounts: [], mnemonicFingerprint: ''); }
  @override Future<WalletAccounts> unlockWallet(String pin) async { calls.add('unlockWallet'); return WalletAccounts(accounts: [], mnemonicFingerprint: ''); }
  @override Future<void> clearWallet() async { calls.add('clearWallet'); }
  @override Future<void> resetAll() async { calls.add('resetAll'); }
  @override WalletAccounts? getAccounts() { calls.add('getAccounts'); return null; }
  @override Future<WalletAccounts> addAccount(String chain, String path) async { calls.add('addAccount'); return WalletAccounts(accounts: [], mnemonicFingerprint: ''); }
  @override Future<WalletAccounts> removeAccount(String chain, String address) async { calls.add('removeAccount'); return WalletAccounts(accounts: [], mnemonicFingerprint: ''); }
  @override Future<String?> revealMnemonic(String pin) async { calls.add('revealMnemonic'); return null; }
  @override String? get mnemonic => null;
  @override String? get passphrase => null;
  @override Future<bool> updatePin(String oldPin, String newPin) async { calls.add('updatePin'); return true; }

  // ── Multi-vault session stubs (unused by these tests) ───────────────

  @override List<Vault> get vaults => const [];
  @override String? get activeVaultId => null;
  @override Vault? get activeVault => null;
  @override int? get sessionDepth => null;
  @override bool get isStandInSession => false;
  @override Future<bool> hasStandIn() async => false;
  @override Future<StandInMode> standInMode() async => StandInMode.hide;
  @override bool get lastUnlockWiped => false;
  @override Future<void> configureStandIn(String mnemonic, {required String pin, required String mainPin, StandInMode mode = StandInMode.hide, VaultSource source = VaultSource.imported, int enigmaLanguage = 0}) async {}
  @override Future<void> updateStandInPin({required String oldPin, required String newPin}) async {}
  @override Future<void> updateStandInMode({required String pin, required StandInMode mode}) async {}
  @override Future<void> removeStandIn({required String pin}) async {}
  @override Future<void> switchVault(String id) async {}
  @override Future<void> renameVault(String id, String label) async {}
  @override Future<WalletAccounts> addVault(String mnemonic, {required String pin, String passphrase = '', bool storePassphrase = false, String label = '', VaultSource source = VaultSource.imported, int enigmaLanguage = 0}) async { calls.add('addVault'); return WalletAccounts(accounts: const [], mnemonicFingerprint: ''); }
  @override Future<void> removeVault(String id, {required String pin}) async { calls.add('removeVault'); }
}

/// Minimal mock of [ApduHandler].
class _MockApduHandler extends ApduHandler {
  _MockApduHandler() : super(crypto: const FakeCryptoService()) {
    setCurrentApp(LedgerApp.ethereum);
  }

  bool contextCleared = false;
  String? seedSet;
  final List<ApduCommand> handledCommands = [];
  ApduResponse? nextResponse;

  /// Address returned by [deriveEthAddressForPath] for the P1=0x01 flow.
  String? derivedAddress;

  @override
  String? deriveEthAddressForPath(String path) => derivedAddress;

  @override
  void clearContext() {
    contextCleared = true;
  }

  @override
  void setContext({required String seedHex}) {
    seedSet = seedHex;
  }

  @override
  ApduResponse handle(ApduCommand command) {
    handledCommands.add(command);
    return nextResponse ?? ApduResponse(sw1: 0x90, sw2: 0x00);
  }
}

/// Minimal mock of [IBlePeripheral].
class _MockBlePeripheral implements IBlePeripheral {
  BleState _state = BleState.idle;

  @override
  BleState get state => _state;

  final StreamController<Uint8List> _apduController =
      StreamController<Uint8List>.broadcast();

  final StreamController<BleState> _stateController =
      StreamController<BleState>.broadcast();

  @override
  Stream<Uint8List> get apduStream => _apduController.stream;

  @override
  Stream<BleState> get stateStream => _stateController.stream;

  @override
  Stream<String> get logStream => const Stream.empty();

  @override
  String get deviceName => 'TestDevice';

  @override
  int get mtu => 20;

  final List<String> calls = [];
  final List<Uint8List> sentResponses = [];

  @override
  Future<void> startAdvertising() async {
    calls.add('startAdvertising');
    _state = BleState.broadcasting;
  }

  @override
  Future<void> stopAdvertising() async {
    calls.add('stopAdvertising');
    _state = BleState.idle;
  }

  @override
  Future<void> sendApduResponse(Uint8List bytes) async {
    calls.add('sendApduResponse');
    sentResponses.add(bytes);
  }

  @override
  void dispose() {
    calls.add('dispose');
    _apduController.close();
    _stateController.close();
  }

  @override
  Future<void> setDeviceName(String name) async {
    calls.add('setDeviceName');
  }

  /// Update [_state] and emit on [stateStream], mirroring real
  /// [_transition] behavior. Existing tests that only read [state]
  /// are unaffected — emissions go to a fresh broadcast stream.
  void setState(BleState s) {
    _state = s;
    if (!_stateController.isClosed) {
      _stateController.add(s);
    }
  }

  void addApduData(Uint8List data) => _apduController.add(data);
}

/// Minimal mock of [ICryptoService] for SignConfirmation construction.
class _MockCryptoService with InertKeyHierarchy, InertExport implements ICryptoService {
  @override String hexEncode(Uint8List b) => 'hex';
  @override String? deriveEthAddress(String s, String p) => '0xmock';
  @override String? deriveSolAddress(String s, String p) => 'mock';
  @override String? deriveBtcAddress(String s, String p) => 'mock';
  @override String? deriveTronAddress(String s, String p) => 'mock';
  @override String? deriveSuiAddress(String s, String p) => 'mock';
  @override String? parseSignData(String c, String p) => null;
  @override String generateMnemonic({int strength = 128}) => '';

  @override bool validateMnemonic(String m) => true;
  @override String reencodeMnemonic(String m) => m;
  @override String? generateMnemonicLang({int strength = 128, required int language}) => null;
  @override bool validateMnemonicLang(String m, int l) => true;
  @override Uint8List? deriveSecp256k1PrivateKey(String s, String p) => null;
  @override Uint8List? deriveSecp256k1Extended(String s, String p) => null;
  @override Uint8List? deriveEd25519PrivateKey(String s, String p) => null;
  @override Uint8List? signEthTransaction(String k, String r) => null;
  @override Uint8List? signEthPersonalMessage(String k, String m) => null;
  @override Uint8List? signEthEIP712(String k, String d, String s) => null;
  @override Uint8List? signSolanaMessage(String k, String m) => null;
  @override String? ethAddressFromPrivateKey(String k) => null;
  @override Uint8List? ethPublicKeyBytes(String k) => null;
  @override Uint8List? solanaPublicKeyBytes(String k) => null;
  @override String? p2wpkhAddress(String k) => null;
  @override String? tronAddressFromPubkey(String k) => null;
  @override String? suiAddress(String k) => null;
  @override String? enigmaDeriveMnemonic(String r, String s, int l) => null;
  @override String? enigmaEntropyHex(String r, String s, int l) => null;
  @override String? mnemonicFromEntropy(String e, int l) => null;
  @override String? pbkdf2Derive(String p, String s, int k) => 'hash';
  @override String? mnemonicToSeed(String m, {String passphrase = ''}) => 'seed';
  @override String? chacha20Encrypt(String p, String pi, String s) => 'enc';
  @override String? chacha20Decrypt(String c, String pi, String s) => 'dec';
  @override String? historyEncrypt(String p, String s) => 'enc';
  @override String? historyDecrypt(String c, String s) => 'dec';
  @override bool constantTimeEquals(String a, String b) => a == b;
  @override Uint8List hexToBytes(String h) => Uint8List(0);
}

// ═══════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════

void main() {
  late _MockWalletService walletService;
  late _MockApduHandler apduHandler;
  late SignConfirmation signConfirmation;
  late BleSession session;
  late _MockBlePeripheral blePeripheral;

  setUp(() {
    walletService = _MockWalletService();
    apduHandler = _MockApduHandler();
    // Create a real SignConfirmation with mock deps
    signConfirmation = SignConfirmation(
      crypto: _MockCryptoService(),
      apduHandler: apduHandler,
    );
    session = BleSession(
      walletService: walletService,
      apduHandler: apduHandler,
      signConfirmation: signConfirmation,
    );
    blePeripheral = _MockBlePeripheral();
  });

  // ──────────────────────────────────────────────────────────────────
  // BLE Peripheral setter
  // ──────────────────────────────────────────────────────────────────

  group('blePeripheral setter', () {
    test('setting peripheral subscribes to APDU stream', () {
      session.blePeripheral = blePeripheral;
      // When wallet is unlocked with seed, it should set context
      walletService._isUnlocked = true;
      walletService._seedHex = 'test-seed';
      session.trySetApduContext();
      expect(apduHandler.seedSet, 'test-seed');
    });

    test('setting to null unsubscribes and clears context', () {
      session.blePeripheral = blePeripheral;
      apduHandler.contextCleared = false;

      session.blePeripheral = null;

      expect(apduHandler.contextCleared, isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // trySetApduContext
  // ──────────────────────────────────────────────────────────────────

  group('trySetApduContext', () {
    test('sets seed when unlocked', () {
      walletService._isUnlocked = true;
      walletService._seedHex = 'my-seed-abc';

      session.trySetApduContext();

      expect(apduHandler.seedSet, 'my-seed-abc');
    });

    test('no-op when locked', () {
      walletService._isUnlocked = false;
      walletService._seedHex = 'my-seed';
      apduHandler.seedSet = null;

      session.trySetApduContext();

      expect(apduHandler.seedSet, isNull);
    });

    test('no-op when seed is null', () {
      walletService._isUnlocked = true;
      walletService._seedHex = null;
      apduHandler.seedSet = null;

      session.trySetApduContext();

      expect(apduHandler.seedSet, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // onAppBackgrounded / onAppForegrounded
  // ──────────────────────────────────────────────────────────────────

  group('onAppBackgrounded', () {
    test('starts auto-lock timer', () {
      session.onAppBackgrounded();

      // Timer is internal — we verify lock didn't fire yet.
      expect(walletService.calls.contains('lock'), isFalse);
    });

    test('stops advertising if broadcasting', () async {
      session.blePeripheral = blePeripheral;
      await blePeripheral.startAdvertising();

      session.onAppBackgrounded();

      expect(blePeripheral.calls.contains('stopAdvertising'), isTrue);
    });

    test('does not stop advertising if idle', () async {
      session.blePeripheral = blePeripheral;

      session.onAppBackgrounded();

      expect(blePeripheral.calls.contains('stopAdvertising'), isFalse);
    });
  });

  group('onAppForegrounded', () {
    test('cancels the auto-lock timer', () {
      session.onAppBackgrounded();
      session.onAppForegrounded();

      // Timer cancelled — wallet should not be locked.
      expect(walletService.calls.contains('lock'), isFalse);
    });

    test('restarts advertising if was stopped by onAppBackgrounded',
        () async {
      session.blePeripheral = blePeripheral;
      await blePeripheral.startAdvertising();
      session.onAppBackgrounded(); // stops advertising
      blePeripheral.calls.clear();

      session.onAppForegrounded();

      expect(blePeripheral.calls.contains('startAdvertising'), isTrue);
    });

    test('does not restart advertising if it was not broadcasting',
        () async {
      session.blePeripheral = blePeripheral;
      session.onAppBackgrounded(); // was idle, no stop called
      blePeripheral.calls.clear();

      session.onAppForegrounded();

      expect(blePeripheral.calls.contains('startAdvertising'), isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // Foreground idle lock (sliding window)
  // ──────────────────────────────────────────────────────────────────

  group('foreground idle lock', () {
    late BleSession idleSession;

    setUp(() {
      idleSession = BleSession(
        walletService: walletService,
        apduHandler: apduHandler,
        signConfirmation: signConfirmation,
        autoLockDuration: const Duration(minutes: 1),
        idleLockDuration: const Duration(seconds: 5),
      );
      walletService.isUnlocked = true;
      walletService.seedHex = 'test-seed';
      addTearDown(idleSession.dispose);
    });

    testWidgets('locks after a full window with no interaction',
        (tester) async {
      var lockedCallbacks = 0;
      idleSession.onWalletLocked = () => lockedCallbacks++;

      idleSession.onSessionStarted();
      await tester.pump(const Duration(seconds: 4));
      expect(walletService.calls.contains('lock'), isFalse);

      await tester.pump(const Duration(seconds: 2));
      expect(walletService.calls.contains('lock'), isTrue);
      expect(lockedCallbacks, 1);
    });

    testWidgets('interaction restarts the window (sliding)', (tester) async {
      idleSession.onSessionStarted();

      await tester.pump(const Duration(seconds: 4));
      idleSession.onUserActivity();
      await tester.pump(const Duration(seconds: 4));
      expect(walletService.calls.contains('lock'), isFalse);

      await tester.pump(const Duration(seconds: 2));
      expect(walletService.calls.contains('lock'), isTrue);
    });

    testWidgets('background pauses the idle window', (tester) async {
      idleSession.onSessionStarted();
      await tester.pump(const Duration(seconds: 3));

      idleSession.onAppBackgrounded();
      await tester.pump(const Duration(seconds: 4));
      expect(walletService.calls.contains('lock'), isFalse);

      idleSession.onAppForegrounded();
      await tester.pump(const Duration(seconds: 4));
      expect(walletService.calls.contains('lock'), isFalse);

      await tester.pump(const Duration(seconds: 2));
      expect(walletService.calls.contains('lock'), isTrue);
    });

    testWidgets('suppressed while a confirmation is pending', (tester) async {
      idleSession.onSessionStarted();
      idleSession.setIdleLockSuppressed(true);
      await tester.pump(const Duration(seconds: 10));
      expect(walletService.calls.contains('lock'), isFalse);

      idleSession.setIdleLockSuppressed(false);
      await tester.pump(const Duration(seconds: 4));
      expect(walletService.calls.contains('lock'), isFalse);

      await tester.pump(const Duration(seconds: 2));
      expect(walletService.calls.contains('lock'), isTrue);
    });

    testWidgets('does not start a window while the wallet is locked',
        (tester) async {
      walletService.isUnlocked = false;

      idleSession.onSessionStarted();
      idleSession.onUserActivity();
      await tester.pump(const Duration(seconds: 20));

      expect(walletService.calls.contains('lock'), isFalse);
    });

    testWidgets('idle lock leaves BLE advertising untouched', (tester) async {
      idleSession.blePeripheral = blePeripheral;
      await blePeripheral.startAdvertising();
      blePeripheral.calls.clear();

      idleSession.onSessionStarted();
      await tester.pump(const Duration(seconds: 6));

      expect(walletService.calls.contains('lock'), isTrue);
      expect(blePeripheral.calls.contains('stopAdvertising'), isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // dispose
  // ──────────────────────────────────────────────────────────────────

  group('dispose', () {
    test('cancels timer and clears context', () {
      session.blePeripheral = blePeripheral;
      session.onAppBackgrounded();
      apduHandler.contextCleared = false;

      session.dispose();

      expect(apduHandler.contextCleared, isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // APDU gating — ETH app special-cases (flow control + address confirm)
  // ──────────────────────────────────────────────────────────────────

  group('ETH_SIGN flow control (P1/P2)', () {
    setUp(() {
      session.blePeripheral = blePeripheral;
    });

    int lastSw() =>
        ApduResponse.fromBytes(blePeripheral.sentResponses.single).statusWord;

    ApduCommand signCommand({required int p1, required int p2, Uint8List? data}) =>
        ApduCommand(cla: Cla.os, ins: Ins.ethSign, p1: p1, p2: p2, data: data);

    test('rejects P1 outside {0x00, 0x80} with 0x6A86', () async {
      await session.onApduCommand(
          signCommand(p1: 0x01, p2: 0x00).toBytes(), 'seed-hex');

      expect(lastSw(), Sw.incorrectP1P2);
    });

    test('rejects P2 outside {0x00, 0x01, 0x02} with 0x6A86', () async {
      await session.onApduCommand(
          signCommand(p1: 0x00, p2: 0x03).toBytes(), 'seed-hex');

      expect(lastSw(), Sw.incorrectP1P2);
    });

    test('P2=0x02 (start flow) is acked with 9000 and no confirmation',
        () async {
      await session.onApduCommand(
          signCommand(p1: 0x00, p2: 0x02).toBytes(), 'seed-hex');

      expect(lastSw(), Sw.success);
      expect(signConfirmation.pendingRequest, isNull);
    });

    test('P2=0x01 (store only) acks a complete tx without confirmation',
        () async {
      await session.onApduCommand(
          signCommand(
            p1: 0x00,
            p2: 0x01,
            data: _blePathData(const [0x80000000],
                remainder: const [0xc1, 0x01]),
          ).toBytes(),
          'seed-hex');

      expect(lastSw(), Sw.success);
      expect(signConfirmation.pendingRequest, isNull);
    });

    test('P2=0x00 acks an incomplete chunk with 9000', () async {
      await session.onApduCommand(
          signCommand(
            p1: 0x00,
            p2: 0x00,
            data: _blePathData(const [0x80000000],
                remainder: const [0xc5, 0x01]),
          ).toBytes(),
          'seed-hex');

      expect(lastSw(), Sw.success);
      expect(signConfirmation.pendingRequest, isNull);
    });

    test('P2=0x00 intercepts a complete tx for user confirmation', () async {
      bool pendingCalled = false;
      signConfirmation.onRequestPending = () => pendingCalled = true;

      await session.onApduCommand(
          signCommand(
            p1: 0x00,
            p2: 0x00,
            data: _blePathData(const [0x80000000],
                remainder: const [0xc1, 0x01]),
          ).toBytes(),
          'seed-hex');

      expect(pendingCalled, isTrue);
      expect(signConfirmation.pendingRequest, isNotNull);
      expect(signConfirmation.pendingRequest!.chain, 'ethereum');
      // Response is deferred until approve()/reject().
      expect(blePeripheral.sentResponses, isEmpty);
    });
  });

  group('ETH GET_PUBLIC_KEY P1=0x01 (address display + confirm)', () {
    setUp(() {
      session.blePeripheral = blePeripheral;
    });

    ApduCommand addressCommand({int p2 = P2.ethNoChainCode}) =>
        ApduCommand(
            cla: Cla.os, ins: Ins.getPublicKey, p1: P1.ethConfirm, p2: p2);

    test('intercepts and holds the address for confirmation', () async {
      apduHandler.derivedAddress = '0xdeadbeef';
      bool pendingCalled = false;
      signConfirmation.onAddressRequestPending = () => pendingCalled = true;

      await session.onApduCommand(addressCommand().toBytes(), 'seed-hex');

      expect(pendingCalled, isTrue);
      expect(signConfirmation.pendingAddressRequest, isNotNull);
      expect(signConfirmation.pendingAddressRequest!.address, '0xdeadbeef');
      expect(signConfirmation.pendingAddressRequest!.derivationPath,
          "m/44'/60'/0'/0/0");
      // Response is deferred until the user confirms.
      expect(blePeripheral.sentResponses, isEmpty);
    });

    test('rejects an out-of-range P2 with 0x6A86', () async {
      apduHandler.derivedAddress = '0xdeadbeef';

      await session.onApduCommand(
          addressCommand(p2: 0x02).toBytes(), 'seed-hex');

      expect(
          ApduResponse.fromBytes(blePeripheral.sentResponses.single).statusWord,
          Sw.incorrectP1P2);
      expect(signConfirmation.pendingAddressRequest, isNull);
    });

    test('P1=0x00 (no display) returns the address immediately', () async {
      apduHandler.nextResponse = ApduResponse(
          data: Uint8List.fromList([0x41]), sw1: 0x90, sw2: 0x00);

      await session.onApduCommand(
          ApduCommand(
            cla: Cla.os,
            ins: Ins.getPublicKey,
            p1: P1.ethNonConfirm,
            p2: P2.ethNoChainCode,
          ).toBytes(),
          'seed-hex');

      expect(blePeripheral.sentResponses, isNotEmpty);
      expect(signConfirmation.pendingAddressRequest, isNull);
      expect(apduHandler.handledCommands.single.ins, Ins.getPublicKey);
    });
  });
}

/// Build APDU data: `[depth(1B)] [4B BE components...] [remainder]`.
Uint8List _blePathData(List<int> components,
    {List<int> remainder = const []}) {
  final bytes = Uint8List(1 + components.length * 4 + remainder.length);
  bytes[0] = components.length;
  for (var i = 0; i < components.length; i++) {
    final value = components[i];
    final offset = 1 + i * 4;
    bytes[offset] = (value >> 24) & 0xFF;
    bytes[offset + 1] = (value >> 16) & 0xFF;
    bytes[offset + 2] = (value >> 8) & 0xFF;
    bytes[offset + 3] = value & 0xFF;
  }
  bytes.setRange(1 + components.length * 4, bytes.length, remainder);
  return bytes;
}
