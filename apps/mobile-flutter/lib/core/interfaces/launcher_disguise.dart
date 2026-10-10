import '../models/launcher_disguise.dart';

/// Applies the launcher disguise to the OS (ADR-012).
///
/// Abstract so services depend on the contract rather than on an Android
/// method channel; targets without the mechanism (web, iOS, tests) implement
/// it as a no-op. The Android implementation toggles activity-alias enabled
/// state via [PackageManager] — the choice itself is persisted by
/// [ISettingsRepository], this only drives the OS.
abstract class ILauncherDisguise {
  /// Makes [disguise] the identity shown on the launcher. Fire-and-forget
  /// safe: failures degrade silently (the desktop keeps its previous icon).
  Future<void> apply(LauncherDisguise disguise);
}
