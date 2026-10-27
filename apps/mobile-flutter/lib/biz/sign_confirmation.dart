import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/interfaces/crypto_service.dart';
import '../core/interfaces/history_repository.dart';
import '../core/models/apdu_message.dart';
import '../core/models/chain.dart';
import '../core/models/signature_record.dart';
import '../core/models/signing_intent.dart';
import '../protocols/apdu/apdu_constants.dart';
import 'apdu_handler.dart';
import 'path_parser.dart';

/// Manages the BLE sign-request interception lifecycle.
///
/// Extracted from [AppState] to separate business logic from app
/// lifecycle / BLE I/O. Owns the state machine for:
///   1. Intercepting signing APDU commands
///   2. Holding pending requests for user confirmation
///   3. Backstop that answers the host if the UI never resolves a request
///   4. Result storage after approve/reject/timeout
///
/// All crypto operations go through [ICryptoService] — never imports
/// [CryptoBridge] directly. Derivation path extraction delegates to
/// [PathParser.parsePathWithRemainder].
///
/// Callbacks:
///   [onRequestPending] — triggered when a new sign request is intercepted
///                        (caller should navigate to TransactionScreen).
///   [onRequestResolved] — triggered after approve, reject, or timeout
///                         (caller should navigate away from confirmation).
///
/// Usage:
/// ```dart
/// final sc = SignConfirmation(crypto: crypto, apduHandler: apduHandler);
/// sc.onRequestPending = () => router.go('/transaction');
/// sc.onRequestResolved = () => router.go('/');
///
/// // In BLE APDU dispatcher:
/// if (SignConfirmation.isSignCommand(cmd)) {
///   await sc.interceptSignCommand(cmd, seedHex);
///   return;
/// }
///
/// // On user approve:
/// await sc.approve(() {
///   final resp = apduHandler.handle(req.command);
///   final bytes = resp.toBytes();
///   ble.sendApduResponse(bytes);
///   return bytes;
/// });
/// ```
class SignConfirmation {
  final ICryptoService _crypto;
  final ApduHandler _apduHandler;

  /// Called when a new sign request needs user confirmation.
  /// The caller should navigate to the TransactionScreen.
  void Function()? onRequestPending;

  /// Called after the pending request is resolved (approved/rejected/timed out).
  /// The caller should navigate away from the confirmation screen.
  void Function()? onRequestResolved;

  /// Called when a GET_PUBLIC_KEY P1=0x01 request needs the user to confirm
  /// the displayed address. The caller should navigate to the address
  /// confirmation screen.
  void Function()? onAddressRequestPending;

  /// Called after the pending address request is resolved
  /// (approved/rejected/timed out).
  void Function()? onAddressRequestResolved;

  PendingSignRequest? _pendingRequest;
  PendingSignRequest? get pendingRequest => _pendingRequest;

  /// The pending address-display request, if any.
  PendingAddressRequest? _pendingAddress;
  PendingAddressRequest? get pendingAddressRequest => _pendingAddress;

  Map<String, dynamic>? _lastSignResult;
  Map<String, dynamic>? get lastSignResult => _lastSignResult;

  /// Chronological list of completed signature operations.
  final List<SignatureRecord> _history = [];
  List<SignatureRecord> get history => List.unmodifiable(_history);

  /// Maximum number of records kept in memory and on disk (oldest dropped).
  static const int maxHistoryRecords = 200;

  /// Persistence backend, attached by [AppState]. When null, history is
  /// kept in memory only.
  IHistoryRepository? _historyRepo;

  /// Sends a terminal status word over BLE for a request that expired
  /// without the confirmation UI resolving it. Injected by [AppState],
  /// which owns the BLE peripheral. When null, the backstop still clears
  /// local state but writes nothing.
  Future<void> Function(int statusWord)? sendTerminalStatus;

  /// How long a pending request may stay unresolved before the state layer
  /// answers the host with [Sw.executionError] (0x6400) itself.
  ///
  /// This is a **backstop**, not the primary timeout: the confirmation
  /// screens run their own 60s countdown and resolve first in normal
  /// operation. It exists so a request whose screen never mounted (failed
  /// navigation, replaced route) still gets a terminal response instead of
  /// leaving the host waiting and the idle-lock suppression latched.
  final Duration confirmationBackstop;

  Timer? _signBackstop;
  Timer? _addressBackstop;

  /// Guard flag to prevent duplicate approve/reject/timeout actions.
  /// Set to `true` while a resolution is in progress (awaiting BLE
  /// response delivery). Prevents response races when the user
  /// double-taps approve or a timeout fires during approval.
  bool _isResolving = false;

  SignConfirmation({
    required this._crypto,
    required this._apduHandler,
    this.confirmationBackstop = const Duration(seconds: 65),
    this.onRequestPending,
    this.onRequestResolved,
  });

  // ═══════════════════════════════════════════════════════════════════
  //  Static helpers — command detection
  // ═══════════════════════════════════════════════════════════════════

  /// Whether this APDU command is a sign operation needing confirmation.
  ///
  /// [currentApp] is the Ledger app opened via OPEN_APP (see
  /// [ApduHandler.currentApp]): CLA 0xE0's INS table is shared between the
  /// Ethereum and Solana apps with OVERLAPPING codes, so it cannot be
  /// decoded from the raw INS byte alone.
  static bool isSignCommand(ApduCommand cmd,
      {LedgerApp? currentApp}) {
    if (cmd.cla == Cla.os || cmd.cla == Cla.global) {
      // Dashboard: no app is open, so no CLA-0xE0 INS table is loaded and
      // nothing can be a sign command.
      if (currentApp == null) return false;
      // Tron app table: Tron signing is not supported yet (no sha256-based
      // secp256k1 signer in the Rust FFI), so never intercept. Without this
      // guard, INS 0x04 would fall through to the Ethereum table and be
      // mistaken for ETH_SIGN.
      if (currentApp == LedgerApp.tron) return false;
      // Solana app table: 0x06 SIGN, 0x07 SIGN_OFFCHAIN.
      if (currentApp == LedgerApp.solana) {
        return cmd.ins == Ins.solSignMessage ||
            cmd.ins == Ins.solSignOffchainMessage;
      }
      // Ethereum app table.
      // ETH RLP transaction (INS 0x04).
      if (cmd.ins == Ins.ethSign) return true;
      if (cmd.ins == Ins.signEthPersonalMessage) return true;
      // EIP-712 V0 (INS 0x0C): the 64-byte domain+struct hash payload is
      // signed as a single APDU. A shorter payload is not a sign request.
      if (cmd.ins == Ins.ethSignEip712 && _remainderLength(cmd) >= 64) {
        return true;
      }
      // NOTE: INS 0x0A is PROVIDE_ERC20_TOKEN_INFO — not a sign command.
      // The handler ACKs it with 9000; it must never pop a confirmation
      // (it previously collided with a fictional Solana-sign code).
      return false;
    }
    // Bitcoin
    if (cmd.cla == Cla.bitcoin || cmd.cla == Cla.bitcoinExt) {
      return cmd.ins == Ins.btcSignTx;
    }
    // Tron
    if (cmd.cla == Cla.tron) {
      return cmd.ins == Ins.tronSignTx;
    }
    // Sui
    if (cmd.cla == Cla.sui) {
      return cmd.ins == Ins.suiSignTx;
    }
    return false;
  }

  /// Map an APDU command to a chain name for parsing / display.
  ///
  /// [currentApp] disambiguates the shared CLA 0xE0 INS table
  /// (Ethereum vs Solana) — see [isSignCommand].
  static String chainFromCommand(ApduCommand cmd,
      {LedgerApp? currentApp}) {
    if (cmd.cla == Cla.os || cmd.cla == Cla.global) {
      if (currentApp == LedgerApp.tron) return 'tron';
      if (currentApp == LedgerApp.solana) return 'solana';
      if (cmd.ins == Ins.signEthPersonalMessage) return 'personal_msg';
      // EIP-712 V0 (INS 0x0C) with a full 64-byte domain+struct payload.
      if (cmd.ins == Ins.ethSignEip712 && _remainderLength(cmd) >= 64) {
        return 'eip712';
      }
      return 'ethereum'; // ETH_SIGN
    }
    if (cmd.cla == Cla.bitcoin || cmd.cla == Cla.bitcoinExt) return 'bitcoin';
    if (cmd.cla == Cla.tron) return 'tron';
    if (cmd.cla == Cla.sui) return 'sui';
    return 'unknown';
  }

  /// Compute the payload remainder length after the BIP-32 path in [cmd].
  ///
  /// APDU data format: `[depth(1B)] [4B × depth] [remainder...]`.
  /// Returns 0 if data is null/empty or the path is malformed (depth > 10
  /// or data shorter than path bytes).
  static int _remainderLength(ApduCommand cmd) {
    final data = cmd.data;
    if (data == null || data.isEmpty) return 0;
    final depth = data[0];
    if (depth > 10) return 0; // matches PathParser sanity check
    final pathBytes = 1 + depth * 4;
    if (data.length < pathBytes) return 0;
    return data.length - pathBytes;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Interception
  // ═══════════════════════════════════════════════════════════════════

  /// Intercept a signing APDU command.
  ///
  /// Extracts the derivation path via [PathParser], derives the signing
  /// address via [ICryptoService], parses the transaction payload, and
  /// creates a [PendingSignRequest]. Triggers [onRequestPending] so the
  /// caller can navigate to the confirmation screen. Starts the backstop.
  ///
  /// Returns `true` if the request was successfully intercepted and stored
  /// as pending. Returns `false` if the command data was invalid (caller
  /// should send an error APDU response over BLE).
  Future<bool> interceptSignCommand(
      ApduCommand command, String seedHex) async {
    var data = command.data;
    if (data == null || data.isEmpty) return false;

    final chain =
        chainFromCommand(command, currentApp: _apduHandler.currentApp);

    // OKX prefixes Solana signing frames with a `num_signers` byte that
    // standard Ledger clients omit. Strip it before parsing the path.
    if (chain == 'solana') {
      data = PathParser.stripNumSignersPrefix(data);
    }

    // Extract derivation path + remainder payload.
    final pathResult = PathParser.parsePathWithRemainder(data);
    if (pathResult == null) return false;
    final address = _deriveAddress(seedHex, pathResult.path, chain);

    // EIP-712 V0 (INS 0x0C) carries the domain+struct hashes inline; the
    // personal_msg first block carries a 4-byte BE length prefix that must
    // be dropped so the confirmation screen shows the real message.
    String payloadHex;
    if (chain == 'personal_msg' && pathResult.remainder.length >= 4) {
      // Official personal_sign layout is [path][4B BE length][message]; drop
      // the length prefix so the confirmation screen shows the real message.
      payloadHex =
          _crypto.hexEncode(Uint8List.sublistView(pathResult.remainder, 4));
    } else {
      payloadHex = _crypto.hexEncode(pathResult.remainder);
    }

    // Parse via Rust SDK.
    final jsonStr = _crypto.parseSignData(chain, payloadHex);
    Map<String, dynamic>? parsedData;
    if (jsonStr != null) {
      try {
        parsedData = jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (_) {}
    }

    await _supersedePending();

    _pendingRequest = PendingSignRequest(
      command: command,
      chain: chain,
      derivationPath: pathResult.path,
      signingAddress: address ?? 'unknown',
      payloadHex: payloadHex,
      parsedData: parsedData,
      seedHex: seedHex,
    );

    // Start the backstop; the confirmation screen resolves first normally.
    _startSignBackstop();

    // Trigger UI navigation.
    onRequestPending?.call();

    return true;
  }

  /// Intercept a pre-assembled signing intent (chunked ETH tx path).
  ///
  /// Called by [BleSession] when the [EthTxAssembler] has accumulated
  /// a complete RLP payload. Derives the signing address, parses the
  /// payload, creates a [SigningIntent] and [PendingSignRequest],
  /// and triggers [onRequestPending]. Starts the backstop.
  ///
  /// Unlike [interceptSignCommand], this does NOT hold a raw
  /// [ApduCommand] — the [PendingSignRequest.command] is `null` and
  /// [PendingSignRequest.intent] is set. On approval, the semantic
  /// signer ([signIntent]) signs the payload directly without
  /// re-dispatching a wire APDU.
  ///
  /// Returns `true` on success. Returns `false` if address derivation
  /// fails (caller should send an error APDU response).
  Future<bool> interceptIntent({
    required String chain,
    required String derivationPath,
    required String seedHex,
    required Uint8List payload,
  }) async {
    final address = _deriveAddress(seedHex, derivationPath, chain);
    final payloadHex = _crypto.hexEncode(payload);

    // Parse via Rust SDK.
    final jsonStr = _crypto.parseSignData(chain, payloadHex);
    Map<String, dynamic>? parsedData;
    if (jsonStr != null) {
      try {
        parsedData = jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (_) {}
    }

    final intent = SigningIntent(
      chain: chain,
      derivationPath: derivationPath,
      seedHex: seedHex,
      payload: payload,
      signingAddress: address ?? 'unknown',
      parsedData: parsedData,
    );

    await _supersedePending();

    _pendingRequest = PendingSignRequest(
      command: null,
      intent: intent,
      chain: chain,
      derivationPath: derivationPath,
      signingAddress: address ?? 'unknown',
      payloadHex: payloadHex,
      parsedData: parsedData,
      seedHex: seedHex,
    );

    // Start the backstop; the confirmation screen resolves first normally.
    _startSignBackstop();

    // Trigger UI navigation.
    onRequestPending?.call();

    return true;
  }

  /// Intercept an ETH GET_PUBLIC_KEY P1=0x01 request (display + confirm).
  ///
  /// On a real Ledger P1=0x01 means "show the address on screen and wait
  /// for the user to confirm". Stores a [PendingAddressRequest] holding the
  /// derived [address] and the original [command], triggers
  /// [onAddressRequestPending] so the caller can navigate to the address
  /// confirmation screen, and starts the backstop.
  ///
  /// Returns `true` on success. Returns `false` if [address] is empty.
  Future<bool> interceptAddressCommand(
      ApduCommand command, String address, String derivationPath) async {
    if (address.isEmpty) return false;

    await _supersedePending();

    _pendingAddress = PendingAddressRequest(
      command: command,
      derivationPath: derivationPath,
      address: address,
    );

    // Start the backstop; the confirmation screen resolves first normally.
    _startAddressBackstop();

    onAddressRequestPending?.call();
    return true;
  }

  /// The user approved the pending address-display request.
  ///
  /// [respond] performs the BLE response delivery — typically
  /// re-dispatching the original GET_PUBLIC_KEY command through
  /// [ApduHandler] and sending the returned address response. Awaited so
  /// delivery completes before the pending request is cleared.
  Future<void> approveAddress(Future<Uint8List> Function() respond) async {
    if (_pendingAddress == null || _isResolving) return;
    _isResolving = true;
    _cancelBackstops();

    try {
      await respond();
    } finally {
      _pendingAddress = null;
      _isResolving = false;
      onAddressRequestResolved?.call();
    }
  }

  /// The user rejected the pending address-display request.
  ///
  /// [sendError] sends the rejection (SW 0x6985) over BLE. Awaited so the
  /// error-response delivery completes before the pending request is cleared.
  Future<void> rejectAddress(Future<Uint8List> Function() sendError) async {
    if (_pendingAddress == null || _isResolving) return;
    _isResolving = true;
    _cancelBackstops();

    try {
      await sendError();
    } catch (_) {
      // Swallow — error-response delivery failure is non-critical.
    }

    _pendingAddress = null;
    _isResolving = false;
    onAddressRequestResolved?.call();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Resolution — approve / reject / timeout
  // ═══════════════════════════════════════════════════════════════════

  /// The user approved the pending sign request.
  ///
  /// [sign] is an async callback that performs the actual signing and
  /// BLE response delivery. It should:
  /// 1. Sign the payload (either semantically via [signIntent] for
  ///    intent-based requests, or via [ApduHandler.handle] for
  ///    command-based requests).
  /// 2. Send the response bytes over BLE.
  /// 3. Return the raw APDU response bytes.
  ///
  /// The callback is **awaited** — BLE response delivery is guaranteed
  /// to complete before the pending request is cleared. This prevents
  /// response races.
  ///
  /// Duplicate calls are silently ignored (via [_isResolving] guard) —
  /// if the user double-taps approve, the second call is a no-op.
  ///
  /// Extracts signature data from the response bytes, stores them in
  /// [lastSignResult], and triggers [onRequestResolved].
  Future<void> approve(Future<Uint8List> Function() sign) async {
    final req = _pendingRequest;
    if (req == null || _isResolving) return;
    _isResolving = true;
    _cancelBackstops();

    try {
      final responseBytes = await sign();
      final response = ApduResponse.fromBytes(responseBytes);
      debugPrint(
          '[SIGN] approve response SW=0x${response.statusWord.toRadixString(16).padLeft(4, '0')} len=${responseBytes.length}');

      // Store result for display.
      final parsed = req.parsedData ?? {};
      final signatureHex = _crypto.hexEncode(response.data ?? Uint8List(0));
      _lastSignResult = {
        ...parsed,
        'chain': req.chain,
        'signingAddress': req.signingAddress,
        'derivationPath': req.derivationPath,
        'signatureHex': signatureHex,
        'statusWord': response.statusWord,
        'isSuccess': response.isSuccess,
      };

      // Record to history.
      _addRecord(SignatureRecord(
        timestamp: DateTime.now(),
        chain: req.chain,
        derivationPath: req.derivationPath,
        signingAddress: req.signingAddress,
        payloadHex: req.payloadHex,
        parsedData: req.parsedData,
        isApproved: true,
        signatureHex: signatureHex,
        statusWord: response.statusWord,
      ), req.seedHex);

      _pendingRequest = null;
      onRequestResolved?.call();
    } catch (e, stack) {
      debugPrint('[SIGN] approve failed: $e\n$stack');
      // Record failed approval to history.
      _addRecord(SignatureRecord(
        timestamp: DateTime.now(),
        chain: req.chain,
        derivationPath: req.derivationPath,
        signingAddress: req.signingAddress,
        payloadHex: req.payloadHex,
        parsedData: req.parsedData,
        isApproved: true,
        signatureHex: null,
        statusWord: 0x0000,
      ), req.seedHex);

      _pendingRequest = null;
      onRequestResolved?.call();
      rethrow;
    } finally {
      _isResolving = false;
    }
  }

  /// The user rejected the pending sign request.
  ///
  /// [sendError] is an async callback that constructs an error APDU
  /// response and sends it over BLE. The callback is **awaited** —
  /// BLE error-response delivery is guaranteed to complete before
  /// the pending request is cleared. Errors from the callback are
  /// silently swallowed — error-response delivery failure is
  /// non-critical.
  ///
  /// Duplicate calls are silently ignored (via [_isResolving] guard).
  ///
  /// Clears the pending request and triggers [onRequestResolved].
  Future<void> reject(Future<Uint8List> Function() sendError) async {
    if (_pendingRequest == null || _isResolving) return;
    _isResolving = true;
    _cancelBackstops();

    // Record rejection to history before clearing request.
    final req = _pendingRequest;

    // Send error response via callback (awaited).
    try {
      await sendError();
    } catch (_) {
      // Swallow — error response delivery failure is non-critical.
    }

    if (req != null) {
      _addRecord(SignatureRecord(
        timestamp: DateTime.now(),
        chain: req.chain,
        derivationPath: req.derivationPath,
        signingAddress: req.signingAddress,
        payloadHex: req.payloadHex,
        parsedData: req.parsedData,
        isApproved: false,
        signatureHex: null,
        statusWord: 0x6985, // SW_USER_REJECTED
      ), req.seedHex);
    }

    _pendingRequest = null;
    _isResolving = false;
    onRequestResolved?.call();
  }

  /// Backstop for a signing request the confirmation UI never resolved.
  ///
  /// Answers the host with [Sw.executionError] (device-side timeout),
  /// records the timeout in history, and triggers [onRequestResolved].
  /// A resolution already in flight ([_isResolving]) wins, and a missing
  /// pending request makes this a no-op, so the screen's 60s countdown and
  /// this backstop can never both answer the same request.
  Future<void> onSignBackstopTimeout() async {
    final req = _pendingRequest;
    if (req == null || _isResolving) return;
    _isResolving = true;
    _cancelBackstops();

    await _sendTerminalStatus(Sw.executionError);

    _addRecord(SignatureRecord(
      timestamp: DateTime.now(),
      chain: req.chain,
      derivationPath: req.derivationPath,
      signingAddress: req.signingAddress,
      payloadHex: req.payloadHex,
      parsedData: req.parsedData,
      isApproved: false,
      signatureHex: null,
      statusWord: Sw.executionError,
    ), req.seedHex);

    _pendingRequest = null;
    _isResolving = false;
    onRequestResolved?.call();
  }

  /// Backstop for an address-display request the confirmation UI never
  /// resolved. Answers [Sw.executionError] and triggers
  /// [onAddressRequestResolved]; address requests carry no history entry.
  Future<void> onAddressBackstopTimeout() async {
    if (_pendingAddress == null || _isResolving) return;
    _isResolving = true;
    _cancelBackstops();

    await _sendTerminalStatus(Sw.executionError);

    _pendingAddress = null;
    _isResolving = false;
    onAddressRequestResolved?.call();
  }

  /// Resolve whatever is pending before a new request replaces it.
  ///
  /// Without this the earlier host would never receive a terminal status
  /// word: its pending request is overwritten and its backstop cancelled.
  /// The superseded request is answered with
  /// [Sw.conditionsNotSatisfied] — it can no longer be served.
  Future<void> _supersedePending() async {
    if (_isResolving) return;

    final hadSign = _pendingRequest != null;
    final hadAddress = _pendingAddress != null;
    if (!hadSign && !hadAddress) return;

    _isResolving = true;
    _cancelBackstops();
    await _sendTerminalStatus(Sw.conditionsNotSatisfied);
    _pendingRequest = null;
    _pendingAddress = null;
    _isResolving = false;

    if (hadSign) onRequestResolved?.call();
    if (hadAddress) onAddressRequestResolved?.call();
  }

  void _startSignBackstop() {
    _signBackstop?.cancel();
    _signBackstop = Timer(confirmationBackstop, onSignBackstopTimeout);
  }

  void _startAddressBackstop() {
    _addressBackstop?.cancel();
    _addressBackstop = Timer(confirmationBackstop, onAddressBackstopTimeout);
  }

  void _cancelBackstops() {
    _signBackstop?.cancel();
    _signBackstop = null;
    _addressBackstop?.cancel();
    _addressBackstop = null;
  }

  Future<void> _sendTerminalStatus(int statusWord) async {
    final send = sendTerminalStatus;
    if (send == null) return;
    try {
      await send(statusWord);
    } catch (_) {
      // Best effort: losing the response must not wedge local state.
    }
  }

  /// Drop any pending request without recording a history entry.
  ///
  /// Used when the wallet locks underneath a pending confirmation: the
  /// request can no longer be approved (there is no seed to sign with), and
  /// the confirmation UI must be dismissed. The backstops are cancelled and
  /// the matching `on…Resolved` callback fires.
  ///
  /// No APDU response is sent here — delivery stays with the caller, like
  /// [reject] / [rejectAddress]. A resolution already in flight
  /// ([_isResolving]) wins: nothing is cancelled and `false` is returned.
  ///
  /// Returns `true` when a pending request was actually dropped.
  bool cancelPending() {
    if (_isResolving) return false;

    final hadSign = _pendingRequest != null;
    final hadAddress = _pendingAddress != null;
    if (!hadSign && !hadAddress) return false;

    _cancelBackstops();
    _pendingRequest = null;
    _pendingAddress = null;

    if (hadSign) onRequestResolved?.call();
    if (hadAddress) onAddressRequestResolved?.call();
    return true;
  }

  /// Sign a [SigningIntent] semantically — no raw APDU re-dispatch.
  ///
  /// Derives the private key from [intent]'s seed + path, then calls
  /// the appropriate signing function based on [intent.chain].
  /// Returns the raw signature bytes (NOT wrapped in an APDU response).
  ///
  /// The caller (typically the `approve` callback in [AppState]) wraps
  /// the returned bytes in an [ApduResponse] and sends them over BLE.
  ///
  /// Throws if key derivation or signing fails.
  Uint8List signIntent(SigningIntent intent) {
    final privKey = _crypto.deriveSecp256k1PrivateKey(
        intent.seedHex, intent.derivationPath);
    if (privKey == null) {
      throw StateError('Key derivation failed for path ${intent.derivationPath}');
    }
    final privKeyHex = _crypto.hexEncode(privKey);
    final payloadHex = _crypto.hexEncode(intent.payload);

    Uint8List? sig;
    switch (intent.chain) {
      case 'ethereum':
      case 'bitcoin':
      case 'tron':
        // secp256k1 transaction signing (ETH/BTC/Tron all use the
        // same signEthTransaction FFI — it signs a raw hash with
        // secp256k1 + EIP-2 low-s).
        sig = _crypto.signEthTransaction(privKeyHex, payloadHex);
        break;
      case 'personal_msg':
        sig = _crypto.signEthPersonalMessage(privKeyHex, payloadHex);
        break;
      case 'eip712':
        // Payload is 64 bytes: domainHash(32) + structHash(32).
        if (intent.payload.length < 64) {
          throw StateError(
              'EIP-712 intent payload too short: ${intent.payload.length}');
        }
        final domainHex = _crypto.hexEncode(
            Uint8List.sublistView(intent.payload, 0, 32));
        final structHex = _crypto.hexEncode(
            Uint8List.sublistView(intent.payload, 32, 64));
        sig = _crypto.signEthEIP712(privKeyHex, domainHex, structHex);
        break;
      case 'solana':
      case 'sui':
        // Ed25519 message signing.
        final edKey = _crypto.deriveEd25519PrivateKey(
            intent.seedHex, intent.derivationPath);
        if (edKey == null) {
          throw StateError(
              'Ed25519 key derivation failed for path ${intent.derivationPath}');
        }
        sig = _crypto.signSolanaMessage(_crypto.hexEncode(edKey), payloadHex);
        break;
      default:
        throw StateError('Unsupported chain for semantic signing: ${intent.chain}');
    }

    if (sig == null) {
      throw StateError('Signing failed for chain ${intent.chain}');
    }
    return sig;
  }

  /// Clear the last sign result (after the result screen is dismissed).
  void clearLastSignResult() {
    _lastSignResult = null;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  History
  // ═══════════════════════════════════════════════════════════════════

  /// Attach the persistence backend used for history across restarts.
  void attachHistoryRepository(IHistoryRepository repo) {
    _historyRepo = repo;
  }

  /// Resolves the vault whose history is being shown/persisted. Injected by
  /// the app assembly (`AppState`) so each vault keeps its **own** persisted
  /// history. While it returns null/empty (locked, or nothing wired) the
  /// records stay in memory only, instead of being written into another
  /// vault's slot.
  String? Function()? historyVaultId;

  /// Replace the in-memory history with [records] loaded from storage.
  void hydrate(List<SignatureRecord> records) {
    _history
      ..clear()
      ..addAll(records);
  }

  /// Clear the in-memory history only; the persisted copy is untouched.
  void clearHistory() {
    _history.clear();
  }

  void _addRecord(SignatureRecord record, String? seedHex) {
    _history.add(record);
    if (_history.length > maxHistoryRecords) {
      _history.removeRange(0, _history.length - maxHistoryRecords);
    }
    final repo = _historyRepo;
    if (repo != null && seedHex != null && seedHex.isNotEmpty) {
      unawaited(_persist(repo, seedHex));
    }
  }

  Future<void> _persist(IHistoryRepository repo, String seedHex) async {
    final vaultId = historyVaultId?.call();
    if (vaultId == null || vaultId.isEmpty) return;
    try {
      await repo.save(List.unmodifiable(_history), vaultId, seedHex);
    } catch (_) {
      // Persistence failure must never break the signing flow.
    }
  }

  /// Cancel the pending timeout and clear in-memory state on disposal.
  /// Persisted history is retained (only the loaded copy is dropped).
  void dispose() {
    _cancelBackstops();
    _pendingRequest = null;
    _pendingAddress = null;
    _lastSignResult = null;
    _history.clear();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Helpers — address derivation
  // ═══════════════════════════════════════════════════════════════════

  /// Derive the signing address for a chain from seed+path.
  String? _deriveAddress(String seedHex, String path, String chain) {
    switch (chain) {
      case 'ethereum':
      case 'personal_msg':
      case 'eip712':
        return _crypto.deriveEthAddress(seedHex, path);
      case 'solana':
        return _crypto.deriveSolAddress(seedHex, path);
      case 'bitcoin':
        return _crypto.deriveBtcAddress(seedHex, path);
      case 'tron':
        return _crypto.deriveTronAddress(seedHex, path);
      case 'sui':
        return _crypto.deriveSuiAddress(seedHex, path);
      default:
        return null;
    }
  }
}
