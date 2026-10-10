/// Launcher-level disguise persona (ADR-012).
///
/// Controls which identity the Android launcher shows for this app —
/// icon + label only. Pure presentation: data, PIN and signing are
/// unaffected. Persists as `settings.launcherDisguise`.
enum LauncherDisguise {
  /// Real identity: Open Ledger App icon + name.
  standard,

  /// Calculator icon + localized "Calculator" name.
  calculator;

  /// Stable id used for storage and the method channel.
  String get id => name;

  static LauncherDisguise fromId(String? id) => switch (id) {
        'calculator' => LauncherDisguise.calculator,
        _ => LauncherDisguise.standard,
      };
}
