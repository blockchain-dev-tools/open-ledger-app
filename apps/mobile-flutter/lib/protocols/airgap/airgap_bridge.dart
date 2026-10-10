import 'dart:typed_data';

import '../../../core/models/wallet_accounts.dart';
import 'airgap_protocol.dart';
import '../eip4527/eip4527.dart';

// ═══════════════════════════════════════════════════════════════════════════
// AirGapBridge — integration layer between AirGap protocol and WalletService
//
// Responsibilities:
//   1. Parse QR-scanned AirGap messages into typed results
//   2. Encode signature responses for sending back to companion app
//   3. Convert between AirGap/EIP-4527 data types and WalletService types
// ═══════════════════════════════════════════════════════════════════════════

// ───────────────────────────────────────────────────────────────────────────
// Result types
// ───────────────────────────────────────────────────────────────────────────

/// Result of parsing an AirGap account share message.
class AccountShareResult {
  final String publicKey;
  final String derivationPath;
  final String masterFingerprint;
  final bool isExtendedPublicKey;

  const AccountShareResult({
    required this.publicKey,
    required this.derivationPath,
    required this.masterFingerprint,
    this.isExtendedPublicKey = false,
  });

  /// Convert to [ChainAccount].
  ChainAccount toChainAccount({required String chain, required String address}) {
    return ChainAccount(
      chain: chain,
      address: address,
      derivationPath: derivationPath,
      publicKey: publicKey,
    );
  }

  @override
  String toString() =>
      'AccountShareResult(path: $derivationPath, fp: $masterFingerprint)';
}

/// Result of parsing an AirGap transaction sign request.
class SignRequestResult {
  /// Hex-encoded transaction payload.
  final String transaction;

  final String publicKey;
  final String derivationPath;
  final String masterFingerprint;

  const SignRequestResult({
    required this.transaction,
    required this.publicKey,
    required this.derivationPath,
    required this.masterFingerprint,
  });

  @override
  String toString() =>
      'SignRequestResult(path: $derivationPath, fp: $masterFingerprint)';
}

// ═══════════════════════════════════════════════════════════════════════════
// AirGapBridge
// ═══════════════════════════════════════════════════════════════════════════

/// Bridge between AirGap protocol and WalletService.
///
/// Handles parsing QR-scanned data and encoding response messages.
class AirGapBridge {
  AirGapBridge._();

  // ── AirGap Protocol Parsing ────────────────────────────────────────

  /// Parse an AirGap-encoded [AccountShare] from a QR scan.
  ///
  /// Returns `null` if the QR data does not match the expected format.
  static AccountShareResult? parseAccountShare(String qrData) {
    try {
      final payload = AirGapProtocol.decode(qrData);
      final type = payload['type'] as String?;
      if (type != AirGapMessageType.accountShare.value) return null;

      final data = payload['data'];
      if (data is! Map) return null;

      return AccountShareResult(
        publicKey: data['publicKey'] as String? ?? '',
        derivationPath: data['derivationPath'] as String? ?? '',
        masterFingerprint: data['masterFingerprint'] as String? ?? '',
        isExtendedPublicKey:
            data['isExtendedPublicKey'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  /// Parse an AirGap-encoded [TransactionSignRequest] from a QR scan.
  ///
  /// Returns `null` if the QR data does not match the expected format.
  static SignRequestResult? parseSignRequest(String qrData) {
    try {
      final payload = AirGapProtocol.decode(qrData);
      final type = payload['type'] as String?;
      // Check both transaction and message sign requests
      final isTx = type == AirGapMessageType.transactionSignRequest.value;
      final isMsg = type == AirGapMessageType.messageSignRequest.value;
      if (!isTx && !isMsg) return null;

      final data = payload['data'];
      if (data is! Map) return null;

      return SignRequestResult(
        transaction: data['transaction'] as String? ?? '',
        publicKey: data['publicKey'] as String? ?? '',
        derivationPath: data['derivationPath'] as String? ?? '',
        masterFingerprint: data['masterFingerprint'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// Encode a signature response for AirGap.
  ///
  /// Returns a base58check-encoded AirGap message that can be shown
  /// as a QR code for the companion app to scan.
  static String encodeSignResponse(
    String signatureHex,
    String requestId, {
    AirGapMessageType messageType =
        AirGapMessageType.transactionSignResponse,
  }) {
    final payload = <String, dynamic>{
      'type': messageType.value,
      'data': {
        'signature': signatureHex,
        'requestId': requestId,
      },
    };
    return AirGapProtocol.encode(payload);
  }

  /// Encode an account share message for AirGap.
  ///
  /// Use this to share wallet accounts to a companion app via QR code.
  static String encodeAccountShare({
    required String publicKey,
    required String derivationPath,
    required String masterFingerprint,
    bool isExtendedPublicKey = false,
  }) {
    final payload = <String, dynamic>{
      'type': AirGapMessageType.accountShare.value,
      'data': {
        'publicKey': publicKey,
        'derivationPath': derivationPath,
        'masterFingerprint': masterFingerprint,
        'isExtendedPublicKey': isExtendedPublicKey,
      },
    };
    return AirGapProtocol.encode(payload);
  }

  // ── EIP-4527 Parsing ───────────────────────────────────────────────

  /// Try to parse QR data as an EIP-4527 UR string.
  ///
  /// Returns the parsed request if the data starts with `ur:` and
  /// matches a known sign request type.
  static SignRequestResult? parseEIP4527SignRequest(String qrData) {
    try {
      if (!qrData.startsWith('ur:')) return null;

      final ur = qrData;

      // Try ETH sign request
      try {
        final ethReq = UREncoder.decodeEthSignRequest(ur);
        return SignRequestResult(
          transaction: Hex.encode(ethReq.signData),
          publicKey: ethReq.origin?.keyData ?? '',
          derivationPath: ethReq.derivationPath,
          masterFingerprint: ethReq.requestIdHex,
        );
      } catch (_) {
        // Not an ETH request, try SOL
      }

      // Try SOL sign request
      try {
        final solReq = UREncoder.decodeSolSignRequest(ur);
        return SignRequestResult(
          transaction: Hex.encode(solReq.signData),
          publicKey: solReq.origin?.keyData ?? '',
          derivationPath: solReq.derivationPath,
          masterFingerprint: solReq.requestIdHex,
        );
      } catch (_) {
        // Not a SOL request either
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  /// Try to parse QR data as either AirGap or EIP-4527.
  ///
  /// Returns the first successful parse result.
  static SignRequestResult? parseAnySignRequest(String qrData) {
    // Try AirGap first
    final airgap = parseSignRequest(qrData);
    if (airgap != null) return airgap;

    // Try EIP-4527
    return parseEIP4527SignRequest(qrData);
  }

  /// Encode an ETH signature as an EIP-4527 UR string.
  static String encodeEIP4527EthSignature(
    Uint8List signature65Bytes,
    List<int> requestId,
  ) {
    final sig = EthSignature(
      requestId: requestId,
      signature: signature65Bytes,
    );
    return UREncoder.encodeEthSignature(sig);
  }

  /// Encode a SOL signature as an EIP-4527 UR string.
  static String encodeEIP4527SolSignature(
    Uint8List signature64Bytes,
    List<int> requestId,
  ) {
    final sig = SolSignature(
      requestId: requestId,
      signature: signature64Bytes,
    );
    return UREncoder.encodeSolSignature(sig);
  }

  // ── Account sharing via EIP-4527 ───────────────────────────────────

  /// Encode a [ChainAccount] as a CryptoHDKey UR string.
  static String encodeAccountAsHDKey(ChainAccount account) {
    final keypath = CryptoKeypath.fromPath(account.derivationPath);
    final hdKey = CryptoHDKey(
      isMaster: false,
      keyData: account.publicKey,
      origin: keypath,
    );
    return UREncoder.encodeHDKey(hdKey);
  }

  /// Encode a list of [ChainAccount]s as a CryptoAccount UR string.
  static String encodeAccountsAsCryptoAccount(
    String masterFingerprintHex,
    List<ChainAccount> accounts,
  ) {
    final fpBytes = Hex.decode(masterFingerprintHex);
    if (fpBytes.length < 4) {
      throw ArgumentError(
          'Master fingerprint must be at least 4 bytes (8 hex chars)');
    }

    final descriptors = accounts.map((account) {
      return CryptoHDKey(
        isMaster: false,
        keyData: account.publicKey,
        origin: CryptoKeypath.fromPath(account.derivationPath),
      );
    }).toList();

    final cryptoAccount = CryptoAccount(
      masterFingerprint: fpBytes.sublist(0, 4),
      outputDescriptors: descriptors,
    );

    return UREncoder.encodeAccount(cryptoAccount);
  }
}
