/// Ledger APDU message format — request / response wire protocol.
///
/// Ported from open-ledger-mono: `packages/apdu/src/constants.ts`
library;

/// CLA byte mapping:
///   0xe0 — OS commands / Solana / Ethereum / Tron / legacy Bitcoin app
///   0xe1 — Bitcoin (current app, protocol 2.1.0+)
///   0xf8 — Bitcoin framework (`F8 01 CONTINUE` only)
///   0x07 — Sui

import 'dart:typed_data';


/// An APDU command sent from the client (BLE central) to the wallet.
class ApduCommand {
  /// Class byte — identifies the command namespace.
  final int cla;

  /// Instruction byte — the specific operation within the class.
  final int ins;

  /// Parameter 1.
  final int p1;

  /// Parameter 2.
  final int p2;

  /// Optional command payload (max 255 bytes for standard APDU).
  final Uint8List? data;

  const ApduCommand({
    required this.cla,
    required this.ins,
    required this.p1,
    required this.p2,
    this.data,
  });

  /// Serialize to raw wire format: [CLA, INS, P1, P2, LC?, ...data]
  ///
  /// LC = data.length; omitted when there is no data payload.
  Uint8List toBytes() {
    final hasData = data != null && data!.isNotEmpty;
    final lc = hasData ? data!.length : 0;
    final headerLen = hasData ? 5 : 4;
    final result = Uint8List(headerLen + lc);

    result[0] = cla;
    result[1] = ins;
    result[2] = p1;
    result[3] = p2;

    if (hasData) {
      result[4] = lc;
      result.setRange(5, 5 + lc, data!);
    }

    return result;
  }

  /// Deserialize from raw bytes received over BLE.
  ///
  /// Throws [ArgumentError] if the header is too short or if the
  /// declared LC does not match the available data length.
  factory ApduCommand.fromBytes(Uint8List bytes) {
    if (bytes.length < 4) {
      throw ArgumentError(
        'APDU command too short: ${bytes.length} bytes (minimum 4)',
      );
    }

    final cla = bytes[0];
    final ins = bytes[1];
    final p1 = bytes[2];
    final p2 = bytes[3];

    final hasData = bytes.length > 4;

    // Case 1: no data, header-only command
    if (!hasData) {
      return ApduCommand(cla: cla, ins: ins, p1: p1, p2: p2);
    }

    final lc = bytes[4];
    final expectedLen = 5 + lc;

    if (bytes.length < expectedLen) {
      throw ArgumentError(
        'APDU command truncated: declared LC=$lc but only '
        '${bytes.length - 5} data bytes available',
      );
    }

    final data =
        lc > 0 ? Uint8List.sublistView(bytes, 5, expectedLen) : Uint8List(0);

    return ApduCommand(
      cla: cla,
      ins: ins,
      p1: p1,
      p2: p2,
      data: data,
    );
  }

  @override
  String toString() =>
      'ApduCommand(CLA=0x${cla.toRadixString(16)}, INS=0x${ins.toRadixString(16)}, '
      'P1=0x${p1.toRadixString(16)}, P2=0x${p2.toRadixString(16)}, '
      'dataLen=${data?.length ?? 0})';
}

/// An APDU response sent from the wallet back to the client.
class ApduResponse {
  /// Response payload (empty list when there is no data).
  final Uint8List? data;

  /// Status word byte 1.
  final int sw1;

  /// Status word byte 2.
  final int sw2;

  const ApduResponse({
    this.data,
    required this.sw1,
    required this.sw2,
  });

  /// `true` when the command completed successfully (SW = 0x9000).
  bool get isSuccess => sw1 == 0x90 && sw2 == 0x00;

  /// Combined 16-bit status word (SW1 << 8 | SW2).
  int get statusWord => (sw1 << 8) | sw2;

  /// Serialize to raw wire format: [data..., SW1, SW2]
  Uint8List toBytes() {
    final d = data;
    final dataLen = d?.length ?? 0;
    final result = Uint8List(dataLen + 2);

    if (d != null && dataLen > 0) {
      result.setRange(0, dataLen, d);
    }
    result[dataLen] = sw1;
    result[dataLen + 1] = sw2;

    return result;
  }

  /// Deserialize from raw bytes.
  ///
  /// The last 2 bytes are SW1/SW2 — everything before them is the
  /// response data (may be empty).
  factory ApduResponse.fromBytes(Uint8List bytes) {
    if (bytes.length < 2) {
      throw ArgumentError(
        'APDU response too short: ${bytes.length} bytes (minimum 2)',
      );
    }

    final sw1 = bytes[bytes.length - 2];
    final sw2 = bytes[bytes.length - 1];

    final dataLen = bytes.length - 2;
    final data = dataLen > 0
        ? Uint8List.sublistView(bytes, 0, dataLen)
        : null;

    return ApduResponse(data: data, sw1: sw1, sw2: sw2);
  }

  @override
  String toString() =>
      'ApduResponse(SW=0x${statusWord.toRadixString(16).padLeft(4, '0')}, '
      'isSuccess=$isSuccess, dataLen=${data?.length ?? 0})';
}

/// A sign request parked by the Rust chain-app host, pending user
/// confirmation.
///
/// Created by [SignConfirmation] when a chain module returns a review. The
/// user must approve or reject on the TransactionScreen; approval asks the
/// host for the signature bytes.
class PendingSignRequest {
  /// Chain identifier: 'ethereum', 'solana', 'bitcoin', 'tron', 'sui',
  /// 'personal_msg', 'eip712'.
  final String chain;

  /// Derivation path string (e.g. "m/44'/60'/0'/0/0").
  final String derivationPath;

  /// Signing address (derived from seed + path before showing UI).
  final String signingAddress;

  /// Hex-encoded remainder payload (after path bytes).
  final String payloadHex;

  /// Parsed transaction data from Rust SDK (JSON-decoded map).
  /// Keys depend on [chain]:
  /// - ethereum: to, value, gas, gasPrice, nonce, data
  /// - personal_msg: message, messageHex
  /// - eip712: domainHash, structHash
  /// - others: hex, size
  final Map<String, dynamic>? parsedData;

  /// When this request was created (for timeout calculation).
  final DateTime createdAt;

  /// Wallet seed used to derive the key for encrypting the resulting
  /// history record. Null when unavailable (record stays in memory only).
  final String? seedHex;

  /// Review id assigned by the Rust chain-app host; approval hands it back
  /// to the host to obtain the signature bytes.
  final int chainReviewId;

  PendingSignRequest({
    required this.chainReviewId,
    required this.chain,
    required this.derivationPath,
    required this.signingAddress,
    required this.payloadHex,
    this.parsedData,
    this.seedHex,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

/// An address-display review parked by the Rust chain-app host, pending user
/// approval.
///
/// Created when a module answers GET_PUBLIC_KEY with P1=0x01 (display and
/// confirm). On a real Ledger that P1 means "show the address on screen and
/// wait for the user to confirm" — the device returns the address only after
/// the user approves, and SW 0x6985 (user rejected) otherwise.
///
/// Unlike [PendingSignRequest] this produces no signature: approval asks the
/// host for the address response it already prepared.
class PendingAddressRequest {
  /// Chain identifier — always 'ethereum' today.
  final String chain;

  /// Derivation path string (e.g. `"m/44'/60'/0'/0/0"`).
  final String derivationPath;

  /// The address to display for confirmation.
  final String address;

  /// When this request was created (for timeout calculation).
  final DateTime createdAt;

  /// Review id assigned by the Rust chain-app host; approval hands it back
  /// to the host to obtain the address response bytes.
  final int chainReviewId;

  PendingAddressRequest({
    this.chain = 'ethereum',
    required this.derivationPath,
    required this.address,
    required this.chainReviewId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}
