import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../services/settings_service.dart';
import '../../../core/interfaces/wallet_service.dart';
import '../../../core/models/ble_types.dart';
import '../../../core/models/launcher_disguise.dart';
import '../../../app/app_state.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/neo_app_bar.dart';
import '../../widgets/common/neo_option_sheet.dart';
import 'components/about_card.dart';
import 'components/group_header.dart';
import 'components/settings_group.dart';
import 'components/settings_row.dart';

/// App settings: theme toggle, language selection, security options,
/// BLE device name configuration, and about section.
///
/// Ported from the original TypeScript implementation.
///
/// When [isTab] is true, renders as a scaffold-less content widget
/// (for use inside a bottom navigation tab). When false (default),
/// renders as a full-screen page with its own AppBar and back button.
class SettingsScreen extends StatefulWidget {
  final SettingsService? settingsService;
  final IWalletService? walletService;
  final AppState? appState;
  final bool isTab;

  /// Gallery-only: open the theme picker sheet on first frame so it can be
  /// reviewed/screenshot without a click. Production stays false.
  final bool previewThemeSheet;

  const SettingsScreen({
    super.key,
    this.settingsService,
    this.walletService,
    this.appState,
    this.isTab = false,
    this.previewThemeSheet = false,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Local tracking of the current BLE device name.
  String _bleName = defaultBleDeviceName;

  /// Currently selected theme mode (drives the theme sheet check mark).
  ThemeMode _themeMode = ThemeMode.dark;

  /// Currently selected locale (tracked for language tile subtitle).
  Locale _currentLocale = const Locale('en');

  /// Currently selected launcher disguise (tracked for the row subtitle).
  LauncherDisguise _launcherDisguise = LauncherDisguise.standard;

  /// Whether the **current session** has a stand-in one tier deeper.
  /// Session-relative: see [_refreshStandIn].
  bool _standInConfigured = false;

  @override
  void initState() {
    super.initState();
    _syncThemeMode();
    widget.settingsService?.addListener(_onSettingsChanged);
    _refreshStandIn();
    if (widget.previewThemeSheet) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showThemePicker();
      });
    }
  }

  /// Reads whether the current session has a stand-in configured one tier
  /// deeper. [IWalletService.hasStandIn] is session-relative — it reports the
  /// child tier (`depth + 1`) of the *current* session — so a stand-in session
  /// shows its own nested status (and "Not set up" when it has no child), while
  /// a primary session shows the top-level stand-in.
  Future<void> _refreshStandIn() async {
    final ws = widget.walletService;
    if (ws == null) return;
    final configured = await ws.hasStandIn();
    if (!mounted) return;
    setState(() => _standInConfigured = configured);
  }

  /// Opens the stand-in wizard, then refreshes the status on return.
  Future<void> _openStandIn() async {
    await context.push('/stand-in');
    if (mounted) await _refreshStandIn();
  }

  @override
  void dispose() {
    widget.settingsService?.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    _syncThemeMode();
  }

  void _syncThemeMode() {
    final svc = widget.settingsService;
    if (svc != null) {
      setState(() {
        _themeMode = svc.themeMode;
        _currentLocale = svc.locale;
        _launcherDisguise = svc.launcherDisguise;
        _bleName = svc.bleName;
      });
    }
  }

  /// Localized name of the current theme mode, shown as the row value.
  String _themeModeLabel(AppLocalizations l10n) => switch (_themeMode) {
    ThemeMode.system => l10n.themeSystem,
    ThemeMode.light => l10n.lightMode,
    ThemeMode.dark => l10n.darkMode,
  };

  /// Shows the theme picker sheet: system / light / dark.
  void _showThemePicker() {
    final l10n = AppLocalizations.of(context)!;
    showNeoOptionSheet(
      context: context,
      title: l10n.theme,
      options: [
        (
          label: l10n.themeSystem,
          selected: _themeMode == ThemeMode.system,
          onSelect: () =>
              widget.settingsService?.setThemeMode(ThemeMode.system),
        ),
        (
          label: l10n.lightMode,
          selected: _themeMode == ThemeMode.light,
          onSelect: () => widget.settingsService?.setThemeMode(ThemeMode.light),
        ),
        (
          label: l10n.darkMode,
          selected: _themeMode == ThemeMode.dark,
          onSelect: () => widget.settingsService?.setThemeMode(ThemeMode.dark),
        ),
      ],
    );
  }

  /// Shows a dialog to edit the BLE device name.
  void _editBleName() {
    final controller = TextEditingController(text: _bleName);
    final c = Theme.of(context).brightness == Brightness.dark
        ? ColorTokens.dark
        : ColorTokens.light;
    showDialog(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(context)!;
        return AlertDialog(
          backgroundColor: c.surface,
          title: Text(l10n.bleName, style: TextStyle(color: c.text)),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 20,
            style: TextStyle(color: c.text),
            decoration: InputDecoration(
              hintText: l10n.bleNameHint,
              hintStyle: TextStyle(color: c.text.withAlpha(100)),
              filled: true,
              fillColor: c.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: c.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: c.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: c.primary),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                l10n.cancel,
                style: TextStyle(color: c.text.withAlpha(150)),
              ),
            ),
            TextButton(
              onPressed: () async {
                final value = controller.text.trim().isEmpty
                    ? defaultBleDeviceName
                    : controller.text.trim();
                Navigator.of(ctx).pop();

                // Persist + apply to the advertiser. AppState also re-arms a
                // live advertiser so the new name reaches the air immediately.
                final appState = widget.appState;
                if (appState != null) {
                  await appState.setBleDeviceName(value);
                } else {
                  widget.settingsService?.setBleName(value);
                }
                if (mounted) setState(() => _bleName = value);
              },
              child: Text(l10n.done, style: TextStyle(color: c.primary)),
            ),
          ],
        );
      },
    );
  }

  /// Returns the display name of the currently active locale.
  String _currentLanguageName(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (_currentLocale.languageCode) {
      case 'en':
        return l10n.languageEnglish;
      case 'zh':
        return l10n.languageChinese;
      case 'ja':
        return l10n.languageJapanese;
      case 'ko':
        return l10n.languageKorean;
      default:
        return l10n.languageEnglish;
    }
  }

  /// Shows the language picker sheet.
  void _showLanguagePicker() {
    final l10n = AppLocalizations.of(context)!;
    showNeoOptionSheet(
      context: context,
      title: l10n.language,
      options: [
        for (final (locale, label) in [
          (const Locale('en'), l10n.languageEnglish),
          (const Locale('zh'), l10n.languageChinese),
          (const Locale('ja'), l10n.languageJapanese),
          (const Locale('ko'), l10n.languageKorean),
        ])
          (
            label: label,
            selected: _currentLocale.languageCode == locale.languageCode,
            onSelect: () => widget.settingsService?.setLocale(locale),
          ),
      ],
    );
  }

  /// Localized display name of a disguise persona (row value + dialog copy).
  String _disguiseName(AppLocalizations l10n, LauncherDisguise disguise) =>
      switch (disguise) {
        LauncherDisguise.standard => l10n.disguiseStandard,
        LauncherDisguise.calculator => l10n.disguiseCalculator,
      };

  /// Shows the disguise picker sheet, then (on an actual change) a
  /// confirmation dialog — the swap is visible on the desktop within seconds,
  /// so the user should know what is about to happen and how to undo it.
  void _showDisguisePicker() {
    final l10n = AppLocalizations.of(context)!;
    showNeoOptionSheet(
      context: context,
      title: l10n.disguiseTitle,
      options: [
        for (final disguise in LauncherDisguise.values)
          (
            label: _disguiseName(l10n, disguise),
            selected: _launcherDisguise == disguise,
            onSelect: () => _changeDisguise(disguise),
          ),
      ],
    );
  }

  Future<void> _changeDisguise(LauncherDisguise target) async {
    if (target == _launcherDisguise) return;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final c = Theme.of(context).brightness == Brightness.dark
        ? ColorTokens.dark
        : ColorTokens.light;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(l10n.disguiseConfirmTitle, style: TextStyle(color: c.text)),
        content: Text(
          l10n.disguiseConfirmBody(_disguiseName(l10n, target)),
          style: TextStyle(color: c.text.withAlpha(200), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              l10n.cancel,
              style: TextStyle(color: c.text.withAlpha(150)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l10n.disguiseConfirmButton,
              style: TextStyle(color: c.primary),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.settingsService?.setLauncherDisguise(target);
  }

  /// Shows a confirmation dialog before resetting the wallet.
  void _confirmResetWallet() {
    final c = Theme.of(context).brightness == Brightness.dark
        ? ColorTokens.dark
        : ColorTokens.light;
    showDialog(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(context)!;
        return AlertDialog(
          backgroundColor: c.surface,
          title: Text(l10n.resetWalletTitle, style: TextStyle(color: c.text)),
          content: Text(
            l10n.resetWalletConfirm,
            style: TextStyle(color: c.text.withAlpha(200), fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                l10n.cancel,
                style: TextStyle(color: c.text.withAlpha(150)),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _resetWallet();
              },
              child: Text(l10n.reset, style: TextStyle(color: c.error)),
            ),
          ],
        );
      },
    );
  }

  /// Clears all wallet data and navigates to the Welcome screen.
  ///
  /// This is a deliberate **device-level destruction**: it wipes *every* tier
  /// and credential, regardless of the stand-in mode or the tier that opened
  /// the current session. That is an explicit exception to the "a session sees
  /// only its own depth" invariant (I14): an explicit, confirmed reset must
  /// leave no real wallet behind, because only after seeing Welcome does an
  /// attacker walk away — a cold start that lands back on Unlock would instead
  /// escalate coercion. Both the appState and the bare-walletService paths must
  /// therefore call `resetAll`, never the session-scoped `clearWallet`.
  Future<void> _resetWallet() async {
    final appState = widget.appState;
    if (appState != null) {
      await appState.resetWallet();
    } else {
      await widget.walletService?.resetAll();
    }
    if (mounted) context.go('/welcome');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;

    // Inset grouped list: surface cards float on the tinted grouped
    // background (white cards on the pale lime tint in light). Nothing paints
    // that background here — the parent does (MainScreen's Scaffold as a tab,
    // this screen's own Scaffold standalone), so the neo grid behind the tabs
    // shows through.
    final content = ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // ── Section: Appearance ──────────────────────────────────
        _buildAppearanceGroup(c, l10n, isDark),
        SizedBox(height: c.neobrutalism ? 30 : 26),

        // ── Section: Security ────────────────────────────────────
        _buildSecurityGroup(c, l10n),
        SizedBox(height: c.neobrutalism ? 30 : 26),

        // ── Section: BLE ─────────────────────────────────────────
        _buildBleGroup(c, l10n),
        SizedBox(height: c.neobrutalism ? 30 : 26),

        // ── Section: About ───────────────────────────────────────
        GroupHeader(c: c, title: l10n.about),
        AboutCard(c: c),
      ],
    );

    // When used as a tab, render content directly (no Scaffold/AppBar).
    // The parent MainScreen provides the Scaffold.
    if (widget.isTab) {
      return content;
    }

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: c.groupedBg,
        appBar: neoAppBar(
          c: c,
          title: Text(AppLocalizations.of(context)!.settingsTitle),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: c.text),
            onPressed: () => context.pop(),
          ),
          darkBackground: c.groupedBg,
        ),
        body: SafeArea(child: content),
      ),
    );
  }

  /// Appearance section: the theme-mode and language rows.
  Widget _buildAppearanceGroup(
    ColorTokens c,
    AppLocalizations l10n,
    bool isDark,
  ) {
    return SettingsGroup(
      c: c,
      header: l10n.appearance,
      rows: [
        SettingsRow(
          c: c,
          icon: isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
          title: l10n.theme,
          value: _themeModeLabel(l10n),
          onTap: _showThemePicker,
        ),
        SettingsRow(
          c: c,
          icon: Icons.language,
          title: l10n.language,
          value: _currentLanguageName(context),
          onTap: _showLanguagePicker,
        ),
      ],
    );
  }

  /// Security section: backup/export, stand-in, launcher disguise, change PIN
  /// and the destructive reset-wallet row.
  Widget _buildSecurityGroup(ColorTokens c, AppLocalizations l10n) {
    return SettingsGroup(
      c: c,
      header: l10n.security,
      rows: [
        SettingsRow(
          c: c,
          icon: Icons.vpn_key_outlined,
          title: l10n.backupAndExport,
          onTap: () => context.push('/backup-export'),
        ),
        // Stand-in wallet (ADR-009). Always tappable and always showing
        // its real, session-relative status: a primary session shows the
        // top-level stand-in, a stand-in session shows its own nested one
        // (a stand-in may itself configure a stand-in one tier deeper).
        // No session ever makes this row behave "differently" — that
        // asymmetry was itself an observable tell.
        SettingsRow(
          c: c,
          icon: Icons.switch_account_outlined,
          title: l10n.standInTitle,
          value: _standInConfigured
              ? l10n.standInConfigured
              : l10n.standInNotSetUp,
          onTap: _openStandIn,
        ),
        // Launcher disguise (ADR-012): device-level icon/label swap.
        // Present in every session with identical behaviour (I14) —
        // it only changes what the desktop shows.
        SettingsRow(
          c: c,
          icon: Icons.theater_comedy_outlined,
          title: l10n.disguiseTitle,
          value: _disguiseName(l10n, _launcherDisguise),
          onTap: _showDisguisePicker,
        ),
        SettingsRow(
          c: c,
          icon: Icons.lock_outline,
          title: l10n.changePin,
          onTap: () => context.go('/set-pin'),
        ),
        SettingsRow(
          c: c,
          icon: Icons.delete_outline,
          title: l10n.resetWalletTitle,
          iconColor: c.error,
          titleColor: c.error,
          showChevron: false,
          onTap: _confirmResetWallet,
        ),
      ],
    );
  }

  /// BLE section: the editable device-name row.
  Widget _buildBleGroup(ColorTokens c, AppLocalizations l10n) {
    return SettingsGroup(
      c: c,
      header: l10n.bluetooth,
      rows: [
        SettingsRow(
          c: c,
          icon: Icons.bluetooth,
          title: l10n.bleName,
          value: _bleName,
          actionIcon: Icons.edit_outlined,
          onTap: _editBleName,
        ),
      ],
    );
  }
}
