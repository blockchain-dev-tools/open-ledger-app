/// BLE session lifecycle, auto-lock timer, and APDU command dispatch.
///
/// Extracted from [AppState] to separate BLE/session concerns from global
/// app state management (ChangeNotifier, navigation, settings).
///
/// Responsibilities:
///   1. **Auto-lock timer** — 5-minute background timeout; locks wallet and
///      fires [onWalletLocked] callback.
///   2. **APDU-BLE bridge** — parses incoming raw APDU bytes, dispatches
///      sign commands to [SignConfirmation] and all others to [ApduHandler].
///   3. **BLE advertising management** — thin wrappers around
///      [IBlePeripheral] with _wasAdvertising flag tracking for
///      foreground/background transitions.
///
/// The peripheral is NOT owned — set via the [blePeripheral] setter.
/// The caller is responsible for creating and disposing the peripheral.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/interfaces/ble_peripheral.dart';
import '../core/interfaces/wallet_service.dart';
import '../core/models/apdu_message.dart';
import '../core/models/ble_types.dart';
import '../core/models/chain.dart';
import '../protocols/apdu/apdu_constants.dart';
import '../protocols/apdu/eth_tx_assembler.dart';
import 'apdu_handler.dart';
import 'path_parser.dart';
import 'sign_confirmation.dart';

/// Manages BLE session lifecycle, auto-lock timer, and APDU dispatch.
class BleSession {
  // ── Dependencies ──────────────────────────────────────────────────────

  final IWalletService _walletService;
  final ApduHandler _apduHandler;
  final SignConfirmation _signConfirmation;

  // ── Auto-lock state ──────────────────────────────────────────────────

  DateTime? _backgroundedAt;
  Timer? _lockTimer;
  bool _wasAdvertising = false;

  static const Duration _autoLockDuration = Duration(minutes: 5);

  /// Called when the auto-lock timer fires and the wallet is locked.
  ///
  /// The caller should update UI (e.g. navigate to Unlock screen).
  void Function()? onWalletLocked;

  // ── BLE state ────────────────────────────────────────────────────────

  IBlePeripheral? _blePeripheral;
  StreamSubscription<Uint8List>? _apduSub;
  StreamSubscription<BleState>? _stateSub;
  String? _seedHex;

  /// ETH transaction APDU assembler — accumulates chunked INS=0x04
  /// P1=0x00/0x80 APDUs into a complete RLP payload before producing
  /// a [SigningIntent] for user confirmation.
  ///
  /// State is cleared on BLE disconnect/error, wallet lock, and
  /// new first chunk (P1=0x00 always resets).
  final EthTxAssembler _ethTxAssembler = EthTxAssembler();

  // ── Constructor ──────────────────────────────────────────────────────

  BleSession({
    required this._walletService,
    required this._apduHandler,
    required this._signConfirmation,
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  BLE Peripheral setter
  // ═══════════════════════════════════════════════════════════════════════

  /// Set (or replace) the active [IBlePeripheral].
  ///
  /// Subscribes to the peripheral's APDU stream and state stream, and
  /// sets the APDU context if the wallet is unlocked. Setting to `null`
  /// unsubscribes and clears the handler context.
  ///
  /// The state-stream subscription resets the ETH tx assembler on
  /// [BleState.idle] / [BleState.error] transitions so a half-assembled
  /// transaction cannot be completed across a disconnect or BLE error.
  set blePeripheral(IBlePeripheral? bp) {
    _apduSub?.cancel();
    _apduSub = null;
    _stateSub?.cancel();
    _stateSub = null;
    _apduHandler.clearContext();
    _ethTxAssembler.reset();
    _seedHex = null;

    _blePeripheral = bp;

    if (bp != null) {
      _apduSub = bp.apduStream.listen(_onRawApdu);
      _stateSub = bp.stateStream.listen(_onBleState);
      trySetApduContext();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Auto-lock
  // ═══════════════════════════════════════════════════════════════════════

  /// Call when the app enters the background.
  ///
  /// Records the current time, starts a [Duration(minutes: 5)] auto-lock
  /// timer, and stops BLE advertising if active (preserving the intent
  /// to restart on foreground via [_wasAdvertising] flag).
  void onAppBackgrounded() {
    _backgroundedAt = DateTime.now();
    _lockTimer?.cancel();
    _lockTimer = Timer(_autoLockDuration, _onAutoLockFire);

    if (_blePeripheral != null &&
        (_blePeripheral!.state == BleState.broadcasting ||
            _blePeripheral!.state == BleState.connected)) {
      _wasAdvertising = true;
      _blePeripheral!.stopAdvertising();
    }
  }

  /// Call when the app returns to the foreground.
  ///
  /// Cancels the auto-lock timer. If the elapsed background time exceeds
  /// [Duration(minutes: 5)], locks the wallet immediately. Restarts BLE
  /// advertising if it was stopped by [onAppBackgrounded].
  void onAppForegrounded() {
    _lockTimer?.cancel();
    _lockTimer = null;

    if (_backgroundedAt != null) {
      final elapsed = DateTime.now().difference(_backgroundedAt!);
      if (elapsed >= _autoLockDuration) {
        _performLock();
      }
      _backgroundedAt = null;
    }

    if (_wasAdvertising && _blePeripheral != null) {
      _wasAdvertising = false;
      _blePeripheral!.startAdvertising();
    }
  }

  /// Called when the auto-lock timer fires while in background.
  void _onAutoLockFire() {
    _performLock();
  }

  /// Lock the wallet and clear all session state.
  void _performLock() {
    if (!_walletService.isUnlocked) return;

    _walletService.lock();
    _seedHex = null;
    _ethTxAssembler.reset();
    _apduHandler.clearContext();
    onWalletLocked?.call();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  BLE Advertising (thin wrappers)
  // ═══════════════════════════════════════════════════════════════════════

  /// Start BLE advertising.
  ///
  /// Sets the APDU handler context from the current wallet state before
  /// starting advertising. Safe to call when no peripheral is set.
  Future<void> startAdvertising() async {
    if (_blePeripheral == null) return;
    trySetApduContext();
    await _blePeripheral!.startAdvertising();
  }

  /// Stop BLE advertising.
  ///
  /// Safe to call when no peripheral is set.
  Future<void> stopAdvertising() async {
    if (_blePeripheral == null) return;
    await _blePeripheral!.stopAdvertising();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  APDU Context
  // ═══════════════════════════════════════════════════════════════════════

  /// Set the APDU handler context from the current wallet state.
  ///
  /// Reads the seed hex from [IWalletService] and passes it to both
  /// [ApduHandler] and the internal cache. Does nothing if the wallet
  /// is locked or has no seed.
  void trySetApduContext() {
    if (_walletService.isUnlocked) {
      final seedHex = _walletService.seedHex;
      if (seedHex != null) {
        _seedHex = seedHex;
        _apduHandler.setContext(seedHex: seedHex);
      }
    }
  }

  /// Refresh the signing context after the wallet's **active vault** changed.
  ///
  /// A connected host must never sign with the previous vault's seed: drop any
  /// half-assembled chunked transaction (its payload was collected for the old
  /// seed) and re-read the seed from the wallet. Wired from
  /// `IWalletService.onActiveVaultChanged`.
  void onActiveVaultChanged() {
    _ethTxAssembler.reset();
    _seedHex = null;
    _apduHandler.clearContext();
    trySetApduContext();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  APDU Command Dispatch
  // ═══════════════════════════════════════════════════════════════════════

  /// Handle an incoming raw APDU command from the BLE stream.
  ///
  /// Parses the raw bytes into an [ApduCommand], then dispatches:
  ///   - Sign commands → [SignConfirmation.interceptSignCommand]
  ///     (creates a pending request, triggers UI navigation)
  ///   - All others → [ApduHandler.handle]
  ///     (processed immediately, response sent over BLE)
  ///
  /// [seedHex] is the pre-computed seed from the wallet — used by
  /// [SignConfirmation] to derive the signing address. May be `null`
  /// when the wallet is locked; sign commands will be rejected.
  Future<void> onApduCommand(Uint8List rawApdu, String? seedHex) async {
    final ble = _blePeripheral;
    if (ble == null) return;

    final apduHex = rawApdu
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
    debugPrint('[APDU IN]  len=${rawApdu.length}  $apduHex');

    try {
      final command = ApduCommand.fromBytes(rawApdu);
      debugPrint(
          '[APDU IN]  parsed: CLA=0x${command.cla.toRadixString(16).padLeft(2, '0')} '
          'INS=0x${command.ins.toRadixString(16).padLeft(2, '0')} '
          'P1=0x${command.p1.toRadixString(16).padLeft(2, '0')} '
          'P2=0x${command.p2.toRadixString(16).padLeft(2, '0')} '
          'dataLen=${command.data?.length ?? 0}');

      // ── ETH tx chunked assembly (INS=0x04) ─────────────────────
      // Intercept before isSignCommand — chunked ETH tx must be
      // assembled into a complete RLP before showing one confirmation.
      // Every ETH_SIGN APDU goes here so P1/P2 are validated and the
      // P2 flow-control byte is honoured (see _handleEthTxApdu).
      // Guarded by the Ethereum app context: INS 0x04 in the Solana app
      // is GET_VERSION (no data, different P1/P2) and must not be fed
      // to the RLP assembler.
      if (_apduHandler.currentApp == LedgerApp.ethereum &&
          command.cla == Cla.os &&
          command.ins == Ins.ethSign) {
        await _handleEthTxApdu(command, ble, seedHex);
        return;
      }

      // ── ETH address display + confirm (INS=0x02, P1=0x01) ────────
      // On a real Ledger, GET_PUBLIC_KEY P1=0x01 means "show the address
      // on screen and wait for the user to confirm". Route it through the
      // address confirmation UI instead of returning the address at once.
      if (_apduHandler.currentApp == LedgerApp.ethereum &&
          command.cla == Cla.os &&
          command.ins == Ins.getPublicKey &&
          command.p1 == P1.ethConfirm) {
        await _handleEthConfirmAddress(command, ble, seedHex);
        return;
      }

      // ── Sign-interception: delegate to SignConfirmation ──────────
      if (SignConfirmation.isSignCommand(command,
          currentApp: _apduHandler.currentApp)) {
        if (seedHex == null) {
          await _sendError(Sw.securityStatusNotSatisfied);
          return;
        }

        final intercepted =
            await _signConfirmation.interceptSignCommand(command, seedHex);
        if (!intercepted) {
          await _sendError(Sw.wrongData);
        }
        // If intercepted, the response will be sent later via approve() / reject().
        return;
      }

      // ── Non-sign: delegate to ApduHandler ────────────────────────
      final response = _apduHandler.handle(command);
      final responseBytes = response.toBytes();
      final responseHex = responseBytes
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');
      debugPrint(
          '[APDU OUT] len=${responseBytes.length}  $responseHex  '
          'SW=0x${response.statusWord.toRadixString(16).padLeft(4, '0')}  '
          'isSuccess=${response.isSuccess}');

      await ble.sendApduResponse(responseBytes);
    } catch (e, stack) {
      debugPrint('[APDU ERR] $e\n$stack');
      await _sendError(Sw.unknownError);
    }
  }

  /// Handle an ETH_SIGN APDU (INS=0x04) — validates P1/P2 and assembles the
  /// transaction.
  ///
  /// P1: 0x00 starts/restarts assembly — parses the derivation path from
  /// the APDU data, stores it, and begins accumulating RLP bytes.
  /// 0x80 appends raw RLP bytes (no path parsing). Anything else is
  /// SWO_WRONG_P1_P2 (0x6A86).
  ///
  /// P2 (official `app-ethereum/doc/apdu.md:101-103`):
  /// 0x00 process & start flow (assemble, then confirm + sign);
  /// 0x01 store only (assemble but never sign); 0x02 start flow with no
  /// data (acknowledge and wait for the first block).
  ///
  /// Incomplete chunks receive SW 9000 immediately and never create a
  /// confirmation request. When the RLP is complete, produces a
  /// [SigningIntent] via [SignConfirmation.interceptIntent] which
  /// triggers the confirmation UI. The response is sent later via
  /// [SignConfirmation.approve] / [.reject].
  Future<void> _handleEthTxApdu(
      ApduCommand command, IBlePeripheral ble, String? seedHex) async {
    if (seedHex == null) {
      await _sendError(Sw.securityStatusNotSatisfied);
      return;
    }

    // P1 = first / subsequent block; P2 = flow control.
    if (command.p1 != 0x00 && command.p1 != 0x80) {
      await _sendError(Sw.incorrectP1P2);
      return;
    }
    if (command.p2 != 0x00 && command.p2 != 0x01 && command.p2 != 0x02) {
      await _sendError(Sw.incorrectP1P2);
      return;
    }

    // P2=0x02 — start flow with no data: acknowledge and wait for the
    // first block (P1=0x00). Nothing is assembled yet.
    if (command.p2 == 0x02) {
      await _sendSuccess();
      return;
    }

    // P2=0x01 — store only: accumulate but never produce a signature.
    final storeOnly = command.p2 == 0x01;
    final data = command.data;

    if (command.p1 == 0x00) {
      // First chunk — parse derivation path + RLP start.
      if (data == null || data.isEmpty) {
        _ethTxAssembler.reset();
        await _sendError(Sw.wrongData);
        return;
      }

      final pathResult = PathParser.parsePathWithRemainder(data);
      if (pathResult == null) {
        // Malformed path — reset assembly and return error.
        _ethTxAssembler.reset();
        await _sendError(Sw.wrongData);
        return;
      }

      final result = _ethTxAssembler.handleFirstChunk(
        derivationPath: pathResult.path,
        seedHex: seedHex,
        rlpData: pathResult.remainder,
      );

      await _processEthAssemblyResult(result, ble, storeOnly: storeOnly);
      return;
    }

    // P1=0x80 — continuation chunk.
    if (data == null || data.isEmpty) {
      await _sendError(Sw.wrongData);
      return;
    }

    final result = _ethTxAssembler.handleContinuation(data);
    await _processEthAssemblyResult(result, ble, storeOnly: storeOnly);
  }

  /// Process an [EthAssemblyResult] from the assembler.
  ///
  /// - Incomplete → send SW 9000 immediately (no confirmation).
  /// - Complete → create a [SigningIntent] via [interceptIntent] and
  ///   trigger the confirmation UI. Response is sent later via
  ///   approve/reject.
  /// - Error → send the error status word over BLE.
  ///
  /// [storeOnly] (P2=0x01) suppresses the confirmation/signature: the
  /// accumulated transaction is discarded with SW 9000 once complete.
  Future<void> _processEthAssemblyResult(
      EthAssemblyResult result, IBlePeripheral ble,
      {bool storeOnly = false}) async {
    if (result.isError) {
      await _sendError(result.errorSw!);
      return;
    }

    if (result.isComplete) {
      if (storeOnly) {
        // P2=0x01 — store only: accept the data, return no signature.
        _ethTxAssembler.reset();
        await _sendSuccess();
        return;
      }
      // RLP is fully assembled — create a SigningIntent and intercept.
      final intercepted = await _signConfirmation.interceptIntent(
        chain: 'ethereum',
        derivationPath: result.derivationPath!,
        seedHex: result.seedHex!,
        payload: result.payload!,
      );
      if (!intercepted) {
        await _sendError(Sw.wrongData);
      }
      // If intercepted, the response will be sent later via approve/reject.
      return;
    }

    // Incomplete — send SW 9000 immediately, no confirmation.
    await _sendSuccess();
  }

  /// Handle ETH GET_PUBLIC_KEY (INS 0x02) with P1=0x01 — display the
  /// address and wait for the user to confirm before returning it.
  ///
  /// Derives the address from the derivation path in [command] (defaulting
  /// to `m/44'/60'/0'/0/0` when none is supplied), then creates a pending
  /// address request via [SignConfirmation.interceptAddressCommand]. The
  /// response is delivered later via [SignConfirmation.approveAddress] /
  /// [SignConfirmation.rejectAddress].
  Future<void> _handleEthConfirmAddress(
      ApduCommand command, IBlePeripheral ble, String? seedHex) async {
    if (seedHex == null) {
      await _sendError(Sw.securityStatusNotSatisfied);
      return;
    }

    // P2 ∈ {0x00 no chain code, 0x01 chain code}.
    if (command.p2 != P2.ethNoChainCode && command.p2 != P2.ethChainCode) {
      await _sendError(Sw.incorrectP1P2);
      return;
    }

    // Default path when none is provided (matches _handleGetPublicKey).
    String? path = PathParser.parsePath(command.data);
    if (path == null && (command.data == null || command.data!.isEmpty)) {
      path = "m/44'/60'/0'/0/0";
    }
    if (path == null) {
      await _sendError(Sw.wrongData);
      return;
    }

    final address = _apduHandler.deriveEthAddressForPath(path);
    if (address == null) {
      await _sendError(Sw.unknownError);
      return;
    }

    final intercepted =
        await _signConfirmation.interceptAddressCommand(command, address, path);
    if (!intercepted) {
      await _sendError(Sw.wrongData);
    }
    // If intercepted, the response is sent later via approveAddress/rejectAddress.
  }

  /// Send a success APDU response (SW 9000, no data) over BLE.
  Future<void> _sendSuccess() async {
    final ble = _blePeripheral;
    if (ble == null) return;
    final resp = ApduResponse(data: null, sw1: 0x90, sw2: 0x00);
    await ble.sendApduResponse(resp.toBytes());
  }

  /// Send an error APDU response over BLE.
  ///
  /// Constructs an [ApduResponse] with the given status word and no
  /// data payload. Does nothing if no peripheral is connected.
  Future<void> _sendError(int sw) async {
    final ble = _blePeripheral;
    if (ble == null) return;
    final resp = ApduResponse(
      data: null,
      sw1: (sw >> 8) & 0xFF,
      sw2: sw & 0xFF,
    );
    await ble.sendApduResponse(resp.toBytes());
  }

  /// BLE stream listener entry-point — captures the current [_seedHex]
  /// and delegates to [onApduCommand].
  void _onRawApdu(Uint8List rawApdu) {
    onApduCommand(rawApdu, _seedHex);
  }

  /// BLE state-stream listener — resets the ETH tx assembler when the
  /// peripheral transitions to [BleState.idle] or [BleState.error].
  ///
  /// A half-assembled chunked ETH transaction must not survive a
  /// disconnect or BLE error: the next first chunk starts a fresh
  /// assembly. [BleState.broadcasting] and [BleState.connected] do not
  /// reset — the session is still active and a pending multi-chunk
  /// transaction may legitimately span the transition.
  void _onBleState(BleState state) {
    if (state == BleState.idle || state == BleState.error) {
      _ethTxAssembler.reset();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Cleanup
  // ═══════════════════════════════════════════════════════════════════════

  /// Dispose all managed resources.
  ///
  /// Cancels the auto-lock timer, unsubscribes from the APDU and state
  /// streams, and clears the APDU handler context. Does NOT dispose the
  /// peripheral — the caller owns its lifecycle.
  void dispose() {
    _lockTimer?.cancel();
    _lockTimer = null;
    _apduSub?.cancel();
    _apduSub = null;
    _stateSub?.cancel();
    _stateSub = null;
    _apduHandler.clearContext();
    _ethTxAssembler.reset();
    _seedHex = null;
    _blePeripheral = null;
  }
}
