import 'package:flutter/foundation.dart';

import '../models/ble_types.dart';
import '../models/chain.dart';

/// Per-chain BLE control surfaced on the Vault screen.
///
/// The device runs a single BLE peripheral and exposes exactly one Ledger
/// "app" at a time, so this control models one open app plus one shared
/// [BleState]:
///
/// - [startChain] opens that chain's app and starts advertising;
/// - [startChain] on a different chain while broadcasting = hot app switch
///   (hosts pick it up via GET_APP_AND_VERSION, no reconnect);
/// - [stop] closes the app and stops advertising (back to the dashboard).
///
/// Implementations live in the app assembly layer (production adapter over
/// `AppState`) and in the gallery (fake). The UI depends only on this
/// interface, never on either concrete holder.
abstract class IChainBleControl implements Listenable {
  /// Shared peripheral state (`idle` when nothing is broadcasting).
  BleState get bleState;

  /// The chain whose Ledger app is currently open, or `null` when the device
  /// sits on the dashboard (nothing opened, nothing broadcasting).
  ///
  /// This is "which app is open", NOT "is the radio on": the two move
  /// together for start/stop, but a radio error must not make the open app
  /// disappear. Implementations must return `null` exactly when no app is
  /// open, so the UI can trust it to decide what to draw.
  Chain? get activeChain;

  /// Whether a sign request is awaiting the user's on-device decision.
  /// Chain switching must be disabled while this is true (contract I2/I9).
  bool get isSignPending;

  /// Open [chain]'s Ledger app and start advertising; hot-switches the app
  /// if another chain is already active.
  Future<void> startChain(Chain chain);

  /// Close the app and stop advertising, returning the device to the
  /// dashboard.
  Future<void> stop();

  /// Release listeners and stream subscriptions. On the interface (not just
  /// [Listenable]) so owners can dispose any implementation without knowing
  /// its concrete type.
  void dispose();
}
