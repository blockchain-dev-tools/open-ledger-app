import 'package:flutter/material.dart';

import '../core/interfaces/launcher_disguise.dart';
import '../core/interfaces/settings_repository.dart';
import '../core/models/ble_types.dart';
import '../core/models/launcher_disguise.dart';

/// Manages app settings — theme, locale, store-passphrase preference,
/// advertised BLE name, launcher disguise (ADR-012).
///
/// All persistence I/O is delegated to [ISettingsRepository]; the OS-facing
/// side of the disguise goes through [ILauncherDisguise] (no-op off Android).
/// This service is pure business logic: it owns the in-memory state,
/// calls persistence, and fires [notifyListeners] on every change.
///
/// Mirrors the settings slice of `AppState` in the pre-refactor codebase.
class SettingsService extends ChangeNotifier {
  final ISettingsRepository _repo;

  /// Applies the disguise to the OS. Nullable so tests and the gallery can
  /// run without a platform channel; persistence still works.
  final ILauncherDisguise? _disguise;

  SettingsService({required ISettingsRepository repo, ILauncherDisguise? disguise})
      : _repo = repo, // ignore: prefer_initializing_formals
        _disguise = disguise; // ignore: prefer_initializing_formals

  // ── Theme ──────────────────────────────────────────────────────────

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  /// Sets the theme mode ([ThemeMode.system] / light / dark) and persists
  /// the choice.
  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _repo.setThemeMode(_themeMode);
    notifyListeners();
  }

  // ── Locale / Language ──────────────────────────────────────────────

  Locale _locale = const Locale('en');
  Locale get locale => _locale;

  /// Sets the display language and persists the choice.
  void setLocale(Locale locale) {
    _locale = locale;
    _repo.setLocale(locale);
    notifyListeners();
  }

  // ── Store Passphrase ───────────────────────────────────────────────

  bool _storePassphrase = false;
  bool get storePassphrase => _storePassphrase;

  /// Sets whether the BIP-39 passphrase should be remembered.
  void setStorePassphrase(bool value) {
    _storePassphrase = value;
    _repo.setStorePassphrase(value);
    notifyListeners();
  }

  // ── Advertised BLE name ────────────────────────────────────────────

  String _bleName = defaultBleDeviceName;
  String get bleName => _bleName;

  /// Sets the advertised BLE device name and persists it.
  ///
  /// Applying it to the running advertiser is the caller's job
  /// (`AppState.setBleDeviceName`); this service only owns the setting.
  void setBleName(String name) {
    _bleName = name;
    _repo.setBleName(_bleName);
    notifyListeners();
  }

  // ── Launcher Disguise (ADR-012) ────────────────────────────────────

  LauncherDisguise _launcherDisguise = LauncherDisguise.standard;
  LauncherDisguise get launcherDisguise => _launcherDisguise;

  /// Switches the launcher identity (icon + label) and persists the choice.
  ///
  /// Persistence happens before the OS call so the UI state stays consistent
  /// even if the platform side fails silently. Re-selecting the current value
  /// is a no-op.
  Future<void> setLauncherDisguise(LauncherDisguise value) async {
    if (value == _launcherDisguise) return;
    _launcherDisguise = value;
    await _repo.setLauncherDisguise(value);
    await _disguise?.apply(value);
    notifyListeners();
  }

  // ── Load persisted settings ────────────────────────────────────────

  /// Reads saved preferences from the repository.
  /// Call on startup before building the widget tree.
  Future<void> loadSettings() async {
    try {
      final data = await _repo.loadSettings();
      _themeMode = data.themeMode;
      _locale = data.locale;
      _storePassphrase = data.storePassphrase;
      _launcherDisguise = data.launcherDisguise;
      _bleName = data.bleName;
    } catch (_) {
      // Repository unavailable (e.g. test environment).
      // Keep default values.
    }
    notifyListeners();
  }

  // ── Locale parsing utility ─────────────────────────────────────────

  /// Parses a locale string like "en", "zh_CN", "ja" into a [Locale].
  // ignore: unused_element
  Locale _parseLocale(String s) {
    final parts = s.split('_');
    if (parts.length == 2) {
      return Locale(parts[0], parts[1]);
    }
    return Locale(parts[0]);
  }
}
