import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_state.dart';
import '../core/models/vault.dart';
import '../core/models/wallet_accounts.dart';
import '../ui/screens/account_detail/account_detail_screen.dart';
import '../ui/screens/enigma/enigma_screen.dart';
import '../ui/screens/enigma_mnemonic/enigma_mnemonic_screen.dart';
import '../ui/screens/entropy/entropy_screen.dart';
import '../ui/screens/generate_mnemonic/generate_mnemonic_screen.dart';
import '../ui/screens/import_mnemonic/import_mnemonic_screen.dart';
import '../ui/screens/seed_export/backup_export_screen.dart';
import '../ui/screens/seed_export/private_key_qr_screen.dart';
import '../ui/screens/seed_export/seed_qr_screen.dart';
import '../ui/screens/set_pin/set_pin_screen.dart';
import '../ui/screens/stand_in/stand_in_screen.dart';
import '../ui/screens/transaction/address_confirm_screen.dart';
import '../ui/screens/transaction/transaction_screen.dart';
import '../ui/screens/transaction/signature_result_screen.dart';
import '../ui/screens/unlock/unlock_screen.dart';
import '../ui/screens/main_screen.dart';
import '../ui/screens/verify_mnemonic/verify_mnemonic_screen.dart';
import '../ui/screens/verify/verify_backup_enigma_screen.dart';
import '../ui/screens/verify/verify_backup_mnemonic_screen.dart';
import '../ui/screens/verify/verify_backup_passphrase_screen.dart';
import '../ui/screens/welcome/welcome_screen.dart';

/// Creates a [GoRouter] that handles navigation for the entire app.
///
/// [initialHasWallet] controls the initial route:
/// - `true` → `/unlock` (cold start with wallet)
/// - `false` → `/welcome` (fresh install)
///
/// Auth flow rules (matching AGENTS.md):
/// - Auth success → `context.go('/')` (replaces entire stack, goes to tabbed main screen)
/// - Reset wallet → `context.go('/welcome')` (replaces entire stack)
/// - Back buttons → `context.pop()`
///
/// Navigation through GoRouter means using `context.go()` instead of
/// `Navigator.pushAndRemoveUntil` — `go()` replaces the entire route stack.
GoRouter createRouter({required bool initialHasWallet, AppState? appState}) {
  return GoRouter(
    initialLocation: initialHasWallet ? '/unlock' : '/welcome',
    routes: [
      // ── Welcome (landing) ────────────────────────────────────────
      GoRoute(
        path: '/welcome',
        builder: (context, state) =>
            WelcomeScreen(settingsService: appState?.settingsService),
      ),

      // ── Wallet Creation Flow ─────────────────────────────────────
      GoRoute(
        path: '/entropy',
        builder: (context, state) => EntropyScreen(mnemonicService: appState?.mnemonicService),
      ),
      GoRoute(
        path: '/generate-mnemonic',
        builder: (context, state) => GenerateMnemonicScreen(
          mnemonic: state.extra as String,
        ),
      ),
      GoRoute(
        path: '/verify-mnemonic',
        builder: (context, state) {
          Map<String, String> creationData;
          final extra = state.extra;
          if (extra is Map) {
            creationData = Map<String, String>.from(extra);
          } else {
            creationData = {'mnemonic': extra as String, 'passphrase': ''};
          }
          // This route *is* the generated flow (entropy → generate → verify).
          creationData['source'] = VaultSource.generated.wire;
          return VerifyMnemonicScreen(creationData: creationData);
        },
      ),

      // ── Wallet Import ────────────────────────────────────────────
      GoRoute(
        path: '/import',
        builder: (context, state) {
          final extra = state.extra;
          final addVault = extra is Map && extra['addVault'] == true;
          return ImportMnemonicScreen(
            mnemonicService: appState?.mnemonicService,
            addVault: addVault,
          );
        },
      ),

      // ── PIN Setup / Change ───────────────────────────────────────
      GoRoute(
        path: '/set-pin',
        builder: (context, state) {
          String? mnemonic;
          String passphrase = '';
          bool addVault = false;
          VaultSource source = VaultSource.imported;
          int enigmaLanguage = 0;
          final extra = state.extra;
          if (extra is Map) {
            mnemonic = extra['mnemonic'] as String?;
            passphrase = (extra['passphrase'] as String?) ?? '';
            addVault = extra['addVault'] == true;
            source = VaultSource.fromWire(extra['source'] as String?);
            enigmaLanguage = (extra['enigmaLanguage'] as num?)?.toInt() ?? 0;
          } else {
            mnemonic = extra as String?;
          }
          return SetPinScreen(
            mnemonic: mnemonic,
            passphrase: passphrase,
            addVault: addVault,
            source: source,
            enigmaLanguage: enigmaLanguage,
            walletService: appState?.walletService,
            appState: appState,
          );
        },
      ),

      // ── Main Screen (tabbed: Accounts / BLE / Settings) ─────────
      GoRoute(
        path: '/',
        builder: (context, state) => MainScreen(
          walletService: appState?.walletService,
          appState: appState,
          urCodec: appState?.urCodec,
          qrSeedHex: appState?.qrPrototypeSeedHex,
        ),
      ),

      // ── Account Detail (with :id parameter) ──────────────────────
      GoRoute(
        path: '/account/:id',
        builder: (context, state) {
          final accountId = state.pathParameters['id'] ?? '0';
          return AccountDetailScreen(key: ValueKey(accountId));
        },
      ),

      // ── Transaction Signing Confirmation ─────────────────────────
      GoRoute(
        path: '/transaction',
        builder: (context, state) => TransactionScreen(
          appState: appState,
        ),
      ),

      // ── Address Display + Confirm (GET_PUBLIC_KEY P1=0x01) ───────
      GoRoute(
        path: '/confirm-address',
        builder: (context, state) => AddressConfirmScreen(
          appState: appState,
        ),
      ),

      // ── Signature Result ─────────────────────────────────────────
      GoRoute(
        path: '/signature-result',
        builder: (context, state) => SignatureResultScreen(
          appState: appState,
        ),
      ),

      // ── Unlock ───────────────────────────────────────────────────
      GoRoute(
        path: '/unlock',
        builder: (context, state) => UnlockScreen(
          walletService: appState?.walletService,
          appState: appState,
        ),
      ),

      // ── Backup & Export (ADR-011) ────────────────────────────────
      //
      // The QR is the only exit: each destination re-verifies the session
      // PIN on the spot (contract I6) via the ExportService.
      GoRoute(
        path: '/backup-export',
        builder: (context, state) => BackupExportScreen(
          exportService: appState?.exportService,
          backupVerifier: appState?.backupVerifier,
          screenSecurity: appState?.screenSecurity,
        ),
      ),
      GoRoute(
        path: '/export-seed',
        builder: (context, state) => SeedQrScreen(
          exportService: appState?.exportService,
          screenSecurity: appState?.screenSecurity,
        ),
      ),
      GoRoute(
        path: '/export-private-key',
        builder: (context, state) => PrivateKeyQrScreen(
          account: state.extra as ChainAccount,
          exportService: appState?.exportService,
          screenSecurity: appState?.screenSecurity,
        ),
      ),

      // ── Backup Verification (ADR-011 §5) ─────────────────────────
      //
      // Retyped secrets are recomputed and compared — nothing is revealed, so
      // these are not PIN-gated (the user supplies the secret).
      GoRoute(
        path: '/verify-backup-seed',
        builder: (context, state) =>
            VerifyBackupMnemonicScreen(verifier: appState?.backupVerifier),
      ),
      GoRoute(
        path: '/verify-backup-passphrase',
        builder: (context, state) =>
            VerifyBackupPassphraseScreen(verifier: appState?.backupVerifier),
      ),
      GoRoute(
        path: '/verify-backup-enigma',
        builder: (context, state) =>
            VerifyBackupEnigmaScreen(verifier: appState?.backupVerifier),
      ),

      // ── Stand-in Wallet (ADR-009; configurable from any session) ──
      GoRoute(
        path: '/stand-in',
        builder: (context, state) => StandInScreen(
          walletService: appState?.walletService,
          mnemonicService: appState?.mnemonicService,
        ),
      ),

      // ── Enigma Flow ──────────────────────────────────────────────
      GoRoute(
        path: '/enigma',
        builder: (context, state) => const EnigmaScreen(),
      ),
      GoRoute(
        path: '/enigma-mnemonic',
        builder: (context, state) => const EnigmaMnemonicScreen(),
      ),
    ],

    // ── Error page (unknown routes) ────────────────────────────────
    errorBuilder: (context, state) => Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(title: const Text('Not Found')),
      body: Center(
        child: Text(
          'No route for ${state.uri}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    ),
  );
}
