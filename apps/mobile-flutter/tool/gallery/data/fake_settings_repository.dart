import 'package:flutter/material.dart';

import 'package:open_ledger_app/core/interfaces/settings_repository.dart';
import 'package:open_ledger_app/core/models/launcher_disguise.dart';

/// In-memory [ISettingsRepository] for the gallery (ADR-005) — no storage,
/// no plugins, so the Settings tab preview can run a real [SettingsService]
/// while staying web-compatible.
class FakeSettingsRepository implements ISettingsRepository {
  ThemeMode themeMode;
  Locale locale;
  bool storePassphrase;
  LauncherDisguise launcherDisguise;

  FakeSettingsRepository({
    this.themeMode = ThemeMode.dark,
    this.locale = const Locale('en'),
    this.storePassphrase = false,
    this.launcherDisguise = LauncherDisguise.standard,
  });

  @override
  Future<SettingsData> loadSettings() async => SettingsData(
        themeMode: themeMode,
        locale: locale,
        storePassphrase: storePassphrase,
        launcherDisguise: launcherDisguise,
      );

  @override
  Future<void> setThemeMode(ThemeMode mode) async => themeMode = mode;

  @override
  Future<void> setLocale(Locale next) async => locale = next;

  @override
  Future<void> setStorePassphrase(bool value) async => storePassphrase = value;

  @override
  Future<void> setLauncherDisguise(LauncherDisguise value) async =>
      launcherDisguise = value;
}
