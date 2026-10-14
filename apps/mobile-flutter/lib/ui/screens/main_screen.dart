import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../app/chain_ble_control_adapter.dart';
import '../../core/interfaces/ble_peripheral.dart';
import '../../core/interfaces/chain_ble_control.dart';
import '../../core/interfaces/wallet_service.dart';
import '../../core/models/signature_record.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../services/settings_service.dart';
import '../theme/color_tokens.dart';
import '../widgets/ble/ble_control_sheet.dart';
import '../widgets/ble/ble_fab.dart';
import '../widgets/ble/ble_log_controller.dart';
import '../widgets/common/grid_background.dart';
import '../widgets/common/neo_app_bar.dart';
import '../widgets/vault/vault_switcher.dart';
import 'accounts/accounts_tab.dart';
import 'history/history_screen.dart';
import 'settings/settings_screen.dart';

/// Main screen with bottom navigation — the app's home after unlock.
///
/// Three tabs:
/// - **Vault** — wallet accounts grouped by chain, with the single BLE
///   control as a floating button (one Ledger app open at a time);
/// - **History** — past signing operations
/// - **Settings** — theme, security, BLE name, about
///
/// The BLE sheet — chain picker and the APDU log as its two views, never two
/// stacked sheets — is opened from that floating button, not from a tab.
/// Uses [IndexedStack] to preserve tab state across switches. Navigation to
/// sub-pages (AccountDetail, SetPin, BackupSeed, Transaction) is handled by
/// pushing on top of this screen via `context.push()`.
class MainScreen extends StatefulWidget {
  final AppState? appState;
  final IWalletService? walletService;

  /// Gallery-only chain-BLE control (ADR-005): when provided, the Vault
  /// headers render realistic broadcasting/connected states without a real
  /// AppState. Production leaves this null — an adapter over [appState] is
  /// used instead.
  final IChainBleControl? chainBleControl;

  /// Gallery-only BLE peripheral (ADR-005): used to back the session-scoped
  /// [BleLogController] when there is no [appState].
  final IBlePeripheral? previewBle;

  /// Gallery-only signing history (ADR-005): forwarded to the History tab
  /// when there is no [appState]. Production leaves this null.
  final List<SignatureRecord>? previewHistory;

  /// Settings service for previews that have no [appState] (gallery).
  final SettingsService? settingsService;

  /// Initial bottom-nav tab (0 = Vault, 1 = History, 2 = Settings).
  final int initialTabIndex;

  /// Gallery-only: open the BLE log sheet on first frame so the sheet can
  /// be reviewed/screenshot without a click. Production stays false.
  final bool autoOpenLogs;

  /// Gallery-only: open the BLE chain/control sheet on first frame.
  final bool autoOpenBleControl;

  /// Gallery-only: open the Settings theme picker sheet on first frame.
  final bool previewThemeSheet;

  const MainScreen({
    super.key,
    this.appState,
    this.walletService,
    this.chainBleControl,
    this.previewBle,
    this.previewHistory,
    this.settingsService,
    this.initialTabIndex = 0,
    this.autoOpenLogs = false,
    this.autoOpenBleControl = false,
    this.previewThemeSheet = false,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _currentIndex;
  IChainBleControl? _chainBleControl;
  bool _ownsChainBleControl = false;
  BleLogController? _bleLogs;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTabIndex.clamp(0, 2);

    if (widget.chainBleControl != null) {
      _chainBleControl = widget.chainBleControl;
    } else if (widget.appState != null) {
      _chainBleControl = ChainBleControlAdapter(widget.appState!);
      _ownsChainBleControl = true;
    }

    final peripheral = widget.appState?.blePeripheral ?? widget.previewBle;
    if (peripheral != null) {
      _bleLogs = BleLogController(peripheral);
    }

    if (widget.autoOpenLogs || widget.autoOpenBleControl) {
      final showLogs = widget.autoOpenLogs;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openBleSheet(showLogs: showLogs);
      });
    }
  }

  // ── Tab pages ─────────────────────────────────────────────────────
  // Rebuilt each frame so the Accounts tab picks up a vault switch / rename
  // / add / remove. [IndexedStack] keeps every tab's State alive across
  // switches because the children stay in the tree (same position, same type).
  List<Widget> _buildTabs() => [
    AccountsTab(walletService: widget.walletService),
    HistoryScreen(
      appState: widget.appState,
      previewRecords: widget.previewHistory,
    ),
    Builder(
      builder: (context) => SettingsScreen(
        settingsService:
            widget.appState?.settingsService ?? widget.settingsService,
        walletService: widget.walletService,
        appState: widget.appState,
        isTab: true,
        previewThemeSheet: widget.previewThemeSheet,
      ),
    ),
  ];

  /// Open the one BLE sheet. The APDU log is its second view, not a second
  /// sheet — house rule: never stack a sheet on a sheet.
  void _openBleSheet({bool showLogs = false}) {
    final control = _chainBleControl;
    if (control == null) return;
    BleControlSheet.open(
      context,
      control: control,
      logController: _bleLogs,
      showLogs: showLogs,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;

    // Every tab sits on the tinted inset-grouped background; the AppBar tints
    // with it so the title area flows into the list. Dark mode's `groupedBg`
    // equals `bg`, so this only changes light mode.
    final scaffoldBg = c.groupedBg;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: neoAppBar(
        c: c,
        title: _currentIndex == 0 && widget.walletService != null
            ? VaultSwitcherTitle(
                walletService: widget.walletService!,
                onChanged: () => setState(() {}),
              )
            : Text(
                _currentIndex == 0
                    ? l10n.accountsTitle
                    : _currentIndex == 1
                    ? l10n.historyTab
                    : l10n.settings,
                style: TextStyle(color: c.text, fontWeight: FontWeight.w700),
              ),
        darkBackground: c.groupedBg,
        ruleWidth: Neo.edge * 2,
      ),
      body: GridBackground(
        child: IndexedStack(index: _currentIndex, children: _buildTabs()),
      ),
      // BLE is controlled from the Vault screen via a single floating
      // button (chain picker / stop / switch in its bottom sheet).
      floatingActionButton: _currentIndex == 0 && _chainBleControl != null
          ? BleFab(control: _chainBleControl!, onTap: _openBleSheet)
          : null,
      // A top-edge shadow lifts the tab bar off the page. In light mode
      // `surface` and `bg` are both white, so without it the bar melts into
      // the body; in dark mode `shadow` is transparent and the surface/bg
      // contrast already does the separating. `elevation: 0` keeps the bar's
      // own (theme-shadow-colored) elevation shadow out of the way so this
      // one controls the depth.
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: c.shadow,
              blurRadius: 3,
              offset: const Offset(0, -1),
            ),
            BoxShadow(
              color: c.shadow,
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          backgroundColor: c.surface,
          selectedItemColor: c.accent,
          unselectedItemColor: c.text.withAlpha(120),
          selectedFontSize: 9,
          unselectedFontSize: 9,
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.account_balance_wallet_outlined),
              activeIcon: const Icon(Icons.account_balance_wallet),
              label: l10n.accountsTitle,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.history_outlined),
              activeIcon: const Icon(Icons.history),
              label: l10n.historyTab,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.settings_outlined),
              activeIcon: const Icon(Icons.settings),
              label: l10n.settings,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Only the adapter created here is ours; an injected preview control is
    // owned (and disposed) by whoever built it. dispose() is on the
    // interface, so no downcast is needed.
    if (_ownsChainBleControl) {
      _chainBleControl?.dispose();
    }
    _bleLogs?.dispose();
    super.dispose();
  }
}
