/// Unit tests for [BleSession].
///
/// Covers auto-lock timers, BLE advertising lifecycle, seed hand-off, and the
/// APDU dispatch contract: chain commands go to the Rust chain-app host (or
/// are refused), OS/app frames go to [ApduHandler]. Uses hand-written mocks.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/biz/apdu_handler.dart';
import 'package:open_ledger_app/biz/ble_session.dart';
import 'package:open_ledger_app/biz/sign_confirmation.dart';
import 'package:open_ledger_app/core/interfaces/ble_peripheral.dart';
import 'package:open_ledger_app/core/interfaces/chain_host_service.dart';
import 'package:open_ledger_app/core/interfaces/crypto_service.dart';
import 'package:open_ledger_app/core/interfaces/wallet_service.dart';
import 'package:open_ledger_app/core/models/apdu_message.dart';
import 'package:open_ledger_app/core/models/ble_types.dart';
import 'package:open_ledger_app/core/models/chain.dart';
import 'package:open_ledger_app/core/models/chain_host_reply.dart';
import 'package:open_ledger_app/core/models/vault.dart';
import 'package:open_ledger_app/core/models/wallet_accounts.dart';
import 'package:open_ledger_app/protocols/apdu/apdu_constants.dart';
import '../support/inert_export.dart';
import '../support/inert_key_hierarchy.dart';

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

/// Hand-written [IChainHostService] capturing every call.
class _FakeChainHost implements IChainHostService {
  bool available = true;

  /// Reply returned by [submit]; `null` models a host that cannot answer.
  ChainHostReply? reply;

  /// Bytes returned by [resolve].
  Uint8List? resolveBytes;

  final List<String> openedApps = [];
  final List<Uint8List> submitted = [];
  final List<int> resolvedIds = [];

  String? seed;
  bool locked = false;

  @override
  bool get isAvailable => available;

  @override
  void setSeed(String? seedHex) => seed = seedHex;

  @override
  void openApp(String moduleId) => openedApps.add(moduleId);

  @override
  ChainHostReply? submit(Uint8List apdu) {
    submitted.add(apdu);
    return reply;
  }

  @override
  Uint8List? resolve(int reviewId, {required bool approved}) {
    resolvedIds.add(reviewId);
    return resolveBytes;
  }

  @override
  ChainAccountMaterial? deriveAccount(
    String moduleId, {
    int accountProfileIndex = 0,
    required int addressIndex,
  }) =>
      null;

  @override
  void lock() => locked = true;
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
  late ApduHandler apduHandler;
  late _FakeChainHost chainHost;
  late SignConfirmation signConfirmation;
  late BleSession session;
  late _MockBlePeripheral blePeripheral;

  setUp(() {
    walletService = _MockWalletService();
    apduHandler = ApduHandler()..setCurrentApp(LedgerApp.ethereum);
    chainHost = _FakeChainHost();
    signConfirmation = SignConfirmation(crypto: _MockCryptoService());
    session = BleSession(
      walletService: walletService,
      apduHandler: apduHandler,
      signConfirmation: signConfirmation,
      chainHost: chainHost,
    );
    blePeripheral = _MockBlePeripheral();
  });

  // ──────────────────────────────────────────────────────────────────
  // BLE Peripheral setter
  // ──────────────────────────────────────────────────────────────────

  group('blePeripheral setter', () {
    test('setting peripheral hands the seed to the chain host', () {
      walletService.isUnlocked = true;
      walletService.seedHex = 'test-seed';

      session.blePeripheral = blePeripheral;

      expect(chainHost.seed, 'test-seed');
    });

    test('setting to null clears the host seed', () {
      walletService.isUnlocked = true;
      walletService.seedHex = 'test-seed';
      session.blePeripheral = blePeripheral;

      session.blePeripheral = null;

      expect(chainHost.seed, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // trySetApduContext
  // ──────────────────────────────────────────────────────────────────

  group('trySetApduContext', () {
    test('sets seed when unlocked', () {
      walletService.isUnlocked = true;
      walletService.seedHex = 'my-seed-abc';

      session.trySetApduContext();

      expect(chainHost.seed, 'my-seed-abc');
    });

    test('no-op when locked', () {
      walletService.isUnlocked = false;
      walletService.seedHex = 'my-seed';

      session.trySetApduContext();

      expect(chainHost.seed, isNull);
    });

    test('no-op when seed is null', () {
      walletService.isUnlocked = true;
      walletService.seedHex = null;

      session.trySetApduContext();

      expect(chainHost.seed, isNull);
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
        chainHost: chainHost,
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

    testWidgets('idle lock drops the host seed', (tester) async {
      idleSession.onSessionStarted();
      await tester.pump(const Duration(seconds: 6));

      expect(chainHost.locked, isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // dispose
  // ──────────────────────────────────────────────────────────────────

  group('dispose', () {
    test('unsubscribes from the APDU stream', () async {
      session.blePeripheral = blePeripheral;
      session.dispose();

      blePeripheral.addApduData(
          ApduCommand(cla: Cla.global, ins: Ins.getVersion, p1: 0, p2: 0)
              .toBytes());
      await Future<void>.delayed(Duration.zero);

      expect(blePeripheral.sentResponses, isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // APDU dispatch — chain commands
  // ──────────────────────────────────────────────────────────────────

  group('chain dispatch', () {
    setUp(() {
      session.blePeripheral = blePeripheral;
    });

    int lastSw() =>
        ApduResponse.fromBytes(blePeripheral.sentResponses.single).statusWord;

    ApduCommand ethSign() => ApduCommand(
        cla: Cla.os, ins: Ins.ethSign, p1: 0x00, p2: 0x00, data: Uint8List(1));

    test('locked wallet refuses a chain command with 6985', () async {
      await session.onApduCommand(ethSign().toBytes(), null);

      expect(lastSw(), Sw.securityStatusNotSatisfied);
      expect(chainHost.submitted, isEmpty);
      expect(chainHost.openedApps, isEmpty);
    });

    test('unavailable host refuses a chain command with 6D00', () async {
      chainHost.available = false;

      await session.onApduCommand(ethSign().toBytes(), 'seed-hex');

      expect(lastSw(), Sw.insNotSupported);
      expect(chainHost.submitted, isEmpty);
    });

    test('a non-terminal host reply refuses with 6D00', () async {
      chainHost.reply = const ChainHostStatus('finished');

      await session.onApduCommand(ethSign().toBytes(), 'seed-hex');

      expect(lastSw(), Sw.insNotSupported);
    });

    test('host emit is written to the wallet verbatim', () async {
      final payload = Uint8List.fromList([0x01, 0x02, 0x90, 0x00]);
      chainHost.reply = ChainHostEmit(payload);

      await session.onApduCommand(ethSign().toBytes(), 'seed-hex');

      expect(blePeripheral.sentResponses.single, payload);
      expect(chainHost.openedApps, ['openledger.ethereum']);
    });

    test('BTC and Sui commands open their own module', () async {
      chainHost.reply = ChainHostEmit(Uint8List.fromList([0x90, 0x00]));

      await session.onApduCommand(
          ApduCommand(
                  cla: Cla.bitcoin, ins: Ins.btcGetWalletPublicKey, p1: 0, p2: 0)
              .toBytes(),
          'seed-hex');
      await session.onApduCommand(
          ApduCommand(cla: Cla.sui, ins: Ins.suiGetPublicKey, p1: 0, p2: 0)
              .toBytes(),
          'seed-hex');

      expect(chainHost.openedApps, ['openledger.bitcoin', 'openledger.sui']);
      expect(chainHost.submitted.length, 2);
    });

    test('Solana and Tron modules follow the opened app', () async {
      chainHost.reply = ChainHostEmit(Uint8List.fromList([0x90, 0x00]));
      apduHandler.setCurrentApp(LedgerApp.solana);
      await session.onApduCommand(
          ApduCommand(cla: Cla.os, ins: Ins.solGetAddress, p1: 0, p2: 0)
              .toBytes(),
          'seed-hex');

      apduHandler.setCurrentApp(LedgerApp.tron);
      await session.onApduCommand(
          ApduCommand(cla: Cla.os, ins: Ins.tronSignTx, p1: 0, p2: 0).toBytes(),
          'seed-hex');

      expect(chainHost.openedApps, ['openledger.solana', 'openledger.tron']);
    });

    test('a sign review parks a pending request and sends nothing', () async {
      chainHost.reply = ChainHostReview(
        reviewId: 7,
        address: '0xabc',
        path: "m/44'/60'/0'/0/0",
        network: 'ethereum',
        actionType: 'sign',
        payloadHex: 'f86c',
        document: const {
          'sections': [
            {
              'title_key': 'review.section.transaction',
              'fields': [
                {
                  'label_key': 'review.field.to',
                  'value': {'type': 'address', 'value': '0xdef'},
                },
              ],
            },
          ],
        },
      );

      var pendingCalled = false;
      signConfirmation.onRequestPending = () => pendingCalled = true;

      await session.onApduCommand(ethSign().toBytes(), 'seed-hex');

      expect(pendingCalled, isTrue);
      expect(blePeripheral.sentResponses, isEmpty);
      final req = signConfirmation.pendingRequest!;
      expect(req.chainReviewId, 7);
      expect(req.chain, 'eth_tx');
      expect(req.signingAddress, '0xabc');
      expect(req.parsedData!['to'], '0xdef');
    });

    test('an address review parks a pending address request', () async {
      chainHost.reply = const ChainHostReview(
        reviewId: 11,
        address: '0xabc',
        path: "m/44'/60'/0'/0/0",
        network: 'ethereum',
        actionType: 'display_address',
        payloadHex: '',
        document: {},
      );

      var pendingCalled = false;
      signConfirmation.onAddressRequestPending = () => pendingCalled = true;

      await session.onApduCommand(
          ApduCommand(cla: Cla.os, ins: Ins.getPublicKey, p1: 0x01, p2: 0)
              .toBytes(),
          'seed-hex');

      expect(pendingCalled, isTrue);
      expect(signConfirmation.pendingAddressRequest, isNotNull);
      expect(signConfirmation.pendingAddressRequest!.address, '0xabc');
      expect(signConfirmation.pendingAddressRequest!.chainReviewId, 11);
      expect(blePeripheral.sentResponses, isEmpty);
    });

    test('resolveChainReview hands the id back to the host', () {
      chainHost.resolveBytes = Uint8List.fromList([0x90, 0x00]);

      final bytes = session.resolveChainReview(7, approved: true);

      expect(bytes, Uint8List.fromList([0x90, 0x00]));
      expect(chainHost.resolvedIds, [7]);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // APDU dispatch — OS / app frames
  // ──────────────────────────────────────────────────────────────────

  group('OS / app dispatch', () {
    setUp(() {
      session.blePeripheral = blePeripheral;
    });

    test('GET_APP_AND_VERSION is answered by the local table', () async {
      await session.onApduCommand(
          ApduCommand(cla: Cla.global, ins: Ins.getVersion, p1: 0, p2: 0)
              .toBytes(),
          'seed-hex');

      expect(blePeripheral.sentResponses.single, isNotEmpty);
      expect(chainHost.submitted, isEmpty);
    });

    test('OPEN_APP switches the table without reaching the host', () async {
      await session.onApduCommand(
          ApduCommand(
            cla: Cla.os,
            ins: Ins.openApp,
            p1: 0,
            p2: 0,
            data: Uint8List.fromList('Solana'.codeUnits),
          ).toBytes(),
          'seed-hex');

      expect(apduHandler.currentApp, LedgerApp.solana);
      expect(chainHost.submitted, isEmpty);
    });

    test('an INS the opened app table does not own is refused with 6D00',
        () async {
      apduHandler.setCurrentApp(LedgerApp.solana);

      await session.onApduCommand(
          const ApduCommand(cla: Cla.os, ins: 0xFF, p1: 0, p2: 0).toBytes(),
          'seed-hex');

      expect(
          ApduResponse.fromBytes(blePeripheral.sentResponses.single).statusWord,
          Sw.insNotSupported);
      expect(chainHost.submitted, isEmpty);
    });
  });
}
