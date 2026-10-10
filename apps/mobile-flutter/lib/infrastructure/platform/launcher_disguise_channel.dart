import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/interfaces/launcher_disguise.dart';
import '../../core/models/launcher_disguise.dart';

/// Android implementation of [ILauncherDisguise] (ADR-012).
///
/// Asks `MainActivity` to toggle the enabled state of the two
/// activity-alias launcher entries. Everywhere else — and whenever the
/// channel is unavailable (tests, gallery, iOS) — it degrades to a no-op,
/// so a presentation-layer nicety can never break the app.
class LauncherDisguiseChannel implements ILauncherDisguise {
  const LauncherDisguiseChannel();

  static const MethodChannel _channel =
      MethodChannel('app.openledger/launcher_disguise');

  @override
  Future<void> apply(LauncherDisguise disguise) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('apply', {'disguise': disguise.id});
    } catch (e) {
      // No handler on this target — desktop keeps the previous identity.
      debugPrint('LauncherDisguiseChannel.apply failed: $e');
    }
  }
}
