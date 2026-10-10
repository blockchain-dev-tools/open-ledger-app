/// Ethereum transaction APDU assembler.
///
/// Assembles chunked Ethereum transaction APDUs (INS 0x04) into a
/// complete RLP payload before producing a result that can be turned
/// into an immutable [SigningIntent].
///
/// Protocol (mirrors open-ledger-mono `packages/apdu/src/handlers/eth.ts`):
/// - **P1=0x00** (first chunk): contains a BIP-32 derivation path
///   followed by the start of the RLP-encoded transaction. Starts
///   or restarts assembly.
/// - **P1=0x80** (continuation): raw RLP bytes, no path. Appended
///   to the accumulated buffer.
///
/// Incomplete chunks receive SW 9000 immediately and never create a
/// confirmation request. When the accumulated bytes reach the
/// expected RLP total length (computed by [rlpTotalLength]), the
/// assembler produces a complete result with the exact payload and
/// resets its state.
///
/// State is cleared on:
/// - Completion (produces result, then resets)
/// - Explicit [reset] call (timeout, disconnect/error, wallet reset)
/// - New first chunk (P1=0x00 always resets before starting)
/// - Malformed first chunk (invalid path data)
///
/// The caller is responsible for:
/// - Parsing the derivation path from the first chunk's data
/// - Deriving the signing address (via [ICryptoService])
/// - Creating the [SigningIntent] from the complete result
/// - Sending SW 9000 / error responses over BLE for incomplete/error results
library;

import 'dart:typed_data';

import 'rlp_parser.dart';

/// Result of feeding an APDU chunk to [EthTxAssembler].
class EthAssemblyResult {
  /// Whether the RLP is fully assembled.
  final bool isComplete;

  /// Error status word (16-bit) when [isError] is true.
  /// `null` when the result is not an error.
  final int? errorSw;

  /// Derivation path string (e.g. `"m/44'/60'/0'/0/0"`).
  /// Only set when [isComplete] is true.
  final String? derivationPath;

  /// Pre-computed seed hex for key derivation.
  /// Only set when [isComplete] is true.
  final String? seedHex;

  /// Complete RLP payload (defensive copy).
  /// Only set when [isComplete] is true.
  final Uint8List? payload;

  const EthAssemblyResult._({
    this.isComplete = false,
    this.errorSw,
    this.derivationPath,
    this.seedHex,
    this.payload,
  });

  /// Incomplete — more chunks are needed.
  /// The caller should send SW 9000 immediately and NOT create a
  /// confirmation request.
  factory EthAssemblyResult.incomplete() =>
      const EthAssemblyResult._(isComplete: false);

  /// Complete — the RLP is fully assembled.
  /// The caller should create a [SigningIntent] from the payload and
  /// show it to the user for confirmation.
  ///
  /// [payload] is defensively copied.
  factory EthAssemblyResult.complete({
    required String derivationPath,
    required String seedHex,
    required Uint8List payload,
  }) =>
      EthAssemblyResult._(
        isComplete: true,
        derivationPath: derivationPath,
        seedHex: seedHex,
        payload: Uint8List.fromList(payload), // defensive copy
      );

  /// Error — malformed data or orphan continuation.
  /// The caller should send [errorSw] as the APDU response.
  factory EthAssemblyResult.error(int sw) =>
      EthAssemblyResult._(errorSw: sw);

  /// Whether this result represents an error.
  bool get isError => errorSw != null;

  /// Whether this result indicates more chunks are needed (not
  /// complete and not an error).
  bool get isIncomplete => !isComplete && !isError;
}

/// Assembles chunked Ethereum transaction APDUs into a complete
/// RLP payload.
///
/// Mutable state — NOT thread-safe. Intended to be owned by a single
/// [BleSession] instance and accessed from the BLE event loop only.
///
/// State mutation is synchronous — no async/await is needed inside
/// the assembler. This ensures APDU state mutation does not block on
/// user approval.
class EthTxAssembler {
  /// Derivation path parsed from the first chunk (P1=0x00).
  String? _derivationPath;

  /// Seed hex captured from the first chunk for key derivation.
  String? _seedHex;

  /// Accumulated RLP bytes (mutable list for efficient append).
  final List<int> _rlpBytes = [];

  /// Expected total RLP length, or -1 if not yet determinable.
  int _expectedLength = -1;

  /// Whether an assembly is in progress (P1=0x00 received, awaiting
  /// more chunks).
  bool get isActive => _derivationPath != null;

  /// Handle a first-chunk APDU (P1=0x00).
  ///
  /// [derivationPath] is the BIP-32 path string parsed from [rlpData]'s
  /// prefix by the caller. [seedHex] is the pre-computed seed for key
  /// derivation. [rlpData] is the RLP-encoded transaction remainder
  /// after the path bytes.
  ///
  /// Always starts a fresh assembly — any previous incomplete state
  /// is discarded (new first chunk = restart).
  ///
  /// Returns:
  /// - [EthAssemblyResult.incomplete] if more chunks are needed
  /// - [EthAssemblyResult.complete] if the RLP is fully contained in
  ///   this first chunk
  EthAssemblyResult handleFirstChunk({
    required String derivationPath,
    required String seedHex,
    required Uint8List rlpData,
  }) {
    // A new first chunk always starts a fresh assembly — discard any
    // previous incomplete state. This handles the "replacement/reset"
    // requirement: a new P1=0x00 supersedes a stalled assembly.
    reset();

    _derivationPath = derivationPath;
    _seedHex = seedHex;
    _rlpBytes.addAll(rlpData);
    _expectedLength = rlpTotalLength(_rlpBytes);

    if (_expectedLength > 0 && _rlpBytes.length >= _expectedLength) {
      // Complete in the first chunk — extract exact payload.
      final txBytes = Uint8List.fromList(
        _rlpBytes.sublist(0, _expectedLength),
      );
      final path = _derivationPath!;
      final seed = _seedHex!;
      reset();
      return EthAssemblyResult.complete(
        derivationPath: path,
        seedHex: seed,
        payload: txBytes,
      );
    }

    return EthAssemblyResult.incomplete();
  }

  /// Handle a continuation chunk (P1=0x80).
  ///
  /// [data] is raw RLP bytes (no path prefix). Appended to the
  /// accumulated buffer. If the accumulated bytes reach the expected
  /// RLP length, produces a complete result and resets.
  ///
  /// Returns:
  /// - [EthAssemblyResult.incomplete] if more chunks are needed
  /// - [EthAssemblyResult.complete] if the RLP is now fully assembled
  /// - [EthAssemblyResult.error] (SW 0x6f00) if no assembly is active
  ///   (orphan continuation — P1=0x80 without a prior P1=0x00)
  EthAssemblyResult handleContinuation(Uint8List data) {
    if (_derivationPath == null) {
      // Orphan continuation — no prior P1=0x00.
      return EthAssemblyResult.error(0x6f00);
    }

    _rlpBytes.addAll(data);
    _expectedLength = rlpTotalLength(_rlpBytes);

    if (_expectedLength > 0 && _rlpBytes.length >= _expectedLength) {
      // Complete — extract exact payload (may be less than accumulated
      // if the host sent extra bytes beyond the RLP boundary).
      final txBytes = Uint8List.fromList(
        _rlpBytes.sublist(0, _expectedLength),
      );
      final path = _derivationPath!;
      final seed = _seedHex!;
      reset();
      return EthAssemblyResult.complete(
        derivationPath: path,
        seedHex: seed,
        payload: txBytes,
      );
    }

    return EthAssemblyResult.incomplete();
  }

  /// Clear all assembly state.
  ///
  /// Called on:
  /// - Completion (internally, after producing a result)
  /// - BLE disconnect / error (via [BleSession._onBleState])
  /// - Wallet lock / context reset (via [BleSession._performLock])
  /// - Timeout (via [BleSession] clearing the assembler)
  /// - New first chunk (internally, at the start of [handleFirstChunk])
  void reset() {
    _derivationPath = null;
    _seedHex = null;
    _rlpBytes.clear();
    _expectedLength = -1;
  }
}
