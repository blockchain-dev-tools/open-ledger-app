import 'package:flutter/material.dart';

import '../models/launcher_disguise.dart';

/// Abstract repository for app settings persistence.
///
/// Implemented by [SettingsRepositoryImpl] in `lib/data/repositories/`.
/// SettingsService depends on this interface, never on concrete storage.
abstract class ISettingsRepository {
  /// Load all persisted settings. Returns default values if nothing stored.
  Future<SettingsData> loadSettings();

  /// Persist the theme mode.
  Future<void> setThemeMode(ThemeMode mode);

  /// Persist the display locale.
  Future<void> setLocale(Locale locale);

  /// Persist the store-passphrase preference.
  Future<void> setStorePassphrase(bool value);

  /// Persist the launcher disguise choice (ADR-012).
  Future<void> setLauncherDisguise(LauncherDisguise value);
}

/// Immutable snapshot of all app settings.
class SettingsData {
  final ThemeMode themeMode;
  final Locale locale;
  final bool storePassphrase;
  final LauncherDisguise launcherDisguise;

  const SettingsData({
    this.themeMode = ThemeMode.dark,
    this.locale = const Locale('en'),
    this.storePassphrase = false,
    this.launcherDisguise = LauncherDisguise.standard,
  });
}
