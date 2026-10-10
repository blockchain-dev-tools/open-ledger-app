import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/interfaces/settings_repository.dart';
import '../../core/models/launcher_disguise.dart';

/// [ISettingsRepository] implementation backed by [SharedPreferences].
///
/// Extracted from [AppState] — handles theme mode, locale, and
/// store-passphrase persistence. Contains zero business logic.
class SettingsRepositoryImpl implements ISettingsRepository {
  // ── Preferences keys ───────────────────────────────────────────────

  static const _keyThemeMode = 'settings.themeMode';
  static const _keyLocale = 'settings.locale';
  static const _keyStorePassphrase = 'settings.storePassphrase';
  static const _keyLauncherDisguise = 'settings.launcherDisguise';

  // ── ISettingsRepository ────────────────────────────────────────────

  @override
  Future<SettingsData> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final themeStr = prefs.getString(_keyThemeMode);
      final themeMode = switch (themeStr) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };

      final localeStr = prefs.getString(_keyLocale);
      Locale locale = const Locale('en');
      if (localeStr != null && localeStr.isNotEmpty) {
        locale = _parseLocale(localeStr);
      }

      final storePassphrase =
          prefs.getBool(_keyStorePassphrase) ?? false;

      final launcherDisguise =
          LauncherDisguise.fromId(prefs.getString(_keyLauncherDisguise));

      return SettingsData(
        themeMode: themeMode,
        locale: locale,
        storePassphrase: storePassphrase,
        launcherDisguise: launcherDisguise,
      );
    } catch (_) {
      // SharedPreferences unavailable (e.g. test environment).
      return const SettingsData();
    }
  }

  @override
  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      ThemeMode.dark => 'dark',
    });
  }

  @override
  Future<void> setLocale(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLocale, locale.toString());
  }

  @override
  Future<void> setStorePassphrase(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyStorePassphrase, value);
  }

  @override
  Future<void> setLauncherDisguise(LauncherDisguise value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLauncherDisguise, value.id);
  }

  // ── Helpers ────────────────────────────────────────────────────────

  Locale _parseLocale(String s) {
    final parts = s.split('_');
    if (parts.length == 2) {
      return Locale(parts[0], parts[1]);
    }
    return Locale(parts[0]);
  }
}
