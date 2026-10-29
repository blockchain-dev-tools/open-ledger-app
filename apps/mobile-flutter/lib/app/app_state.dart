import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/interfaces/wallet_service.dart';
import '../core/interfaces/backup_verifier.dart';
import '../core/interfaces/export_service.dart';
import '../core/interfaces/screen_security.dart';
import '../core/interfaces/ble_peripheral.dart';
import '../core/interfaces/chain_host_service.dart';
import '../core/interfaces/history_repository.dart';
import '../core/interfaces/ur_codec.dart';
import '../core/models/apdu_message.dart';
import '../core/models/ble_types.dart';
import '../core/models/chain.dart';
import '../core/models/signature_record.dart';
import '../infrastructure/ffi/chain_host_bridge.dart';
import '../infrastructure/ffi/crypto_service_adapter.dart';
import '../infrastructure/ffi/ur_bridge.dart';
import '../infrastructure/platform/screen_security_channel.dart';
import '../biz/apdu_handler.dart';
import '../biz/ble_session.dart';
import '../biz/sign_confirmation.dart';
import '../services/backup_verifier.dart';
import '../services/export_service.dart';
import '../services/mnemonic_service.dart';
import '../services/settings_service.dart';

/// Global application state — wallet lifecycle, BLE peripheral lifecycle,
/// settings delegation, and navigation tracking.
///
/// Business logic for APDU dispatch, auto-lock, and sign-interception is
/// delegated to [BleSession] and [SignConfirmation].
///
/// Uses [ChangeNotifier] + Flutter's built-in [ListenableBuilder].
class AppState extends ChangeNotifier {
  // ── Settings (delegated) ────────────────────────────────────────────

  final SettingsService _settingsService;
  SettingsService get settingsService => _settingsService;

  // Convenience accessors for theme/locale (delegated).
  ThemeMode get themeMode => _settingsService.themeMode;
  Locale get locale => _settingsService.locale;
  bool get storePassphrase => _settingsService.storePassphrase;

  AppState({required this._settingsService}) {
    _settingsService.addListener(_onSettingsChanged);
    _apduHandler = ApduHandler();
    _signConfirmation = SignConfirmation(
      crypto: const CryptoServiceAdapter(),
    );
    // Terminal status words emitted by the state-layer backstop (timeout /
    // superseded request) go out over BLE directly, so a request whose
    // confirmation screen never resolved still gets an answer.
    _signConfirmation.sendTerminalStatus = (statusWord) async {
      final resp = ApduResponse(
        data: null,
        sw1: (statusWord >> 8) & 0xFF,
        sw2: statusWord & 0xFF,
      );
      await _blePeripheral?.sendApduResponse(resp.toBytes());
    };
    _signConfirmation.onRequestPending = () {
      // Reviewing a request must not be interrupted by the idle timer.
      setIdleLockSuppressed(true);
      // Forward to the navigation callback set by main.dart.
      onSignRequest?.call();
    };
    _signConfirmation.onRequestResolved = () {
      setIdleLockSuppressed(false);
    };
    _signConfirmation.onAddressRequestPending = () {
      setIdleLockSuppressed(true);
      // Forward to the navigation callback set by main.dart.
      onAddressRequest?.call();
    };
    _signConfirmation.onAddressRequestResolved = () {
      setIdleLockSuppressed(false);
    };
  }

  void _onSettingsChanged() {
    notifyListeners(); // Bubble settings changes up to UI.
  }

  /// Load persisted settings on startup.
  Future<void> loadSettings() => _settingsService.loadSettings();

  // ── Wallet ─────────────────────────────────────────────────────────

  /// `null` = unknown (splash), resolved to `true` / `false`.
  bool? _hasWallet;
  bool? get hasWallet => _hasWallet;

  /// The active [IWalletService] instance, set after startup.
  IWalletService? _walletService;
  IWalletService? get walletService => _walletService;

  /// Sets the wallet service and notifies listeners.
  set walletService(IWalletService? ws) {
    _walletService = ws;
    notifyListeners();
  }

  // ── Export Service ─────────────────────────────────────────────────

  /// Reads the active vault's exportable secrets (ADR-011). `null` until
  /// [resolveWallet] runs.
  IExportService? _exportService;
  IExportService? get exportService => _exportService;

  // ── Backup Verifier (ADR-011) ──────────────────────────────────────

  /// Checks retyped secrets against the active vault (§5). `null` until
  /// [resolveWallet] runs.
  IBackupVerifier? _backupVerifier;
  IBackupVerifier? get backupVerifier => _backupVerifier;

  // ── Screen Security (ADR-011 §6) ───────────────────────────────────

  /// Toggles the OS screenshot / recents-thumbnail block. The secret-display
  /// screens hold it down while they are mounted; everywhere else it is idle.
  final IScreenSecurity _screenSecurity = const ScreenSecurityChannel();
  IScreenSecurity get screenSecurity => _screenSecurity;

  // ── Mnemonic Service ──────────────────────────────────────────────

  MnemonicService? _mnemonicService;
  MnemonicService? get mnemonicService => _mnemonicService;
  set mnemonicService(MnemonicService? ms) {
    _mnemonicService = ms;
    notifyListeners();
  }

  /// Checks whether a wallet exists on this device, caches the
  /// [WalletService], and creates the [BleSession].
  Future<void> resolveWallet(IWalletService ws) async {
    _walletService = ws;
    _hasWallet = await ws.hasWallet();

    // Create (or recreate) BleSession now that we have the wallet service.
    _bleSession?.dispose();
    _bleSession = BleSession(
      walletService: ws,
      apduHandler: _apduHandler,
      signConfirmation: _signConfirmation,
      chainHost: _chainHostBridge,
    );
    _bleSession!.onWalletLocked = () {
      // A pending confirmation cannot be approved without a seed: answer the
      // host with SECURITY_STATUS_NOT_SATISFIED (best effort) and dismiss it.
      final hadPending = _signConfirmation.pendingRequest != null ||
          _signConfirmation.pendingAddressRequest != null;
      final ble = _blePeripheral;
      if (hadPending && ble != null) {
        final resp = ApduResponse(data: null, sw1: 0x69, sw2: 0x82);
        unawaited(ble.sendApduResponse(resp.toBytes()));
      }
      _signConfirmation.cancelPending();
      // A new BleSession starts unsuppressed; mirror the current state in case
      // a confirmation is still pending across a wallet re-resolution.
      setIdleLockSuppressed(false);
      _signConfirmation.clearHistory();
      _historyLoadedForVault = null;
      notifyListeners();
      onLocked?.call();
    };
    _bleSession!.setIdleLockSuppressed(_idleLockSuppressed);
    // Keep the BLE signing context in step with the active vault: a connected
    // host must never sign with the previous vault's seed after a switch or
    // removal (the callback also drops any in-flight tx assembly).
    ws.onActiveVaultChanged = _onActiveVaultChanged;
    // A destroyed vault takes its signing history with it (ADR-009 §7 for the
    // `wipe` path, ADR-010 for removals) — otherwise `wallet.signHistory`
    // keeps a tombstone entry per wallet the device once held.
    ws.onVaultsDestroyed = _onVaultsDestroyed;
    _bleSession!.trySetApduContext();

    // Export reaches the same wallet/session as BLE but stays read-only and
    // local: it never advertises, never writes storage (ADR-011 §6).
    _exportService = ExportService(
      wallet: ws,
      crypto: const CryptoServiceAdapter(),
    );

    // Verification is the read-only counterpart to export: it recomputes the
    // vault's derived output from a retyped secret, reveals nothing and, like
    // export, stays local (ADR-011 §5).
    _backupVerifier = BackupVerifier(
      wallet: ws,
      crypto: const CryptoServiceAdapter(),
    );

    notifyListeners();
  }

  // ── Auto-lock (delegated) ──────────────────────────────────────────

  /// Whether the idle lock is currently suspended (a confirmation is pending).
  bool _idleLockSuppressed = false;

  void onAppBackgrounded() {
    _bleSession?.onAppBackgrounded();
  }

  void onAppForegrounded() {
    _bleSession?.onAppForegrounded();
  }

  /// Start the foreground idle window for the session that just opened.
  void onSessionStarted() {
    _bleSession?.onSessionStarted();
  }

  /// Foreground interaction (pointer down) — restarts the idle window.
  void onUserActivity() {
    _bleSession?.onUserActivity();
  }

  /// Suspend or resume the foreground idle lock.
  ///
  /// Wire to the sign / address confirmation lifecycle: a pending request
  /// pins the session open, resolving it restarts the idle window.
  void setIdleLockSuppressed(bool suppressed) {
    _idleLockSuppressed = suppressed;
    _bleSession?.setIdleLockSuppressed(suppressed);
  }

  // ── BLE Peripheral ─────────────────────────────────────────────────

  IBlePeripheral? _blePeripheral;
  IBlePeripheral? get blePeripheral => _blePeripheral;

  late final ApduHandler _apduHandler;
  late final SignConfirmation _signConfirmation;
  BleSession? _bleSession;

  /// Native chain-app host (stage 2b). Lives as long as the app so a rebuilt
  /// [BleSession] keeps the same Rust-side session and seed.
  final ChainHostBridge _chainHostBridge = ChainHostBridge();
  IChainHostService get chainHost => _chainHostBridge;

  // ── Keystone QR (T-026 prototype, debug-only) ──────────────────────

  /// BC-UR codec backed by the native `ur_*` exports.
  final UrBridge _urBridge = UrBridge();
  IUrCodec get urCodec => _urBridge;

  /// Seed handed to the QR prototype pages — the **unlocked vault seed**, so
  /// the accounts a host derives match this wallet. `null` outside debug
  /// builds or while the vault is locked, so release never exposes the
  /// QRs-screen entry points and a locked vault cannot export.
  String? get qrPrototypeSeedHex => kDebugMode ? _walletService?.seedHex : null;

  set blePeripheral(IBlePeripheral? bp) {
    _blePeripheral = bp;
    _bleSession?.blePeripheral = bp;
    notifyListeners();
  }

  // ── Exposed app (device-side "open app") ───────────────────────────

  /// The Ledger app the device currently has open, or `null` while it sits on
  /// the dashboard. Wallets read it via GET_APP_AND_VERSION and only proceed
  /// with an account while it reports the app they need.
  LedgerApp? get currentApp => _apduHandler.currentApp;

  /// Switch the exposed app — the device-side equivalent of opening an app
  /// on a real Ledger. Hosts that poll GET_APP_AND_VERSION pick up the
  /// change on their next poll, so no reconnect is needed. `null` returns to
  /// the dashboard, exactly like quitting the app on a real device.
  void setCurrentApp(LedgerApp? app) {
    _apduHandler.setCurrentApp(app);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Sign confirmation — delegates to SignConfirmation
  // ═══════════════════════════════════════════════════════════════════

  /// Callback for triggering navigation from non-Widget code.
  /// Injected by [main.dart] or router setup.
  void Function()? onSignRequest;

  /// Callback fired when an ETH GET_PUBLIC_KEY P1=0x01 request needs the
  /// user to confirm the displayed address. Injected by [main.dart].
  void Function()? onAddressRequest;

  /// Callback fired after an auto-lock dropped the session. Injected by
  /// [main.dart] to send the user back to the Unlock screen.
  void Function()? onLocked;

  /// Proxy to [_signConfirmation.pendingRequest].
  PendingSignRequest? get pendingRequest => _signConfirmation.pendingRequest;

  /// Proxy to [_signConfirmation.pendingAddressRequest].
  PendingAddressRequest? get pendingAddressRequest =>
      _signConfirmation.pendingAddressRequest;

  /// Proxy to [_signConfirmation.lastSignResult].
  Map<String, dynamic>? get lastSignResult => _signConfirmation.lastSignResult;

  /// The user approved the pending sign request.
  ///
  /// The sign callback is passed to [SignConfirmation.approve]: the Rust
  /// chain-app host consumed the approval and encodes the reply, which is
  /// sent over BLE and awaited.
  Future<void> approveSign() async {
    await _signConfirmation.approve(() async {
      final req = _signConfirmation.pendingRequest!;
      // A host that cannot answer gets a terminal execution error rather than
      // leaving the request unanswered.
      final responseBytes = _resolveChainReview(req, approved: true) ??
          ApduResponse(data: null, sw1: 0x64, sw2: 0x00).toBytes();
      await _blePeripheral?.sendApduResponse(responseBytes);
      return responseBytes;
    });
    notifyListeners();
  }

  /// The user rejected the pending sign request.
  ///
  /// Sends an error APDU response over BLE via the callback passed to
  /// [SignConfirmation.reject]. The callback is awaited to ensure BLE
  /// error-response delivery completes before clearing state.
  Future<void> rejectSign() async {
    await _signConfirmation.reject(() async {
      final req = _signConfirmation.pendingRequest;
      final fromHost =
          req == null ? null : _resolveChainReview(req, approved: false);
      final bytes = fromHost ??
          ApduResponse(data: null, sw1: 0x69, sw2: 0x85).toBytes();
      await _blePeripheral?.sendApduResponse(bytes);
      return bytes;
    });
    notifyListeners();
  }

  /// Asks the native chain-app host to finish a parked signing review.
  ///
  /// Returns `null` when the host cannot answer, so the caller sends a
  /// terminal execution error instead of leaving the request unanswered.
  Uint8List? _resolveChainReview(PendingSignRequest req,
      {required bool approved}) {
    return _bleSession?.resolveChainReview(req.chainReviewId,
        approved: approved);
  }

  /// Clear the last sign result (after the result screen is dismissed).
  void clearLastSignResult() {
    _signConfirmation.clearLastSignResult();
    notifyListeners();
  }

  /// The user approved the pending address-display request.
  ///
  /// The Rust chain-app host produces the final bytes (it already consumed
  /// the approval).
  Future<void> approveAddress() async {
    await _signConfirmation.approveAddress(() async {
      final req = _signConfirmation.pendingAddressRequest!;
      final bytes = _resolveAddressRequest(req, approved: true);
      await _blePeripheral?.sendApduResponse(bytes);
      return bytes;
    });
    notifyListeners();
  }

  /// The user rejected the pending address-display request.
  ///
  /// Sends SW 0x6985 (user rejected) over BLE.
  Future<void> rejectAddress() async {
    await _signConfirmation.rejectAddress(() async {
      final req = _signConfirmation.pendingAddressRequest;
      final bytes = req != null
          ? _resolveAddressRequest(req, approved: false)
          : ApduResponse(data: null, sw1: 0x69, sw2: 0x85).toBytes();
      await _blePeripheral?.sendApduResponse(bytes);
      return bytes;
    });
    notifyListeners();
  }

  /// Resolves a pending address request through the native chain-app host.
  ///
  /// When the host cannot answer (unavailable symbols, already-consumed
  /// review, module error) the external wallet still gets a terminal
  /// response: user-rejected on rejection, execution error on approval.
  Uint8List _resolveAddressRequest(PendingAddressRequest req,
      {required bool approved}) {
    final bytes = _bleSession?.resolveChainReview(req.chainReviewId,
        approved: approved);
    if (bytes != null) return bytes;
    return approved
        ? ApduResponse(data: null, sw1: 0x64, sw2: 0x00).toBytes()
        : ApduResponse(data: null, sw1: 0x69, sw2: 0x85).toBytes();
  }

  /// History of all completed signing operations (approved/rejected/timeout).
  List<SignatureRecord> get signHistory => _signConfirmation.history;

  // ── History persistence ─────────────────────────────────────────────

  IHistoryRepository? _historyRepo;

  /// Vault whose persisted history is currently hydrated in memory.
  String? _historyLoadedForVault;

  /// Attach the persistence backend for signing history.
  void attachHistoryRepository(IHistoryRepository repo) {
    _historyRepo = repo;
    _signConfirmation.attachHistoryRepository(repo);
    // Persisted history is scoped per vault, so the sign path must know which
    // vault it is writing for.
    _signConfirmation.historyVaultId = () => _walletService?.activeVaultId;
  }

  /// Load persisted history for the currently active vault.
  ///
  /// No-op when locked, when no repository is attached, or when already
  /// loaded for this vault. Call after a successful unlock/setup, and whenever
  /// the active vault changes.
  Future<void> loadHistory() async {
    final repo = _historyRepo;
    final seed = _walletService?.seedHex;
    final vaultId = _walletService?.activeVaultId;
    if (repo == null || seed == null || seed.isEmpty) return;
    if (vaultId == null || vaultId.isEmpty) return;
    if (_historyLoadedForVault == vaultId) return;
    final records = await repo.load(vaultId, seed);
    _signConfirmation.hydrate(records);
    _historyLoadedForVault = vaultId;
    notifyListeners();
  }

  /// Clear history from memory and storage (every vault).
  Future<void> clearHistory() async {
    _signConfirmation.clearHistory();
    _historyLoadedForVault = null;
    await _historyRepo?.clear();
    notifyListeners();
  }

  /// The active vault changed inside a live session (switch / removal / first
  /// add). Refresh the BLE signing context, then swap the in-memory history for
  /// the new vault's — keeping the previous vault's records would let the next
  /// sign persist them into *this* vault's slot.
  void _onActiveVaultChanged() {
    _bleSession?.onActiveVaultChanged();
    _historyLoadedForVault = null;
    unawaited(loadHistory());
  }

  /// Vaults were destroyed for good. Drop their persisted history, and the
  /// in-memory copy too when it belonged to one of them.
  void _onVaultsDestroyed(Set<String> vaultIds) {
    final loaded = _historyLoadedForVault;
    if (loaded != null && vaultIds.contains(loaded)) {
      _signConfirmation.clearHistory();
      _historyLoadedForVault = null;
    }
    final repo = _historyRepo;
    if (repo == null) return;
    unawaited(repo.removeVaults(vaultIds));
  }

  /// Reset the wallet: wipe **every** tier, credential and failure count,
  /// plus signing history.
  ///
  /// Backs the unlock screen's "forgot PIN → reset": the user is locked out,
  /// so the session scope is meaningless — the whole device must be cleared.
  Future<void> resetWallet() async {
    await _walletService?.resetAll();
    await clearHistory();
    notifyListeners();
  }

  // ── BLE advertising ─────────────────────────────────────────────────

  Future<void> startBleAdvertising() async {
    await _bleSession?.startAdvertising();
  }

  Future<void> stopBleAdvertising() async {
    await _bleSession?.stopAdvertising();
  }

  /// Persist a custom advertised BLE name and apply it to the peripheral.
  ///
  /// Restarts a live advertiser so the new name reaches the air immediately,
  /// but only while broadcasting — a connected host keeps its session and
  /// picks up the new name on the next advertise.
  Future<void> setBleDeviceName(String name) async {
    _settingsService.setBleName(name);
    final bp = _blePeripheral;
    if (bp == null) return;

    final wasBroadcasting = bp.state == BleState.broadcasting;
    await bp.setDeviceName(name);
    if (wasBroadcasting) {
      await stopBleAdvertising();
      await startBleAdvertising();
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────

  String? _currentScreen;
  String? get currentScreen => _currentScreen;

  void setScreen(String screen) {
    _currentScreen = screen;
    notifyListeners();
  }

  // ── Cleanup ────────────────────────────────────────────────────────

  @override
  void dispose() {
    _settingsService.removeListener(_onSettingsChanged);
    _bleSession?.dispose();
    _signConfirmation.dispose();
    _blePeripheral?.dispose();
    _chainHostBridge.dispose();
    super.dispose();
  }
}
