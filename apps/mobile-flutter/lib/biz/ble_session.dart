/// BLE session lifecycle, auto-lock timer, and APDU command dispatch.
///
/// Extracted from [AppState] to separate BLE/session concerns from global
/// app state management (ChangeNotifier, navigation, settings).
///
/// Responsibilities:
///   1. **Auto-lock timers** — a background timeout and a foreground idle
///      timeout (sliding window: every user interaction restarts it); both
///      lock the wallet and fire [onWalletLocked].
///   2. **APDU-BLE bridge** — parses incoming raw APDU bytes. Chain commands
///      go to the Rust chain-app host (parked reviews reach
///      [SignConfirmation]); OS/app-level frames go to [ApduHandler].
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
import '../core/interfaces/chain_host_service.dart';
import '../core/interfaces/wallet_service.dart';
import '../core/models/apdu_message.dart';
import '../core/models/ble_types.dart';
import '../core/models/chain.dart';
import '../core/models/chain_host_reply.dart';
import '../protocols/apdu/apdu_constants.dart';
import 'apdu_handler.dart';
import 'sign_confirmation.dart';

/// Manages BLE session lifecycle, auto-lock timer, and APDU dispatch.
class BleSession {
  // ── Dependencies ──────────────────────────────────────────────────────

  final IWalletService _walletService;
  final ApduHandler _apduHandler;
  final SignConfirmation _signConfirmation;

  /// Rust chain-app host. Every chain command is routed here; `null` or an
  /// unavailable host answers INS_NOT_SUPPORTED instead of falling back to a
  /// second Dart implementation.
  final IChainHostService? _chainHost;

  // ── Auto-lock state ──────────────────────────────────────────────────

  DateTime? _backgroundedAt;
  Timer? _lockTimer;
  Timer? _idleTimer;
  bool _wasAdvertising = false;

  /// Whether the app is in the foreground. Maintained by
  /// [onAppBackgrounded] / [onAppForegrounded]; the idle timer only runs
  /// while this is `true`.
  bool _isForeground = true;

  /// True while a sign / address confirmation is pending. The idle timer is
  /// suspended so a user reviewing a request is never locked out mid-review.
  bool _idleLockSuppressed = false;

  /// Background timeout before locking.
  final Duration autoLockDuration;

  /// Foreground idle timeout (sliding window: every interaction restarts it).
  final Duration idleLockDuration;

  /// Called when the auto-lock timer fires and the wallet is locked.
  ///
  /// The caller should update UI (e.g. navigate to Unlock screen).
  void Function()? onWalletLocked;

  // ── BLE state ────────────────────────────────────────────────────────

  IBlePeripheral? _blePeripheral;
  StreamSubscription<Uint8List>? _apduSub;
  String? _seedHex;

  // ── Constructor ──────────────────────────────────────────────────────

  BleSession({
    required this._walletService,
    required this._apduHandler,
    required this._signConfirmation,
    this._chainHost,
    this.autoLockDuration = const Duration(minutes: 5),
    this.idleLockDuration = const Duration(minutes: 5),
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  BLE Peripheral setter
  // ═══════════════════════════════════════════════════════════════════════

  /// Set (or replace) the active [IBlePeripheral].
  ///
  /// Subscribes to the peripheral's APDU stream and state stream, and
  /// hands the seed to the chain host if the wallet is unlocked. Setting to
  /// `null` unsubscribes and clears the host seed.
  set blePeripheral(IBlePeripheral? bp) {
    _apduSub?.cancel();
    _apduSub = null;
    _seedHex = null;
    _chainHost?.setSeed(null);

    _blePeripheral = bp;

    if (bp != null) {
      _apduSub = bp.apduStream.listen(_onRawApdu);
      trySetApduContext();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Auto-lock
  // ═══════════════════════════════════════════════════════════════════════

  /// Call when the app enters the background.
  ///
  /// Records the current time, starts the [autoLockDuration] timer, pauses the
  /// foreground idle timer, and stops BLE advertising if active (preserving
  /// the intent to restart on foreground via [_wasAdvertising] flag).
  void onAppBackgrounded() {
    _isForeground = false;
    _backgroundedAt = DateTime.now();
    _cancelIdleTimer();
    _lockTimer?.cancel();
    _lockTimer = Timer(autoLockDuration, _onAutoLockFire);

    if (_blePeripheral != null &&
        (_blePeripheral!.state == BleState.broadcasting ||
            _blePeripheral!.state == BleState.connected)) {
      _wasAdvertising = true;
      _blePeripheral!.stopAdvertising();
    }
  }

  /// Call when the app returns to the foreground.
  ///
  /// Cancels the background timer. If the elapsed background time exceeds
  /// [autoLockDuration], locks the wallet immediately; otherwise restarts the
  /// foreground idle timer from zero. Restarts BLE advertising if it was
  /// stopped by [onAppBackgrounded].
  void onAppForegrounded() {
    _isForeground = true;
    _lockTimer?.cancel();
    _lockTimer = null;

    if (_backgroundedAt != null) {
      final elapsed = DateTime.now().difference(_backgroundedAt!);
      if (elapsed >= autoLockDuration) {
        _performLock();
      }
      _backgroundedAt = null;
    }

    if (_wasAdvertising && _blePeripheral != null) {
      _wasAdvertising = false;
      _blePeripheral!.startAdvertising();
    }

    _restartIdleTimerIfEligible();
  }

  /// Call when a wallet session opens (successful unlock or wallet setup).
  ///
  /// Unlocking does not produce a lifecycle event, so the idle window has to
  /// be started explicitly; it then slides on every [onUserActivity].
  void onSessionStarted() {
    _restartIdleTimerIfEligible();
  }

  /// Call on any foreground user interaction (pointer down).
  ///
  /// Implements the sliding window: cancels the running timer and starts a
  /// fresh [idleLockDuration], so the wallet locks only after a full window
  /// with no interaction.
  void onUserActivity() {
    _restartIdleTimerIfEligible();
  }

  /// Suspend or resume the foreground idle timer.
  ///
  /// Set while a sign / address confirmation is pending so the user is never
  /// locked out mid-review. Resuming restarts the window from zero.
  void setIdleLockSuppressed(bool suppressed) {
    if (_idleLockSuppressed == suppressed) return;
    _idleLockSuppressed = suppressed;
    if (suppressed) {
      _cancelIdleTimer();
    } else {
      _restartIdleTimerIfEligible();
    }
  }

  /// Start (or restart) the idle timer when the session is lockable.
  void _restartIdleTimerIfEligible() {
    if (!_isForeground || _idleLockSuppressed) return;
    if (!_walletService.isUnlocked) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(idleLockDuration, _onIdleLockFire);
  }

  void _cancelIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  /// Called when the auto-lock timer fires while in background.
  void _onAutoLockFire() {
    _lockTimer = null;
    _performLock();
  }

  /// Called when the foreground idle window elapses with no interaction.
  void _onIdleLockFire() {
    _idleTimer = null;
    _performLock();
  }

  /// Lock the wallet and clear all session state.
  ///
  /// BLE advertising and any live connection are left untouched: a locked
  /// device may keep advertising, and signing commands are refused by the
  /// missing APDU context (I3) rather than by tearing the link down.
  void _performLock() {
    _cancelIdleTimer();
    _lockTimer?.cancel();
    _lockTimer = null;
    _backgroundedAt = null;

    if (!_walletService.isUnlocked) return;

    _walletService.lock();
    _seedHex = null;
    _chainHost?.lock();
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

  /// Push the current wallet seed into the session cache and chain host.
  ///
  /// Reads the seed hex from [IWalletService]. The Rust host keeps its own
  /// copy and never hands it back. Does nothing if the wallet is locked or
  /// has no seed.
  void trySetApduContext() {
    if (_walletService.isUnlocked) {
      final seedHex = _walletService.seedHex;
      if (seedHex != null) {
        _seedHex = seedHex;
        _chainHost?.setSeed(seedHex);
      }
    }
  }

  /// Refresh the signing context after the wallet's **active vault** changed.
  ///
  /// A connected host must never sign with the previous vault's seed: drop
  /// the cached seed and re-read it from the wallet. Wired from
  /// `IWalletService.onActiveVaultChanged`.
  void onActiveVaultChanged() {
    _seedHex = null;
    trySetApduContext();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  APDU Command Dispatch
  // ═══════════════════════════════════════════════════════════════════════

  /// Handle an incoming raw APDU command from the BLE stream.
  ///
  /// Parses the raw bytes into an [ApduCommand], then dispatches:
  ///   - Chain commands → Rust chain-app host. The host either writes the
  ///     reply itself ([ChainHostEmit]) or parks a review that turns into a
  ///     [SignConfirmation] request.
  ///   - Everything else → [ApduHandler] (OS / app-level frames).
  ///
  /// [seedHex] is the pre-computed seed from the wallet. A chain command
  /// arriving while locked is refused with SW 0x6985; a chain command whose
  /// host cannot answer gets SW 0x6D00 — there is no second Dart
  /// implementation to fall back to.
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

      // ── Chain commands: the Rust chain-app host owns every one ────
      // ETH: GET_PUBLIC_KEY (P1=0x00 return / P1=0x01 confirm), SIGN,
      // SIGN_PERSONAL, SIGN_EIP_712. BTC (CLA 0xE1/0xF8) and Sui (0x07) keep
      // their own CLA; SOL/Tron share CLA 0xE0 and are selected by the app
      // the host opened via OPEN_APP.
      if (_isChainCommand(command)) {
        if (seedHex == null) {
          await _sendError(Sw.securityStatusNotSatisfied);
          return;
        }
        if (await _handleViaChainHost(command, ble, seedHex)) return;
        // Host missing or unable to answer — refuse instead of re-implementing
        // the chain in Dart.
        await _sendError(Sw.insNotSupported);
        return;
      }

      // ── OS / app-level frames: delegate to ApduHandler ───────────
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

  /// Whether this command belongs to a Rust chain module.
  ///
  /// CLA 0xE0 is shared by Ethereum, Solana and Tron, so the opened app decides
  /// which INS table (and therefore which module) owns the frame. BTC and Sui
  /// keep their own CLA and never depend on the app context.
  bool _isChainCommand(ApduCommand command) {
    if (command.cla == Cla.bitcoin || command.cla == Cla.bitcoinExt) {
      return command.ins == Ins.btcGetWalletPublicKey ||
          command.ins == Ins.btcSignTx;
    }
    if (command.cla == Cla.sui) {
      return command.ins == Ins.suiGetPublicKey || command.ins == Ins.suiSignTx;
    }
    if (command.cla == Cla.near) {
      return command.ins == Ins.nearGetPublicKey ||
          command.ins == Ins.nearSignTransaction ||
          command.ins == Ins.nearGetVersion;
    }
    if (command.cla != Cla.os) return false;
    switch (_apduHandler.currentApp) {
      case LedgerApp.ethereum:
        return command.ins == Ins.getPublicKey ||
            command.ins == Ins.ethSign ||
            command.ins == Ins.signEthPersonalMessage ||
            command.ins == Ins.ethSignEip712;
      case LedgerApp.solana:
        return command.ins == Ins.solGetAppConfiguration ||
            command.ins == Ins.solGetAddress ||
            command.ins == Ins.solSignMessage ||
            command.ins == Ins.solSignOffchainMessage;
      case LedgerApp.tron:
        // 0x04/0x05/0x08/0x0A/0x0C 全部由 Rust 模块处理；未实现时模块回 6D00。
        return command.ins == Ins.tronGetPublicKey ||
            command.ins == Ins.tronGetAppConfiguration ||
            command.ins == Ins.tronSignTx ||
            command.ins == Ins.tronSignHash ||
            command.ins == Ins.tronSignPersonalMessage ||
            command.ins == Ins.tronEcdhSecret ||
            command.ins == Ins.tronSignTip712;
      case LedgerApp.ton:
        // TON 的版本/应用名/公钥/签名都在模块里；0x08/0x09 回 6D00。
        return command.ins == Ins.tonGetVersion ||
            command.ins == Ins.tonGetAppName ||
            command.ins == Ins.tonGetPublicKey ||
            command.ins == Ins.tonSignTx ||
            command.ins == Ins.tonGetAddressProof ||
            command.ins == Ins.tonSignData;
      case LedgerApp.bitcoin:
      case LedgerApp.sui:
      case LedgerApp.near:
      case null:
        return false;
    }
  }

  /// Route one complete APDU through the Rust chain-app host.
  ///
  /// Returns `true` when the host produced the outcome (bytes written, or a
  /// review parked awaiting the user). Returns `false` when the host is
  /// missing, unavailable, or answered with a non-terminal status.
  Future<bool> _handleViaChainHost(
      ApduCommand command, IBlePeripheral ble, String seedHex) async {
    final host = _chainHost;
    if (host == null || !host.isAvailable) return false;

    // 选模块：BTC/Sui 有独立 CLA；CLA 0xE0 由当前打开的 App 决定
    // （Ethereum / Solana / Tron）。
    if (command.cla == Cla.bitcoin || command.cla == Cla.bitcoinExt) {
      host.openApp('openledger.bitcoin');
    } else if (command.cla == Cla.sui) {
      host.openApp('openledger.sui');
    } else if (command.cla == Cla.near) {
      host.openApp('openledger.near');
    } else if (_apduHandler.currentApp == LedgerApp.solana) {
      host.openApp('openledger.solana');
    } else if (_apduHandler.currentApp == LedgerApp.tron) {
      host.openApp('openledger.tron');
    } else if (_apduHandler.currentApp == LedgerApp.ton) {
      host.openApp('openledger.ton');
    } else {
      host.openApp('openledger.ethereum');
    }

    final ChainHostReply? reply;
    try {
      reply = host.submit(command.toBytes());
    } catch (error) {
      debugPrint('[CHAIN HOST] submit failed: $error');
      return false;
    }
    if (reply == null) return false;

    switch (reply) {
      case ChainHostEmit(:final payload):
        debugPrint('[CHAIN HOST] emit ${payload.length}B');
        await ble.sendApduResponse(payload);
        return true;

      case ChainHostReview(:final reviewId):
        if (!await _openReview(reply, seedHex)) return false;
        debugPrint('[CHAIN HOST] review #$reviewId awaiting user decision');
        return true;

      default:
        return false;
    }
  }

  /// Opens the confirmation surface matching the review's action.
  ///
  /// [seedHex] only keys the encrypted history record — the host already
  /// holds the signing key.
  Future<bool> _openReview(ChainHostReview review, String seedHex) {
    if (!review.isSign) {
      return _signConfirmation.interceptAddressCommand(
        review.address,
        review.path,
        chainReviewId: review.reviewId,
      );
    }
    return _signConfirmation.interceptChainReview(
      reviewId: review.reviewId,
      chain: _chainForReview(review),
      derivationPath: review.path,
      signingAddress: review.address,
      payloadHex: review.payloadHex,
      parsedData: _parsedFromReview(review),
      seedHex: seedHex,
    );
  }

  /// The display class comes from the module's section title, so the existing
  /// confirmation screens need no changes.
  static String _chainForReview(ChainHostReview review) {
    switch (review.sectionKind) {
      case 'review.section.transaction':
        return 'eth_tx';
      case 'review.section.eip712':
        return 'eip712';
      case 'review.section.bitcoin':
        return 'bitcoin';
      case 'review.section.solana':
        return 'solana';
      case 'review.section.sui':
        return 'sui';
      case 'review.section.tron':
        return 'tron';
      default:
        return 'personal_msg';
    }
  }

  /// Maps the module's review fields onto the shape [TxDetailsCard] renders.
  static Map<String, dynamic> _parsedFromReview(ChainHostReview review) {
    final fields = _reviewFields(review.document);
    switch (review.sectionKind) {
      case 'review.section.transaction':
        final data = fields['review.field.data'] ?? '';
        return {
          'type': 'eth_tx',
          'to': fields['review.field.to'] ?? '',
          'value': fields['review.field.value'] ?? '0',
          'gas': fields['review.field.gas'] ?? '',
          'gasPrice': fields['review.field.gas_price'] ?? '0',
          'nonce': fields['review.field.nonce'] ?? '0',
          'data': data.isEmpty || data.startsWith('0x') ? data : '0x$data',
        };
      case 'review.section.eip712':
        return {
          'type': 'eip712',
          'domainHash': fields['review.field.domain_hash'] ?? '',
          'structHash': fields['review.field.struct_hash'] ?? '',
        };
      case 'review.section.bitcoin':
        return {
          'type': 'btc_tx',
          'address': fields['review.field.address'] ?? review.address,
          'inputs': fields['review.field.inputs'] ?? '1',
        };
      case 'review.section.solana':
        return {
          'type': 'solana_tx',
          'to': fields['review.field.to'] ?? '',
          'lamports': fields['review.field.amount'] ?? '',
          'programId': fields['review.field.program'] ?? '',
          'version': fields['review.field.version'] ?? 'legacy',
        };
      case 'review.section.sui':
        return {
          'type': 'personal_msg',
          'message': '',
          'messageHex': fields['review.field.message_hex'] ?? '',
        };
      case 'review.section.tron':
        // Tron 的字段随命令与合约类型变化（多合约、通用视图），必须按顺序
        // 渲染而不是走 Map（同名 label 会被覆盖）。
        final lines = <String>[];
        final risks = review.document['risks'];
        if (risks is List) {
          for (final risk in risks) {
            if (risk is Map) {
              final line = _tronRiskLine(risk);
              if (line != null) lines.add(line);
            }
          }
        }
        for (final (label, value) in _reviewFieldEntries(review.document)) {
          switch (label) {
            case 'review.field.address':
              break; // 账户地址已由确认页头部展示
            case 'review.field.contract_type':
              lines.add(value);
            case 'review.field.contract_index':
              lines.add('Contract $value');
            case 'review.field.to':
              lines.add('To: $value');
            case 'review.field.amount':
              lines.add('Amount: $value');
            case 'review.field.contract':
              lines.add('Contract: $value');
            case 'review.field.selector':
              lines.add('Selector: 0x$value');
            case 'review.field.asset':
              lines.add('Asset: $value');
            case 'review.field.permission':
              lines.add('Permission: $value');
            case 'review.field.domain_hash':
              lines.add('Domain: 0x$value');
            case 'review.field.struct_hash':
              lines.add('Struct: 0x$value');
            case 'review.field.hash':
              lines.add('Hash: 0x$value');
            case 'review.field.fee_limit':
              lines.add('Fee limit: $value sun');
            case 'review.field.message_hex':
              break; // 卡片底部已展示原始 hex
            default:
              // review.field.param：模块已格式化为 `field N: …`
              lines.add(value);
          }
        }
        return {
          'type': 'personal_msg',
          'message': lines.join('\n'),
          'messageHex': review.payloadHex,
        };
      default:
        return {
          'type': 'personal_msg',
          'message': fields['review.field.message'] ?? '',
          'messageHex': fields['review.field.message_hex'] ?? '',
        };
    }
  }

  /// Ordered `(label_key, display value)` pairs.
  ///
  /// Tron multi-contract / generic reviews repeat the same label key, so they
  /// must not go through [_reviewFields]' map.
  static List<(String, String)> _reviewFieldEntries(
      Map<String, dynamic> document) {
    final out = <(String, String)>[];
    final sections = document['sections'];
    if (sections is! List) return out;
    for (final section in sections) {
      final fields = section is Map ? section['fields'] : null;
      if (fields is! List) continue;
      for (final field in fields) {
        if (field is! Map) continue;
        final label = field['label_key'];
        final value = field['value'];
        if (label is! String || value is! Map) continue;
        final String? text = switch (value['type']) {
          'amount' || 'fee' => value['raw'] as String?,
          'bytes' || 'text' || 'address' => value['value'] as String?,
          _ => null,
        };
        if (text != null) out.add((label, text));
      }
    }
    return out;
  }

  /// Tron 风险项 → 确认页上的一行提示。没有对应文案时返回 `null`。
  static String? _tronRiskLine(Map<dynamic, dynamic> risk) {
    final prefix = risk['severity'] == 'critical' ? '[HIGH RISK]' : '[WARNING]';
    return switch (risk['code']) {
      'tron.unknown_contract_type' =>
        '$prefix Unverified contract type — check the raw payload before signing',
      'tron.unknown_selector' =>
        '$prefix Unrecognized contract call — verify the target and call value',
      'tron.critical_contract_type' =>
        '$prefix Permission or contract-creation transaction — high risk',
      'tron.sign_by_hash' => '$prefix Blind signing: only a transaction hash is provided',
      _ => null,
    };
  }

  /// `label_key` → display value: text/address/bytes carry `value`, amounts and
  /// fees carry a decimal `raw`.
  static Map<String, String> _reviewFields(Map<String, dynamic> document) {
    final out = <String, String>{};
    final sections = document['sections'];
    if (sections is! List) return out;
    for (final section in sections) {
      final fields = section is Map ? section['fields'] : null;
      if (fields is! List) continue;
      for (final field in fields) {
        if (field is! Map) continue;
        final label = field['label_key'];
        final value = field['value'];
        if (label is! String || value is! Map) continue;
        final String? text = switch (value['type']) {
          'amount' || 'fee' => value['raw'] as String?,
          'bytes' || 'text' || 'address' => value['value'] as String?,
          _ => null,
        };
        if (text != null) out[label] = text;
      }
    }
    return out;
  }

  /// Completes a review parked by the Rust chain-app host.
  ///
  /// Returns the full APDU response (data + status word) the host encoded, or
  /// `null` when the host could not produce a terminal response.
  Uint8List? resolveChainReview(int reviewId, {required bool approved}) {
    final bytes = _chainHost?.resolve(reviewId, approved: approved);
    debugPrint('[CHAIN HOST] resolve #$reviewId approved=$approved → '
        '${bytes == null ? 'no response' : '${bytes.length}B'}');
    return bytes;
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

  // ═══════════════════════════════════════════════════════════════════════
  //  Cleanup
  // ═══════════════════════════════════════════════════════════════════════

  /// Dispose all managed resources.
  ///
  /// Cancels both auto-lock timers and unsubscribes from the APDU stream.
  /// Does NOT dispose the peripheral — the caller owns its lifecycle.
  void dispose() {
    _lockTimer?.cancel();
    _lockTimer = null;
    _cancelIdleTimer();
    _apduSub?.cancel();
    _apduSub = null;
    _seedHex = null;
    _blePeripheral = null;
  }
}
