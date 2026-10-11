import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../services/settings_service.dart';
import '../../../core/interfaces/wallet_service.dart';
import '../../../core/models/ble_types.dart';
import '../../../core/models/launcher_disguise.dart';
import '../../../app/app_state.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../theme/widgets/brand_mark.dart';

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
    _showOptionsSheet(
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
          onSelect: () =>
              widget.settingsService?.setThemeMode(ThemeMode.light),
        ),
        (
          label: l10n.darkMode,
          selected: _themeMode == ThemeMode.dark,
          onSelect: () =>
              widget.settingsService?.setThemeMode(ThemeMode.dark),
        ),
      ],
    );
  }

  /// Shows a modal bottom sheet with a checkmark-style option list — the
  /// shared picker used by both the theme and language rows.
  void _showOptionsSheet({
    required String title,
    required List<({String label, bool selected, VoidCallback onSelect})>
        options,
  }) {
    final c = Theme.of(context).brightness == Brightness.dark
        ? ColorTokens.dark
        : ColorTokens.light;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xl)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.text.withAlpha(60),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Text(
                  title,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final opt in options)
                InkWell(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    opt.onSelect();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 13),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            opt.label,
                            style: TextStyle(
                              color: c.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                        if (opt.selected)
                          Icon(Icons.check_rounded,
                              color: c.primary, size: 22),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
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
              child: Text(
                l10n.done,
                style: TextStyle(color: c.primary),
              ),
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
    _showOptionsSheet(
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
    _showOptionsSheet(
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
        title:
            Text(l10n.disguiseConfirmTitle, style: TextStyle(color: c.text)),
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
            child: Text(l10n.disguiseConfirmButton,
                style: TextStyle(color: c.primary)),
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
              child: Text(
                l10n.reset,
                style: TextStyle(color: c.error),
              ),
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
    // background (iOS-style in light: white cards on #F2F2F7).
    final content = ColoredBox(
      color: c.groupedBg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // ── Section: Appearance ──────────────────────────────────
          _SettingsGroup(
            c: c,
            header: l10n.appearance,
            rows: [
              _SettingsRow(
                c: c,
                icon: isDark
                    ? Icons.dark_mode_outlined
                    : Icons.light_mode_outlined,
                title: l10n.theme,
                value: _themeModeLabel(l10n),
                onTap: _showThemePicker,
              ),
              _SettingsRow(
                c: c,
                icon: Icons.language,
                title: l10n.language,
                value: _currentLanguageName(context),
                onTap: _showLanguagePicker,
              ),
            ],
          ),
          const SizedBox(height: 26),

          // ── Section: Security ────────────────────────────────────
          _SettingsGroup(
            c: c,
            header: l10n.security,
            rows: [
              _SettingsRow(
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
              _SettingsRow(
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
              _SettingsRow(
                c: c,
                icon: Icons.theater_comedy_outlined,
                title: l10n.disguiseTitle,
                value: _disguiseName(l10n, _launcherDisguise),
                onTap: _showDisguisePicker,
              ),
              _SettingsRow(
                c: c,
                icon: Icons.lock_outline,
                title: l10n.changePin,
                onTap: () => context.go('/set-pin'),
              ),
              _SettingsRow(
                c: c,
                icon: Icons.delete_outline,
                title: l10n.resetWalletTitle,
                iconColor: c.error,
                titleColor: c.error,
                showChevron: false,
                onTap: _confirmResetWallet,
              ),
            ],
          ),
          const SizedBox(height: 26),

          // ── Section: BLE ─────────────────────────────────────────
          _SettingsGroup(
            c: c,
            header: l10n.bluetooth,
            rows: [
              _SettingsRow(
                c: c,
                icon: Icons.bluetooth,
                title: l10n.bleName,
                value: _bleName,
                actionIcon: Icons.edit_outlined,
                onTap: _editBleName,
              ),
            ],
          ),
          const SizedBox(height: 26),

          // ── Section: About ───────────────────────────────────────
          _GroupHeader(c: c, title: l10n.about),
          _AboutCard(c: c),
        ],
      ),
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
        appBar: AppBar(
          backgroundColor: c.groupedBg,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: c.text),
            onPressed: () => context.pop(),
          ),
          title: Text(AppLocalizations.of(context)!.settingsTitle),
        ),
        body: SafeArea(child: content),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Inset grouped settings list — one borderless surface card per section on
// the tinted grouped background, hairline dividers between rows.
// ═══════════════════════════════════════════════════════════════════════

/// A section of the settings list: an uppercase label above a single
/// rounded card containing [rows] separated by indented hairline dividers.
class _SettingsGroup extends StatelessWidget {
  final ColorTokens c;
  final String header;
  final List<Widget> rows;

  const _SettingsGroup({
    required this.c,
    required this.header,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GroupHeader(c: c, title: header),
        // No border: the card edge is defined by surface vs. groupedBg.
        // Corner radius 10 matches the iOS inset-grouped card.
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                rows[i],
                if (i < rows.length - 1)
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    // Align the divider with the title text (after the icon).
                    indent: 52,
                    color: c.border.withAlpha(140),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A single settings row: leading icon, title, optional right-aligned
/// [value] and a chevron.
///
/// Tapping calls [onTap]. Rows without [onTap] render muted and inert.
/// [iconColor]/[titleColor] override the neutral defaults (use [c.error]
/// for the destructive Reset Wallet row).
class _SettingsRow extends StatelessWidget {
  final ColorTokens c;
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? titleColor;
  final bool showChevron;

  /// Trailing icon override (e.g. an edit affordance for the BLE name row).
  /// Takes precedence over the default chevron.
  final IconData? actionIcon;

  const _SettingsRow({
    required this.c,
    required this.icon,
    required this.title,
    this.value,
    this.onTap,
    this.iconColor,
    this.titleColor,
    this.showChevron = true,
    this.actionIcon,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final iconEffective =
        enabled ? (iconColor ?? c.text.withAlpha(160)) : c.text.withAlpha(80);
    final titleEffective =
        enabled ? (titleColor ?? c.text) : c.text.withAlpha(120);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconEffective),
            const SizedBox(width: 14),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: titleEffective,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            // iOS-style trailing value: pinned to the right edge, ahead of
            // the chevron. The title keeps its natural width; the value
            // takes the remaining space and ellipsizes when too long.
            if (value != null)
              Expanded(
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: c.text.withAlpha(enabled ? 120 : 80),
                    fontSize: 15,
                  ),
                ),
              )
            else
              const Spacer(),
            if (enabled && actionIcon != null) ...[
              const SizedBox(width: 4),
              Icon(
                actionIcon,
                size: 16,
                color: c.text.withAlpha(80),
              ),
            ] else if (enabled && showChevron) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: c.text.withAlpha(80),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// About section: app identity block (icon, name, version, tagline).
///
/// Replaces the old pair of pseudo-rows (a "Version" row that looked
/// tappable and a redundant "Ledger compatible" check row) with one
/// non-interactive card.
class _AboutCard extends StatelessWidget {
  final ColorTokens c;

  const _AboutCard({required this.c});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(R.lg),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        children: [
          const BrandMark(size: 56),
          const SizedBox(height: 14),
          Text(
            l10n.appTitle,
            style: TextStyle(
              color: c.text,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${l10n.version} 1.0.0',
            style: TextStyle(color: c.text.withAlpha(120), fontSize: 13),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.welcomeSubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.text.withAlpha(140),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// iOS-style group label above a settings card: 12pt regular,
/// secondary-label gray, sentence case.
///
/// Flush with the card's left edge (the parent list already applies the
/// 16pt gutter) — an extra 16pt here pushed the label to x=32, off the
/// grid shared by the app-bar title and the card edge.
class _GroupHeader extends StatelessWidget {
  final ColorTokens c;
  final String title;

  const _GroupHeader({required this.c, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        title,
        style: TextStyle(fontSize: 12, color: c.text.withAlpha(110)),
      ),
    );
  }
}
