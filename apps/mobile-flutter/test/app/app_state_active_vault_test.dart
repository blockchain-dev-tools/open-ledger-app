/// Regression tests for AppState wiring.
///
/// - `onActiveVaultChanged` (T-015 #2): switching or removing the active vault
///   must drop the previous vault's in-memory signing history and hydrate the
///   new vault's persisted records; keeping the old list would let the next
///   sign persist one vault's records into another vault's slot.
/// - `setBleDeviceName` (T-013): a rename must persist and reach the advertiser.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/app/app_state.dart';
import 'package:open_ledger_app/core/interfaces/ble_peripheral.dart';
import 'package:open_ledger_app/core/interfaces/history_repository.dart';
import 'package:open_ledger_app/core/interfaces/settings_repository.dart';
import 'package:open_ledger_app/core/models/ble_types.dart';
import 'package:open_ledger_app/core/models/launcher_disguise.dart';
import 'package:open_ledger_app/core/models/signature_record.dart';
import 'package:open_ledger_app/services/settings_service.dart';

import '../support/fake_wallet_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// Fakes
// ═══════════════════════════════════════════════════════════════════════

/// Wallet fake whose active vault and seed can be changed on demand, firing
/// the callback [AppState] wires in [AppState.resolveWallet].
class _ScriptedWalletService extends FakeWalletService {
  String _vaultId = 'v1';
  String _seed = 'seed-v1';

  @override
  String? get activeVaultId => _vaultId;

  @override
  String? get seedHex => _seed;

  @override
  bool get isUnlocked => true;

  /// Model a switch/removal: the wallet commits the new active vault first,
  /// then notifies its listener.
  void switchTo(String vaultId, String seed) {
    _vaultId = vaultId;
    _seed = seed;
    onActiveVaultChanged?.call();
  }
}

/// Minimal settings repository — [AppState] only needs a service instance.
class _NoopSettingsRepository implements ISettingsRepository {
  final List<String> setBleNameCalls = [];

  @override
  Future<SettingsData> loadSettings() async => const SettingsData();

  @override
  Future<void> setThemeMode(ThemeMode mode) async {}

  @override
  Future<void> setLocale(Locale locale) async {}

  @override
  Future<void> setStorePassphrase(bool value) async {}

  @override
  Future<void> setLauncherDisguise(LauncherDisguise value) async {}

  @override
  Future<void> setBleName(String name) async => setBleNameCalls.add(name);
}

/// Peripheral fake recording the name/state transitions a rename triggers.
class _FakePeripheral implements IBlePeripheral {
  BleState _state = BleState.idle;
  String _deviceName = defaultBleDeviceName;
  final List<String> calls = [];

  @override
  BleState get state => _state;

  @override
  String get deviceName => _deviceName;

  @override
  int get mtu => 185;

  @override
  Stream<Uint8List> get apduStream => const Stream.empty();

  @override
  Stream<BleState> get stateStream => const Stream.empty();

  @override
  Stream<String> get logStream => const Stream.empty();

  /// Put the fake into the state a live advertiser would report.
  void markBroadcasting() => _state = BleState.broadcasting;

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
  Future<void> setDeviceName(String name) async {
    calls.add('setDeviceName:$name');
    _deviceName = name;
  }

  @override
  Future<void> sendApduResponse(Uint8List response) async {}

  @override
  void dispose() {}
}

/// Per-vault in-memory history backend that records every load.
class _FakeHistoryRepository implements IHistoryRepository {
  _FakeHistoryRepository(this._byVault);

  final Map<String, List<SignatureRecord>> _byVault;
  final List<String> loadedVaultIds = [];
  final List<String> loadedSeeds = [];

  @override
  Future<List<SignatureRecord>> load(String vaultId, String seedHex) async {
    loadedVaultIds.add(vaultId);
    loadedSeeds.add(seedHex);
    return _byVault[vaultId] ?? const [];
  }

  @override
  Future<void> save(
      List<SignatureRecord> records, String vaultId, String seedHex) async {}

  @override
  Future<void> removeVaults(Iterable<String> vaultIds) async {}

  @override
  Future<void> clear() async {}
}

SignatureRecord _record(String address) => SignatureRecord(
      timestamp: DateTime(2026, 10, 25),
      chain: 'ethereum',
      derivationPath: "m/44'/60'/0'/0/0",
      signingAddress: address,
      payloadHex: '00',
      isApproved: true,
      signatureHex: 'ff',
      statusWord: 0x9000,
    );

List<String> _addresses(AppState state) =>
    state.signHistory.map((r) => r.signingAddress).toList();

void main() {
  late _ScriptedWalletService wallet;
  late _FakeHistoryRepository history;
  late _NoopSettingsRepository settingsRepo;
  late AppState appState;

  setUp(() async {
    wallet = _ScriptedWalletService();
    settingsRepo = _NoopSettingsRepository();
    appState = AppState(
      settingsService: SettingsService(repo: settingsRepo),
    );
    await appState.resolveWallet(wallet);

    history = _FakeHistoryRepository({
      'v1': [_record('0xaaa')],
      'v2': [_record('0xbbb'), _record('0xccc')],
    });
    appState.attachHistoryRepository(history);
  });

  tearDown(() => appState.dispose());

  test('active-vault change reloads history for the new vault only', () async {
    await appState.loadHistory();
    expect(_addresses(appState), ['0xaaa']);
    expect(history.loadedVaultIds, ['v1']);

    // Switch the wallet's active vault; the callback must reset the loaded
    // marker and re-hydrate from the new vault.
    wallet.switchTo('v2', 'seed-v2');
    await pumpEventQueue();

    expect(history.loadedVaultIds, ['v1', 'v2']);
    expect(history.loadedSeeds.last, 'seed-v2');
    // The previous vault's records are gone from memory — not merged.
    expect(_addresses(appState), ['0xbbb', '0xccc']);
  });

  group('setBleDeviceName', () {
    test('persists the name and restarts a live advertiser', () async {
      final peripheral = _FakePeripheral()..markBroadcasting();
      appState.blePeripheral = peripheral;

      await appState.setBleDeviceName('MyLedger');

      // Persisted and applied, then the live advertiser is restarted so the
      // new name reaches the air immediately.
      expect(settingsRepo.setBleNameCalls, ['MyLedger']);
      expect(appState.settingsService.bleName, 'MyLedger');
      expect(peripheral.deviceName, 'MyLedger');
      expect(peripheral.calls,
          ['setDeviceName:MyLedger', 'stopAdvertising', 'startAdvertising']);
      expect(peripheral.state, BleState.broadcasting);
    });

    test('does not restart an idle advertiser', () async {
      final peripheral = _FakePeripheral();
      appState.blePeripheral = peripheral;

      await appState.setBleDeviceName('MyLedger');

      expect(peripheral.deviceName, 'MyLedger');
      expect(peripheral.calls, ['setDeviceName:MyLedger']);
      expect(peripheral.state, BleState.idle);
    });
  });
}
