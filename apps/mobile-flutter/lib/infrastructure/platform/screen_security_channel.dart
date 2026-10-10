import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/interfaces/screen_security.dart';

/// Android implementation of [IScreenSecurity] (ADR-011 §6).
///
/// Flips `WindowManager.LayoutParams.FLAG_SECURE` through a method channel
/// handled by `MainActivity`. Everywhere else — and whenever the channel is
/// unavailable (tests, gallery, a detached engine) — it degrades to a no-op,
/// so a privacy nicety can never break the export flow.
class ScreenSecurityChannel implements IScreenSecurity {
  const ScreenSecurityChannel();

  static const MethodChannel _channel =
      MethodChannel('app.openledger/screen_security');

  @override
  Future<void> enable() => _set('enable');

  @override
  Future<void> disable() => _set('disable');

  Future<void> _set(String method) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>(method);
    } catch (_) {
      // No handler on this target — nothing to protect.
    }
  }
}
