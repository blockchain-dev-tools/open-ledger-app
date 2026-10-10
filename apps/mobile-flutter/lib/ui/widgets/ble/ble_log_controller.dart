import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/interfaces/ble_peripheral.dart';
import '../../../core/models/ble_log_entry.dart';
import '../../../protocols/apdu/apdu_decoder.dart';

/// Decodes and accumulates the BLE activity log for the whole app session.
///
/// Hoisted out of the former BLE tab when the controls moved onto the Vault
/// screen and the log became an overlay (bottom sheet): the subscriber now
/// outlives any single widget. One instance is owned by `MainScreen`.
///
/// APDU exchanges are sequential, so at most one [BleLogStatus.pending] row
/// exists at a time; the matching `APDU response:` / send-error line
/// resolves it in place. Fragment-level chatter is filtered by
/// [ApduLogDecoder].
class BleLogController extends ChangeNotifier {
  final IBlePeripheral _ble;
  final ApduLogDecoder _decoder = ApduLogDecoder();
  StreamSubscription<String>? _sub;

  final List<BleLogEntry> _entries = [];

  /// Most recent first — feed straight into a reversed list builder.
  List<BleLogEntry> get entries => List.unmodifiable(_entries.reversed);

  bool get isEmpty => _entries.isEmpty;

  BleLogController(this._ble) {
    _sub = _ble.logStream.listen((log) {
      final e = _decoder.decode(log);
      if (e == null) return; // fragment-level chatter — not shown
      _applyEntry(e);
      notifyListeners();
    });
  }

  /// Index of the pending "APDU response sending" row, or `null`.
  int? _pendingIndex;

  /// Appends, holds, or replaces a log entry according to its status.
  void _applyEntry(BleLogEntry e) {
    if (e.status == BleLogStatus.pending) {
      // A previous pending row that never resolved is marked stalled before
      // a new in-flight row replaces it.
      final pi = _pendingIndex;
      if (pi != null && pi < _entries.length) {
        _entries[pi] = _entries[pi].copyWith(
          summary: '… no response (stalled)',
          status: BleLogStatus.error,
          level: BleLogLevel.warn,
        );
      }
      _entries.add(e);
      _pendingIndex = _entries.length - 1;
    } else if (e.status == BleLogStatus.success ||
        e.status == BleLogStatus.error) {
      // Resolve the pending row in place; append directly if none pending.
      final pi = _pendingIndex;
      if (pi != null && pi < _entries.length) {
        _entries[pi] = e;
        _pendingIndex = null;
      } else {
        _entries.add(e);
      }
    } else {
      _entries.add(e);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
