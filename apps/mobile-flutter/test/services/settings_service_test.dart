/// Unit tests for [SettingsService].
///
/// Covers default values, persistence delegation, theme toggling,
/// locale/flag setters, load error resilience, and getter correctness.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/interfaces/launcher_disguise.dart';
import 'package:open_ledger_app/core/interfaces/settings_repository.dart';
import 'package:open_ledger_app/core/models/ble_types.dart';
import 'package:open_ledger_app/core/models/launcher_disguise.dart';
import 'package:open_ledger_app/services/settings_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// Hand-written mock ISettingsRepository with call tracking
// ═══════════════════════════════════════════════════════════════════════

class _MockSettingsRepo implements ISettingsRepository {
  /// The data returned by [loadSettings]. Set before each test.
  SettingsData loadResult = const SettingsData();

  /// Whether [loadSettings] should throw.
  bool loadThrows = false;

  // ── Call tracking ──────────────────────────────────────────────────

  final List<ThemeMode> setThemeModeCalls = [];
  final List<Locale> setLocaleCalls = [];
  final List<bool> setStorePassphraseCalls = [];
  final List<LauncherDisguise> setLauncherDisguiseCalls = [];
  final List<String> setBleNameCalls = [];
  int loadSettingsCallCount = 0;

  // ── ISettingsRepository ────────────────────────────────────────────

  @override
  Future<SettingsData> loadSettings() async {
    loadSettingsCallCount++;
    if (loadThrows) {
      throw Exception('Storage unavailable');
    }
    return loadResult;
  }

  @override
  Future<void> setThemeMode(ThemeMode mode) async {
    setThemeModeCalls.add(mode);
  }

  @override
  Future<void> setLocale(Locale locale) async {
    setLocaleCalls.add(locale);
  }

  @override
  Future<void> setStorePassphrase(bool value) async {
    setStorePassphraseCalls.add(value);
  }

  @override
  Future<void> setLauncherDisguise(LauncherDisguise value) async {
    setLauncherDisguiseCalls.add(value);
  }

  @override
  Future<void> setBleName(String name) async {
    setBleNameCalls.add(name);
  }
}

/// Hand-written fake [ILauncherDisguise] — records every apply call instead
/// of touching the OS.
class _FakeDisguise implements ILauncherDisguise {
  final List<LauncherDisguise> applyCalls = [];

  @override
  Future<void> apply(LauncherDisguise disguise) async {
    applyCalls.add(disguise);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════

/// Returns true if the [ChangeNotifier] fired at least one notification
/// between [action] and the returned moment.
Future<bool> didNotify(ChangeNotifier service, Future<void> Function() action) async {
  var notified = false;
  void listener() {
    notified = true;
  }

  service.addListener(listener);
  await action();
  // Pump microtask queue so any async notifications settle.
  await Future<void>.delayed(Duration.zero);
  service.removeListener(listener);
  return notified;
}

void main() {
  late _MockSettingsRepo repo;
  late SettingsService service;

  setUp(() {
    repo = _MockSettingsRepo();
    service = SettingsService(repo: repo);
  });

  // ═══════════════════════════════════════════════════════════════════
  // 1. Default values
  // ═══════════════════════════════════════════════════════════════════

  test('default values: themeMode=system, locale=en, storePassphrase=false', () {
    expect(service.themeMode, ThemeMode.system);
    expect(service.locale, const Locale('en'));
    expect(service.storePassphrase, isFalse);
  });

  // ═══════════════════════════════════════════════════════════════════
  // 2. loadSettings updates all fields from repo and fires notify
  // ═══════════════════════════════════════════════════════════════════

  test('loadSettings updates all fields from repo and fires notify', () async {
    repo.loadResult = const SettingsData(
      themeMode: ThemeMode.light,
      locale: Locale('ja'),
      storePassphrase: true,
    );

    final notified = await didNotify(service, () => service.loadSettings());

    expect(notified, isTrue);
    expect(service.themeMode, ThemeMode.light);
    expect(service.locale, const Locale('ja'));
    expect(service.storePassphrase, isTrue);
    expect(repo.loadSettingsCallCount, 1);
  });

  // ═══════════════════════════════════════════════════════════════════
  // 3. setThemeMode updates the mode and persists
  // ═══════════════════════════════════════════════════════════════════

  test('setThemeMode updates the mode and persists', () {
    // Default is system.
    expect(service.themeMode, ThemeMode.system);

    service.setThemeMode(ThemeMode.light);

    expect(service.themeMode, ThemeMode.light);
    expect(repo.setThemeModeCalls, [ThemeMode.light]);
  });

  // ═══════════════════════════════════════════════════════════════════
  // 4. setThemeMode supports ThemeMode.system
  // ═══════════════════════════════════════════════════════════════════

  test('setThemeMode supports ThemeMode.system and persists', () {
    service.setThemeMode(ThemeMode.system);

    expect(service.themeMode, ThemeMode.system);
    expect(repo.setThemeModeCalls, [ThemeMode.system]);
  });

  // ═══════════════════════════════════════════════════════════════════
  // 5. setLocale updates locale and persists
  // ═══════════════════════════════════════════════════════════════════

  test('setLocale updates locale and persists', () {
    const zh = Locale('zh', 'CN');

    service.setLocale(zh);

    expect(service.locale, zh);
    expect(repo.setLocaleCalls, [zh]);
  });

  // ═══════════════════════════════════════════════════════════════════
  // 6. setStorePassphrase updates and persists
  // ═══════════════════════════════════════════════════════════════════

  test('setStorePassphrase updates and persists', () {
    service.setStorePassphrase(true);

    expect(service.storePassphrase, isTrue);
    expect(repo.setStorePassphraseCalls, [true]);

    service.setStorePassphrase(false);

    expect(service.storePassphrase, isFalse);
    expect(repo.setStorePassphraseCalls, [true, false]);
  });

  // ═══════════════════════════════════════════════════════════════════
  // 7. loadSettings handles repo returning defaults gracefully
  // ═══════════════════════════════════════════════════════════════════

  test('loadSettings handles repo returning defaults gracefully', () async {
    // The mock default SettingsData is already all defaults.
    await service.loadSettings();

    // No overrides means defaults remain.
    expect(service.themeMode, ThemeMode.system);
    expect(service.locale, const Locale('en'));
    expect(service.storePassphrase, isFalse);
    expect(repo.loadSettingsCallCount, 1);
  });

  // ═══════════════════════════════════════════════════════════════════
  // 7b. loadSettings handles repo throwing
  // ═══════════════════════════════════════════════════════════════════

  test('loadSettings keeps defaults when repo throws', () async {
    repo.loadThrows = true;

    final notified = await didNotify(service, () => service.loadSettings());

    // Should still fire notify even on error path.
    expect(notified, isTrue);
    // Defaults preserved.
    expect(service.themeMode, ThemeMode.system);
    expect(service.locale, const Locale('en'));
    expect(service.storePassphrase, isFalse);
  });

  // ═══════════════════════════════════════════════════════════════════
  // 8. Getters return current values after load
  // ═══════════════════════════════════════════════════════════════════

  test('getters return current values after load', () async {
    repo.loadResult = const SettingsData(
      themeMode: ThemeMode.light,
      locale: Locale('zh', 'CN'),
      storePassphrase: true,
    );
    await service.loadSettings();

    // After load, getters should reflect loaded data.
    expect(service.themeMode, ThemeMode.light);
    expect(service.locale, const Locale('zh', 'CN'));
    expect(service.storePassphrase, isTrue);

    // And a subsequent set changes the getter.
    service.setLocale(const Locale('en'));
    expect(service.locale, const Locale('en'));
  });

  // ═══════════════════════════════════════════════════════════════════
  // Bonus: notifyListeners is called on every setter
  // ═══════════════════════════════════════════════════════════════════

  test('notifyListeners fires on setThemeMode', () {
    var notified = false;
    service.addListener(() => notified = true);

    service.setThemeMode(ThemeMode.light);

    expect(notified, isTrue);
    service.removeListener(() => notified = true);
  });

  test('notifyListeners fires on setLocale', () {
    var notified = false;
    service.addListener(() => notified = true);

    service.setLocale(const Locale('ja'));

    expect(notified, isTrue);
  });

  test('notifyListeners fires on setStorePassphrase', () {
    var notified = false;
    service.addListener(() => notified = true);

    service.setStorePassphrase(true);

    expect(notified, isTrue);
  });

  // ═══════════════════════════════════════════════════════════════════
  // 9. Launcher disguise (ADR-012)
  // ═══════════════════════════════════════════════════════════════════

  test('default launcherDisguise is standard', () {
    expect(service.launcherDisguise, LauncherDisguise.standard);
  });

  test('loadSettings restores the persisted disguise', () async {
    repo.loadResult = const SettingsData(
      launcherDisguise: LauncherDisguise.calculator,
    );

    await service.loadSettings();

    expect(service.launcherDisguise, LauncherDisguise.calculator);
  });

  test('loadSettings keeps standard when the repo throws', () async {
    repo.loadThrows = true;

    await service.loadSettings();

    expect(service.launcherDisguise, LauncherDisguise.standard);
  });

  test('setLauncherDisguise persists, applies to the OS and notifies',
      () async {
    final disguise = _FakeDisguise();
    final svc = SettingsService(repo: repo, disguise: disguise);
    var notified = false;
    svc.addListener(() => notified = true);

    await svc.setLauncherDisguise(LauncherDisguise.calculator);

    expect(svc.launcherDisguise, LauncherDisguise.calculator);
    expect(repo.setLauncherDisguiseCalls, [LauncherDisguise.calculator]);
    expect(disguise.applyCalls, [LauncherDisguise.calculator]);
    expect(notified, isTrue);
  });

  test('setLauncherDisguise is a no-op for the current value', () async {
    final disguise = _FakeDisguise();
    final svc = SettingsService(repo: repo, disguise: disguise);
    var notified = false;
    svc.addListener(() => notified = true);

    await svc.setLauncherDisguise(LauncherDisguise.standard);

    expect(repo.setLauncherDisguiseCalls, isEmpty);
    expect(disguise.applyCalls, isEmpty);
    expect(notified, isFalse);
  });

  test('setLauncherDisguise persists even without a platform manager',
      () async {
    // The gallery / tests construct the service without a disguise manager.
    await service.setLauncherDisguise(LauncherDisguise.calculator);

    expect(service.launcherDisguise, LauncherDisguise.calculator);
    expect(repo.setLauncherDisguiseCalls, [LauncherDisguise.calculator]);
  });

  // ═══════════════════════════════════════════════════════════════════
  // 10. Advertised BLE name
  // ═══════════════════════════════════════════════════════════════════

  test('default bleName is the shared default', () {
    expect(service.bleName, defaultBleDeviceName);
  });

  test('loadSettings restores the persisted BLE name', () async {
    repo.loadResult = const SettingsData(bleName: 'MyLedger');

    await service.loadSettings();

    expect(service.bleName, 'MyLedger');
  });

  test('setBleName updates the name, persists and notifies', () {
    var notified = false;
    service.addListener(() => notified = true);

    service.setBleName('MyLedger');

    expect(service.bleName, 'MyLedger');
    expect(repo.setBleNameCalls, ['MyLedger']);
    expect(notified, isTrue);
  });
}
