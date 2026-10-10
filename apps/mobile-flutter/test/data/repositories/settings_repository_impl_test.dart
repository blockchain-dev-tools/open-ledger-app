import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_ledger_app/core/interfaces/settings_repository.dart';
import 'package:open_ledger_app/data/repositories/settings_repository_impl.dart';

void main() {
  late SettingsRepositoryImpl repo;

  /// Helper: set mock values then load settings immediately.
  Future<SettingsData> loadWith(Map<String, Object> initialValues) async {
    SharedPreferences.setMockInitialValues(initialValues);
    // getInstance caches — after setMockInitialValues we need a fresh handle.
    // Flutter test framework handles this: each call to setMockInitialValues
    // resets the mock store automatically.
    repo = SettingsRepositoryImpl();
    return repo.loadSettings();
  }

  group('SettingsRepositoryImpl', () {
    // ── loadSettings ──────────────────────────────────────────────────

    test('loadSettings returns defaults when nothing stored', () async {
      final settings = await loadWith({});
      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.locale, const Locale('en'));
      expect(settings.storePassphrase, false);
    });

    test('loadSettings returns dark theme when "dark" stored', () async {
      final settings =
          await loadWith({'settings.themeMode': 'dark'});
      expect(settings.themeMode, ThemeMode.dark);
    });

    test('loadSettings returns light theme when "light" stored', () async {
      final settings =
          await loadWith({'settings.themeMode': 'light'});
      expect(settings.themeMode, ThemeMode.light);
    });

    test('loadSettings returns en locale when "en" stored', () async {
      final settings = await loadWith({'settings.locale': 'en'});
      expect(settings.locale, const Locale('en'));
    });

    test('loadSettings returns zh locale when "zh" stored', () async {
      final settings = await loadWith({'settings.locale': 'zh'});
      expect(settings.locale, const Locale('zh'));
    });

    test('loadSettings returns storePassphrase=true when true stored',
        () async {
      final settings =
          await loadWith({'settings.storePassphrase': true});
      expect(settings.storePassphrase, true);
    });

    // ── setThemeMode ──────────────────────────────────────────────────

    test('setThemeMode(dark) persists "dark"', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      repo = SettingsRepositoryImpl();

      await repo.setThemeMode(ThemeMode.dark);
      // Reload to verify persistence
      final stored = prefs.getString('settings.themeMode');
      expect(stored, 'dark');
    });

    test('setThemeMode(light) persists "light"', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      repo = SettingsRepositoryImpl();

      await repo.setThemeMode(ThemeMode.light);
      final stored = prefs.getString('settings.themeMode');
      expect(stored, 'light');
    });

    // ── setLocale ─────────────────────────────────────────────────────

    test('setLocale(en) persists "en"', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      repo = SettingsRepositoryImpl();

      await repo.setLocale(const Locale('en'));
      final stored = prefs.getString('settings.locale');
      expect(stored, 'en');
    });

    // ── setStorePassphrase ────────────────────────────────────────────

    test('setStorePassphrase(true) persists true', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      repo = SettingsRepositoryImpl();

      await repo.setStorePassphrase(true);
      final stored = prefs.getBool('settings.storePassphrase');
      expect(stored, true);
    });
  });
}
