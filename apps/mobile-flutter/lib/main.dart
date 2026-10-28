import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'app/app_state.dart';
import 'core/router.dart';
import 'data/repositories/settings_repository_impl.dart';
import 'data/repositories/history_repository_impl.dart';
import 'data/repositories/vault_repository_impl.dart';
import 'generated/l10n/app_localizations.dart';
import 'infrastructure/ble/ble_peripheral_universal.dart';
import 'infrastructure/ffi/crypto_service_adapter.dart';
import 'infrastructure/platform/launcher_disguise_channel.dart';
import 'infrastructure/persistence/secure_storage.dart';
import 'services/account_service.dart';
import 'services/mnemonic_service.dart';
import 'services/pin_auth_service.dart';
import 'services/settings_service.dart';
import 'services/wallet_service.dart';
import 'ui/theme/app_theme.dart';

/// Global navigator key for navigation from non-Widget code.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock the app to portrait: this is a phone-shaped hardware-wallet UI
  // (Ledger Nano X parity), never meant to rotate.
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
  if (kDebugMode) {
    SemanticsBinding.instance.ensureSemantics();
  }
  runApp(const OpenLedgerAppApp());
}

class OpenLedgerAppApp extends StatefulWidget {
  const OpenLedgerAppApp({super.key});

  @override
  State<OpenLedgerAppApp> createState() => _OpenLedgerAppAppState();
}

class _OpenLedgerAppAppState extends State<OpenLedgerAppApp>
    with WidgetsBindingObserver {
  final AppState _appState = AppState(
    settingsService: SettingsService(
      repo: SettingsRepositoryImpl(),
      disguise: const LauncherDisguiseChannel(),
    ),
  );

  /// Stable GoRouter — created once after hasWallet resolves.
  /// Never recreated on theme/locale changes to avoid navigation reset.
  GoRouter? _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Any pointer down counts as activity for the foreground idle window
    // (sliding lock). A global route also sees taps no widget claims.
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onGlobalPointer);
    _initApp();
  }

  /// Restart the foreground idle window on every pointer down.
  void _onGlobalPointer(PointerEvent event) {
    if (event is PointerDownEvent) _appState.onUserActivity();
  }

  /// Feed App lifecycle to the wallet session (contract J8/I8): leaving the
  /// foreground starts the background lock timer, returning either locks
  /// immediately (timeout elapsed) or restarts the foreground idle window.
  ///
  /// `inactive` is deliberately ignored — it also fires for the control
  /// centre, permission dialogs and the iOS app switcher, none of which mean
  /// the device left the app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _appState.onAppBackgrounded();
      case AppLifecycleState.resumed:
        _appState.onAppForegrounded();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _initApp() async {
    // Load persisted settings.
    await _appState.loadSettings();

    // Build the dependency chain:
    //   Storage → VaultRepositoryImpl (migrates legacy single-wallet data)
    //   ICryptoService (CryptoServiceAdapter)
    //   → PinAuthService, AccountService, MnemonicService
    //   → WalletService
    //
    // Wallet data lives in OS-backed secure storage (ADR-007). On a device that
    // still has the pre-upgrade plaintext keys, the one-time migration runs
    // first so the repository only ever sees the secure copy.
    final storage = SecureStorage();
    await LegacyWalletMigration(storage).run();
    final crypto = const CryptoServiceAdapter();
    final vaultRepo = VaultRepositoryImpl(storage);
    _appState.attachHistoryRepository(HistoryRepositoryImpl(storage, crypto));

    final pinAuthService = PinAuthService(crypto: crypto, repo: vaultRepo);
    final accountService =
        AccountService(crypto: crypto, chainHost: _appState.chainHost);
    final mnemonicService = MnemonicService(crypto: crypto);
    _appState.mnemonicService = mnemonicService;

    final walletService = WalletService(
      pinAuth: pinAuthService,
      accountService: accountService,
      mnemonicService: mnemonicService,
      repo: vaultRepo,
    );

    await _appState.resolveWallet(walletService);

    // Create GoRouter ONCE — stable reference prevents navigation reset
    // on theme/locale changes triggered by AppState listeners.
    _router = createRouter(
      initialHasWallet: _appState.hasWallet ?? false,
      appState: _appState,
    );

    // Inject sign-request navigation callback.
    _appState.onSignRequest = _navigateToTransaction;

    // Inject address-confirmation navigation callback.
    _appState.onAddressRequest = _navigateToAddressConfirm;

    // Auto-lock (background timeout or foreground idle) sends the user back
    // to Unlock, clearing the navigation stack (I12).
    _appState.onLocked = () => _router?.go('/unlock');

    // Initialize BLE peripheral for Ledger Nano X compatibility, applying the
    // persisted BLE name before any advertising starts.
    final blePeripheral = BlePeripheral();
    await blePeripheral.setDeviceName(_appState.settingsService.bleName);
    _appState.blePeripheral = blePeripheral;
  }

  /// Navigate to the transaction confirmation screen when a sign
  /// request arrives from BLE.
  void _navigateToTransaction() {
    _router?.go('/transaction');
  }

  /// Navigate to the address confirmation screen when an ETH
  /// GET_PUBLIC_KEY P1=0x01 request arrives from BLE.
  void _navigateToAddressConfirm() {
    _router?.go('/confirm-address');
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointer);
    WidgetsBinding.instance.removeObserver(this);
    _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _appState,
      builder: (context, _) {
        final hasWallet = _appState.hasWallet;

        // Startup flash prevention: render nothing until wallet check
        // AND router creation both complete.
        if (hasWallet == null || _router == null) {
          return MaterialApp(
            title: 'Open Ledger App',
            debugShowCheckedModeBanner: false,
            themeMode: _appState.themeMode,
            darkTheme: darkTheme,
            theme: lightTheme,
            locale: _appState.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const SizedBox.shrink(),
          );
        }

        return MaterialApp.router(
          title: 'Open Ledger App',
          debugShowCheckedModeBanner: false,
          themeMode: _appState.themeMode,
          darkTheme: darkTheme,
          theme: lightTheme,
          locale: _appState.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: _router!,
        );
      },
    );
  }
}
