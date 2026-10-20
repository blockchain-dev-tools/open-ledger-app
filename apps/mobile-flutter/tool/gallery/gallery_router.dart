import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:open_ledger_app/core/interfaces/backup_verifier.dart';
import 'package:open_ledger_app/core/models/ble_types.dart';
import 'package:open_ledger_app/core/models/chain.dart';
import 'package:open_ledger_app/core/models/vault.dart';
import 'package:open_ledger_app/core/models/wallet_accounts.dart';

import 'data/sample_accounts.dart';
import 'data/sample_enigma.dart';
import 'data/sample_export.dart';
import 'data/sample_history.dart';
import 'data/sample_mnemonic.dart';
import 'data/sample_signing.dart';
import 'data/fake_ble_peripheral.dart';
import 'data/fake_chain_ble_control.dart';
import 'data/fake_mnemonic_service.dart';
import 'data/fake_settings_repository.dart';
import 'data/fake_wallet_service.dart';
import 'gallery_boot.dart';
import 'pages/catalog_page.dart';
import 'pages/components_page.dart';
import 'pages/tokens_page.dart';
import 'shell/gallery_frame.dart';

// Product screens are imported directly — the gallery renders the exact
// widgets that ship in the app, with zero reimplementation (ADR-005).
import 'package:open_ledger_app/ui/screens/account_detail/account_detail_screen.dart';
import 'package:open_ledger_app/ui/screens/backup_seed/backup_seed_screen.dart';
import 'package:open_ledger_app/ui/screens/enigma/enigma_screen.dart';
import 'package:open_ledger_app/ui/screens/enigma_mnemonic/enigma_mnemonic_screen.dart';
import 'package:open_ledger_app/ui/screens/entropy/entropy_screen.dart';
import 'package:open_ledger_app/ui/screens/generate_mnemonic/generate_mnemonic_screen.dart';
import 'package:open_ledger_app/ui/screens/import_mnemonic/import_mnemonic_screen.dart';
import 'package:open_ledger_app/ui/screens/seed_export/backup_export_screen.dart';
import 'package:open_ledger_app/ui/screens/seed_export/private_key_list_screen.dart';
import 'package:open_ledger_app/ui/screens/seed_export/private_key_qr_screen.dart';
import 'package:open_ledger_app/ui/screens/seed_export/seed_qr_screen.dart';
import 'package:open_ledger_app/ui/screens/set_pin/set_pin_screen.dart';
import 'package:open_ledger_app/ui/screens/stand_in/stand_in_screen.dart';
import 'package:open_ledger_app/ui/screens/transaction/address_confirm_screen.dart';
import 'package:open_ledger_app/ui/screens/transaction/transaction_screen.dart';
import 'package:open_ledger_app/ui/widgets/security/privacy_shield.dart';
import 'package:open_ledger_app/services/settings_service.dart';
import 'package:open_ledger_app/ui/screens/transaction/signature_result_screen.dart';
import 'package:open_ledger_app/ui/screens/unlock/unlock_screen.dart';
import 'package:open_ledger_app/ui/screens/main_screen.dart';
import 'package:open_ledger_app/ui/screens/verify_mnemonic/verify_mnemonic_screen.dart';
import 'package:open_ledger_app/ui/screens/verify/verify_backup_enigma_screen.dart';
import 'package:open_ledger_app/ui/screens/verify/verify_backup_mnemonic_screen.dart';
import 'package:open_ledger_app/ui/screens/verify/verify_backup_passphrase_screen.dart';
import 'package:open_ledger_app/ui/screens/welcome/welcome_screen.dart';

/// Gallery-only: the Backup & Export hub wired to deterministic sample data.
Widget _buildBackupExport(bool hasPassphrase, {bool isEnigma = false}) =>
    BackupExportScreen(
      previewMnemonic: sampleMnemonic,
      previewFingerprint: sampleWalletFingerprint,
      hasPassphrase: hasPassphrase,
      isEnigma: isEnigma,
      previewAccounts: sampleWalletAccounts.accounts,
      encodedKeyFor: (account) => samplePrivateKeyEncodings[account.chain],
      encodingLabelFor: (account) =>
          samplePrivateKeyEncodingLabels[account.chain],
    );

/// Resolves a frozen verdict from the `result` query param so each
/// verification screen can be captured in its match / mismatch / unavailable
/// state. Absent → no verdict (the input-only state).
VerifyResult? _previewVerifyResult(GoRouterState state) =>
    switch (state.uri.queryParameters['result']) {
      'match' => VerifyResult.match,
      'mismatch' => VerifyResult.mismatch,
      'unavailable' => VerifyResult.unavailable,
      _ => null,
    };

/// Gallery-only: the stand-in wallet wizard / status view against a fake
/// wallet service (no storage, no crypto).
///
/// [mode] defaults to the safe `hide` behaviour — a preview must never load
/// with the destructive erase mode pre-selected. `?mode=wipe` opts in to that
/// state explicitly. `?step=mnemonic` opens the wizard straight on the
/// Import / Generate / Enigma step so the tab bar can be captured.
Widget _buildStandIn(bool configured, StandInMode mode, {bool mnemonicStep = false}) =>
    StandInScreen(
      walletService: FakeWalletService(
        standInConfigured: configured,
        standInMode: mode,
      ),
      mnemonicService: createFakeMnemonicService(),
      previewMnemonicStep: mnemonicStep,
    );

/// Resolves the previewed stand-in behaviour from the `mode` query param,
/// defaulting to the non-destructive [StandInMode.hide].
StandInMode _standInModeFrom(GoRouterState state) =>
    state.uri.queryParameters['mode'] == 'wipe'
        ? StandInMode.wipe
        : StandInMode.hide;

// ── Onboarding / signing builders ───────────────────────────────────────
//
// Each of these screens is registered at *two* paths: the product path the
// app's own `context.go` calls use (`/entropy`, `/import`, `/enigma`, …) and
// the `/screens/…` alias the catalog deep-links to. Sharing one builder per
// screen keeps the two in sync — mirrors `_buildBackupExport` / `_buildStandIn`.
Widget _buildEntropy() =>
    EntropyScreen(mnemonicService: createFakeMnemonicService());

Widget _buildGenerateMnemonic() =>
    const GenerateMnemonicScreen(mnemonic: sampleMnemonic);

Widget _buildVerifyMnemonic() =>
    const VerifyMnemonicScreen(creationData: sampleCreationData);

Widget _buildImport() =>
    ImportMnemonicScreen(mnemonicService: createFakeMnemonicService());

Widget _buildEnigma() => const EnigmaScreen();

Widget _buildEnigmaMnemonic() => const EnigmaMnemonicScreen(
      previewWords: sampleEnigmaWords,
      previewEntropyHex: sampleEnigmaEntropyHex,
    );

Widget _buildSetPin() => const SetPinScreen(mnemonic: sampleMnemonic);

Widget _buildSignatureResult() =>
    SignatureResultScreen(previewResult: sampleSignResult());

GoRouter createGalleryRouter(GalleryBoot boot) {
  // Direct page loads (headless screenshots, shared links) carry no
  // navigation call, so resolve the mock payload from the URL itself.
  Object? initialExtra;
  if (boot.initialLocation.startsWith('/account/')) {
    final chain = boot.query['chain'] ?? 'eth';
    initialExtra = sampleAccounts[chain] ?? ethAccount;
  }

  // Preserve the launch query string in the initial location so deep links
  // like `/screens/main?tab=2` (and the screenshot pipeline) select the right
  // scenario. `boot.initialLocation` holds the path only.
  final initialLocation = boot.query.isEmpty
      ? boot.initialLocation
      : Uri(path: boot.initialLocation, queryParameters: boot.query).toString();

  // Populated mock dependencies so the Main-screen tabs render their real
  // list states instead of empty ones (no AppState in the gallery).
  final gallerySettingsService = SettingsService(
    repo: FakeSettingsRepository(
      themeMode: boot.theme == 'light' ? ThemeMode.light : ThemeMode.dark,
      locale: Locale(boot.lang),
    ),
  )..loadSettings();

  return GoRouter(
    initialLocation: initialLocation,
    initialExtra: initialExtra,
    routes: [
      ShellRoute(
        builder: (context, state, child) => GalleryFrame(
          boot: boot,
          state: state,
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const CatalogPage(),
          ),
          GoRoute(
            path: '/tokens/:variant',
            builder: (context, state) {
              final variant = state.pathParameters['variant'];
              return variant == 'light'
                  ? const TokensPage.light()
                  : const TokensPage.dark();
            },
          ),
          GoRoute(
            path: '/components',
            builder: (context, state) => const ComponentsPage(),
          ),
          // Path shape mirrors the product router in lib/core/router.dart.
          GoRoute(
            path: '/account/:id',
            builder: (context, state) => const AccountDetailScreen(),
          ),

          // ── Seed / private-key export ─────────────────────────────
          //
          // Reached from AccountDetail → Backup (private key) and the catalog
          // (recovery phrase). Both freeze the auto-hide countdown so
          // screenshots stay deterministic.
          GoRoute(
            path: '/export-private-key',
            builder: (context, state) {
              // Deep links (chrome=0 screenshots) carry no extra, so fall back
              // to the `chain` query parameter.
              final extra = state.extra;
              final chain = extra is ChainAccount
                  ? extra.chain
                  : state.uri.queryParameters['chain'] ?? 'eth';
              final account = sampleAccounts[chain] ?? ethAccount;
              return PrivateKeyQrScreen(
                account: account,
                encodedPrivateKey: samplePrivateKeyEncodings[account.chain],
                encodingLabel: samplePrivateKeyEncodingLabels[account.chain],
                previewSeconds: 58,
              );
            },
          ),
          GoRoute(
            path: '/screens/export-seed',
            builder: (context, state) => SeedQrScreen(
              previewMnemonic: sampleMnemonic,
              previewFingerprint: sampleWalletFingerprint,
              hasPassphrase: state.uri.queryParameters['passphrase'] == '1',
              previewSeconds: 58,
            ),
          ),
          // Settings → Security pushes this path; catalog deep-links use the
          // /screens/ alias below.
          GoRoute(
            path: '/backup-export',
            builder: (context, state) => _buildBackupExport(
              state.uri.queryParameters['passphrase'] == '1',
              isEnigma: state.uri.queryParameters['enigma'] == '1',
            ),
          ),
          GoRoute(
            path: '/screens/backup-export',
            builder: (context, state) => _buildBackupExport(
              state.uri.queryParameters['passphrase'] == '1',
              isEnigma: state.uri.queryParameters['enigma'] == '1',
            ),
          ),
          GoRoute(
            path: '/screens/private-keys',
            builder: (context, state) => PrivateKeyListScreen(
              accounts: sampleWalletAccounts.accounts,
              encodedKeyFor: (account) =>
                  samplePrivateKeyEncodings[account.chain],
              encodingLabelFor: (account) =>
                  samplePrivateKeyEncodingLabels[account.chain],
              previewSeconds: 58,
            ),
          ),
          // Backup verification (ADR-011 §5). `?result=` freezes one verdict;
          // the screens themselves never call crypto in preview mode.
          GoRoute(
            path: '/screens/verify-seed',
            builder: (context, state) => VerifyBackupMnemonicScreen(
              previewInput: sampleMnemonic,
              previewResult: _previewVerifyResult(state),
            ),
          ),
          GoRoute(
            path: '/screens/verify-passphrase',
            builder: (context, state) => VerifyBackupPassphraseScreen(
              previewResult: _previewVerifyResult(state),
            ),
          ),
          GoRoute(
            path: '/screens/verify-enigma',
            builder: (context, state) => VerifyBackupEnigmaScreen(
              previewRiddle: sampleEnigmaWords.take(6).join(' '),
              previewResult: _previewVerifyResult(state),
            ),
          ),
          // The background cover (ADR-011 §6) over a live secret screen —
          // `previewHidden` freezes the state a real backgrounding produces.
          GoRoute(
            path: '/screens/privacy-shield',
            builder: (context, state) => PrivacyShield(
              previewHidden: true,
              child: SeedQrScreen(
                previewMnemonic: sampleMnemonic,
                previewFingerprint: sampleWalletFingerprint,
                previewSeconds: 58,
              ),
            ),
          ),

          // ── Product screens (ADR-005) ─────────────────────────────
          //
          // Mounted under /screens/ because product `/` conflicts with the
          // gallery catalog. Services that would pull in FFI/BLE are left
          // null; screens render their standalone/degraded state.
          //
          // The product path is also registered for each screen the app
          // reaches through `context.go` (e.g. Welcome → `/entropy`), so the
          // in-app navigation works inside the gallery too.
          GoRoute(
            path: '/welcome',
            builder: (context, state) =>
                WelcomeScreen(settingsService: gallerySettingsService),
          ),
          GoRoute(
            path: '/screens/welcome',
            builder: (context, state) =>
                WelcomeScreen(settingsService: gallerySettingsService),
          ),
          GoRoute(
            path: '/entropy',
            builder: (context, state) => _buildEntropy(),
          ),
          GoRoute(
            path: '/screens/entropy',
            builder: (context, state) => _buildEntropy(),
          ),
          GoRoute(
            path: '/generate-mnemonic',
            builder: (context, state) => _buildGenerateMnemonic(),
          ),
          GoRoute(
            path: '/screens/generate-mnemonic',
            builder: (context, state) => _buildGenerateMnemonic(),
          ),
          GoRoute(
            path: '/verify-mnemonic',
            builder: (context, state) => _buildVerifyMnemonic(),
          ),
          GoRoute(
            path: '/screens/verify-mnemonic',
            builder: (context, state) => _buildVerifyMnemonic(),
          ),
          GoRoute(
            path: '/import',
            builder: (context, state) => _buildImport(),
          ),
          GoRoute(
            path: '/screens/import',
            builder: (context, state) => _buildImport(),
          ),
          GoRoute(
            path: '/enigma',
            builder: (context, state) => _buildEnigma(),
          ),
          GoRoute(
            path: '/screens/enigma',
            builder: (context, state) => _buildEnigma(),
          ),
          GoRoute(
            path: '/enigma-mnemonic',
            builder: (context, state) => _buildEnigmaMnemonic(),
          ),
          GoRoute(
            path: '/screens/enigma-mnemonic',
            builder: (context, state) => _buildEnigmaMnemonic(),
          ),
          // Create mode (mnemonic provided) — the canonical onboarding path.
          GoRoute(
            path: '/set-pin',
            builder: (context, state) => _buildSetPin(),
          ),
          GoRoute(
            path: '/screens/set-pin',
            builder: (context, state) => _buildSetPin(),
          ),

          // ── Stand-in wallet (ADR-009) ─────────────────────────────
          //
          // `configured=1` previews the status view; the default is the
          // first-time wizard intro. `mode=wipe` swaps in the destructive
          // behaviour; the default stays `hide`. Settings pushes `/stand-in`,
          // so both path shapes are registered (mirrors the backup-export
          // routes).
          GoRoute(
            path: '/stand-in',
            builder: (context, state) => _buildStandIn(
              state.uri.queryParameters['configured'] == '1',
              _standInModeFrom(state),
              mnemonicStep: state.uri.queryParameters['step'] == 'mnemonic',
            ),
          ),
          GoRoute(
            path: '/screens/stand-in',
            builder: (context, state) => _buildStandIn(
              state.uri.queryParameters['configured'] == '1',
              _standInModeFrom(state),
              mnemonicStep: state.uri.queryParameters['step'] == 'mnemonic',
            ),
          ),
          GoRoute(
            path: '/screens/unlock',
            // `?state=locked` previews the permanent lockout view a wallet
            // with five exhausted attempts enters directly (no PIN pad).
            builder: (context, state) =>
                state.uri.queryParameters['state'] == 'locked'
                    ? UnlockScreen(
                        walletService: FakeWalletService(lockedOut: true),
                      )
                    : const UnlockScreen(),
          ),
          GoRoute(
            path: '/screens/backup-seed',
            builder: (context, state) => const BackupSeedScreen(),
          ),
          // Main screen with its three bottom-nav tabs. Query parameters
          // select the review scenario:
          //   tab=0|1|2          Vault / History / Settings
          //   chain=<id>        chain whose app is active when broadcasting
          //   bleState=...      broadcasting (default) | connected | idle | error
          //   pending=1         sign decision pending (buttons disabled)
          //   logs=1            auto-open the BLE log sheet
          //   blepanel=1        auto-open the BLE control sheet
          //   themeSheet=1      auto-open the Settings theme picker sheet
          //   standin=1         open as a stand-in session (settings row is
          //                     tappable and reads "Not set up")
          GoRoute(
            path: '/screens/main',
            builder: (context, state) {
              final q = state.uri.queryParameters;
              final tab = int.tryParse(q['tab'] ?? '') ?? 0;
              final bleState = switch (q['bleState']) {
                'idle' => BleState.idle,
                'connected' => BleState.connected,
                'error' => BleState.error,
                _ => BleState.broadcasting,
              };
              final chain = Chain.fromId(q['chain']) ?? Chain.ethereum;
              final ble = FakeBlePeripheral(initialState: bleState);
              // A stand-in session needs its own wallet service so the settings
              // row and vault switcher render their session-relative state.
              final walletService = FakeWalletService(
                isStandInSession: q['standin'] == '1',
              );
              return MainScreen(
                initialTabIndex: tab,
                previewBle: ble,
                chainBleControl: FakeChainBleControl(
                  ble: ble,
                  // An open app only makes sense while the radio is on.
                  initialChain: bleState == BleState.idle ? null : chain,
                  signPending: q['pending'] == '1',
                ),
                walletService: walletService,
                settingsService: gallerySettingsService,
                previewHistory: sampleHistory(),
                autoOpenLogs: q['logs'] == '1',
                autoOpenBleControl: q['blepanel'] == '1',
                previewThemeSheet: q['themeSheet'] == '1',
              );
            },
          ),
          GoRoute(
            path: '/screens/transaction',
            builder: (context, state) =>
                TransactionScreen(previewRequest: sampleSignRequest),
          ),
          GoRoute(
            path: '/screens/confirm-address',
            builder: (context, state) =>
                AddressConfirmScreen(previewRequest: sampleAddressRequest),
          ),
          // Approving a signature lands on `/signature-result`, so the product
          // path is registered alongside the catalog alias.
          GoRoute(
            path: '/signature-result',
            builder: (context, state) => _buildSignatureResult(),
          ),
          GoRoute(
            path: '/screens/signature-result',
            builder: (context, state) => _buildSignatureResult(),
          ),
        ],
      ),
    ],
  );
}
