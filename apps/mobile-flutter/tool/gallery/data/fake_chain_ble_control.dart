import 'package:flutter/foundation.dart';

import 'package:open_ledger_app/core/interfaces/chain_ble_control.dart';
import 'package:open_ledger_app/core/models/ble_types.dart';
import 'package:open_ledger_app/core/models/chain.dart';

import 'fake_ble_peripheral.dart';

/// Gallery fake for [IChainBleControl] (ADR-005).
///
/// Wraps [FakeBlePeripheral] with the open-app value, modelling the real
/// device semantics: switching chains while broadcasting is a hot switch
/// (radio keeps running), and stopping closes the app and returns to the
/// dashboard. [activeChain] therefore means "which app is open" and is
/// `null` exactly when nothing is — matching the production adapter.
class FakeChainBleControl extends ChangeNotifier implements IChainBleControl {
  final FakeBlePeripheral ble;
  Chain? _activeChain;

  /// Gallery-only: when true all chain buttons render disabled, as if a
  /// TransactionScreen decision were pending.
  bool signPending;

  FakeChainBleControl({
    required this.ble,
    Chain? initialChain,
    this.signPending = false,
  }) : _activeChain = initialChain {
    ble.addListener(_onBle);
  }

  void _onBle() => notifyListeners();

  @override
  BleState get bleState => ble.state;

  @override
  Chain? get activeChain => _activeChain;

  @override
  bool get isSignPending => signPending;

  @override
  Future<void> startChain(Chain chain) async {
    final previous = _activeChain;
    _activeChain = chain;
    if (ble.state == BleState.idle) {
      await ble.startAdvertising();
    } else if (previous != null && previous != chain) {
      ble.emitLog('Current app: ${chain.ledgerApp.ledgerName}');
    }
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _activeChain = null;
    await ble.stopAdvertising();
    notifyListeners();
  }

  @override
  void dispose() {
    ble.removeListener(_onBle);
    super.dispose();
  }
}
