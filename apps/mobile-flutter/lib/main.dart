import 'package:flutter/foundation.dart';
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
import 'infrastructure/persistence/shared_prefs_storage.dart';
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

class _OpenLedgerAppAppState extends State<OpenLedgerAppApp> {
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
    _initApp();
  }

  Future<void> _initApp() async {
    // Load persisted settings.
    await _appState.loadSettings();

    // Build the dependency chain:
    //   Storage → VaultRepositoryImpl (migrates legacy single-wallet data)
    //   ICryptoService (CryptoServiceAdapter)
    //   → PinAuthService, AccountService, MnemonicService
    //   → WalletService
    final storage = SharedPreferencesStorage();
    final crypto = const CryptoServiceAdapter();
    final vaultRepo = VaultRepositoryImpl(storage);
    _appState.attachHistoryRepository(HistoryRepositoryImpl(storage, crypto));

    final pinAuthService = PinAuthService(crypto: crypto, repo: vaultRepo);
    final accountService = AccountService(crypto: crypto);
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

    // Initialize BLE peripheral for Ledger Nano X compatibility.
    final blePeripheral = BlePeripheral();
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
