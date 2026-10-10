import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/interfaces/ble_peripheral.dart';
import '../core/interfaces/chain_ble_control.dart';
import '../core/models/ble_types.dart';
import '../core/models/chain.dart';
import 'app_state.dart';

/// Production [IChainBleControl] backed by [AppState].
///
/// Rebinds the BLE state stream when the assembly layer swaps the
/// peripheral, and forwards app/chain switches to `AppState.setCurrentApp`
/// — a hot switch: hosts pick up the new app through their next
/// GET_APP_AND_VERSION poll without reconnecting.
///
/// Chain → app mapping comes from the [Chain] registry, so this class holds
/// no per-chain knowledge of its own.
class ChainBleControlAdapter extends ChangeNotifier
    implements IChainBleControl {
  final AppState _appState;
  StreamSubscription<BleState>? _stateSub;
  IBlePeripheral? _boundPeripheral;

  ChainBleControlAdapter(this._appState) {
    _appState.addListener(_onAppState);
    _bind(_appState.blePeripheral);
  }

  void _onAppState() {
    if (_appState.blePeripheral != _boundPeripheral) {
      _bind(_appState.blePeripheral);
    }
    notifyListeners();
  }

  void _bind(IBlePeripheral? peripheral) {
    _stateSub?.cancel();
    _boundPeripheral = peripheral;
    if (peripheral != null) {
      _stateSub = peripheral.stateStream.listen((_) => notifyListeners());
    }
  }

  @override
  BleState get bleState => _appState.blePeripheral?.state ?? BleState.idle;

  @override
  Chain? get activeChain => _appState.currentApp?.chain;

  @override
  bool get isSignPending => _appState.pendingRequest != null;

  @override
  Future<void> startChain(Chain chain) async {
    _appState.setCurrentApp(chain.ledgerApp);
    await _appState.startBleAdvertising();
  }

  @override
  Future<void> stop() async {
    await _appState.stopBleAdvertising();
    // Back to the dashboard: nothing is open, so GET_APP_AND_VERSION reports
    // BOLOS and the UI shows no active chain — same as a real device.
    _appState.setCurrentApp(null);
  }

  @override
  void dispose() {
    _appState.removeListener(_onAppState);
    _stateSub?.cancel();
    super.dispose();
  }
}
