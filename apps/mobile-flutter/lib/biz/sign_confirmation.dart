import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/interfaces/crypto_service.dart';
import '../core/interfaces/history_repository.dart';
import '../core/models/apdu_message.dart';
import '../core/models/signature_record.dart';
import '../protocols/apdu/apdu_constants.dart';

/// Owns the confirmation lifecycle for reviews parked by the Rust chain host.
///
/// Extracted from [AppState] to separate business logic from app
/// lifecycle / BLE I/O. Owns the state machine for:
///   1. Holding a parked review for user confirmation
///   2. Backstop that answers the host if the UI never resolves a request
///   3. Result storage after approve/reject/timeout
///
/// The Rust modules parse the payload and produce the digest; Dart only
/// renders the parsed view and parks the request. Approval asks the host for
/// the signature bytes, so no seed is needed on this path.
///
/// Callbacks:
///   [onRequestPending] — triggered when a new review is parked
///                        (caller should navigate to TransactionScreen).
///   [onRequestResolved] — triggered after approve, reject, or timeout
///                         (caller should navigate away from confirmation).
///
/// Usage:
/// ```dart
/// final sc = SignConfirmation(crypto: crypto);
/// sc.onRequestPending = () => router.go('/transaction');
/// sc.onRequestResolved = () => router.go('/');
///
/// // On user approve:
/// await sc.approve(() async {
///   final bytes = host.resolve(reviewId, approved: true);
///   ble.sendApduResponse(bytes);
///   return bytes;
/// });
/// ```
class SignConfirmation {
  /// Used to hex-encode the signature for display / history.
  final ICryptoService _crypto;

  /// Called when a new sign request needs user confirmation.
  /// The caller should navigate to the TransactionScreen.
  void Function()? onRequestPending;

  /// Called after the pending request is resolved (approved/rejected/timed out).
  /// The caller should navigate away from the confirmation screen.
  void Function()? onRequestResolved;

  /// Called when an address-display review needs the user to confirm the
  /// displayed address. The caller should navigate to the address
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
    this.confirmationBackstop = const Duration(seconds: 65),
    this.onRequestPending,
    this.onRequestResolved,
  });

  // ═══════════════════════════════════════════════════════════════════
  //  Interception
  // ═══════════════════════════════════════════════════════════════════

  /// Intercept a signing review produced by the Rust chain-app host.
  ///
  /// The module already parsed the payload and produced the digest; Dart only
  /// renders the parsed view and parks the request. Approval asks the host for
  /// the signature bytes instead of signing locally.
  ///
  /// [seedHex] is **not** used for signing — the host already holds the key.
  /// It only keys the encrypted signature-history record.
  ///
  /// Returns `true` once the request is parked and the UI has been asked to
  /// open the confirmation screen.
  Future<bool> interceptChainReview({
    required int reviewId,
    required String chain,
    required String derivationPath,
    required String signingAddress,
    required String payloadHex,
    Map<String, dynamic>? parsedData,
    String? seedHex,
  }) async {
    await _supersedePending();

    _pendingRequest = PendingSignRequest(
      chain: chain,
      derivationPath: derivationPath,
      signingAddress: signingAddress,
      payloadHex: payloadHex,
      parsedData: parsedData,
      seedHex: seedHex,
      chainReviewId: reviewId,
    );

    // Start the backstop; the confirmation screen resolves first normally.
    _startSignBackstop();

    onRequestPending?.call();
    return true;
  }

  /// Intercept an address-display review.
  ///
  /// The host has already derived and normalised [address]. Stores a
  /// [PendingAddressRequest], triggers [onAddressRequestPending] so the caller
  /// can navigate to the address confirmation screen, and starts the backstop.
  ///
  /// Returns `true` on success. Returns `false` if [address] is empty.
  Future<bool> interceptAddressCommand(
      String address, String derivationPath,
      {required int chainReviewId}) async {
    if (address.isEmpty) return false;

    await _supersedePending();

    _pendingAddress = PendingAddressRequest(
      derivationPath: derivationPath,
      address: address,
      chainReviewId: chainReviewId,
    );

    // Start the backstop; the confirmation screen resolves first normally.
    _startAddressBackstop();

    onAddressRequestPending?.call();
    return true;
  }

  /// The user approved the pending address-display request.
  ///
  /// [respond] performs the BLE response delivery — asking the host for the
  /// final bytes and sending them. Awaited so delivery completes before the
  /// pending request is cleared.
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
  /// [sign] is an async callback that asks the chain host for the final
  /// response and sends it over BLE. It is **awaited** — BLE response
  /// delivery is guaranteed to complete before the pending request is
  /// cleared. This prevents response races.
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
}
