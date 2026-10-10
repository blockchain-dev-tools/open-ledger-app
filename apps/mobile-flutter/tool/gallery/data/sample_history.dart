import 'package:open_ledger_app/core/models/signature_record.dart';

import 'sample_signing.dart';

/// Fixed signing-history script for the History tab preview (ADR-005).
///
/// Covers all three card states — approved (sw 0x9000), rejected (0x6985),
/// and failed — so every branch of the record card renders. Timestamps are
/// relative to now so the "12m ago / 5h ago / 2d ago" labels stay readable;
/// the list is ordered oldest-first, matching how [AppState.signHistory]
/// accumulates (the screen reverses it for display).
List<SignatureRecord> sampleHistory() {
  final now = DateTime.now();
  return [
    SignatureRecord(
      timestamp: now.subtract(const Duration(days: 2, hours: 3)),
      chain: 'ethereum',
      derivationPath: "m/44'/60'/0'/0/0",
      signingAddress: '0x71C7656EC7ab88b098defB751B7401B5f6d8976F',
      payloadHex: sampleSignRequest.payloadHex,
      parsedData: sampleSignRequest.parsedData,
      isApproved: true,
      signatureHex:
          '3044022079be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798'
          '02200c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5',
      statusWord: 0x9000,
    ),
    SignatureRecord(
      timestamp: now.subtract(const Duration(hours: 5, minutes: 12)),
      chain: 'tron',
      derivationPath: "m/44'/195'/0'/0/0",
      signingAddress: 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8',
      payloadHex: '0a02b2ce22080a02b2ce1200',
      isApproved: false,
      statusWord: 0x6985,
    ),
    SignatureRecord(
      timestamp: now.subtract(const Duration(minutes: 12)),
      chain: 'solana',
      derivationPath: "m/44'/501'/0'/0'",
      signingAddress: '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM',
      payloadHex: '010001035c3d1b2a4f60718293a4b5c6d7e8f90',
      isApproved: true,
      signatureHex:
          '3f8a1c4d9e2b7053f8a1c4d9e2b7053f8a1c4d9e2b7053f8a1c4d9e2b7053f8a1c'
          '4d9e2b7053f8a1c4d9e2b7053f8a1c4d9e2b7053f8a1c4d9e2b7053f8a1c4d9',
      statusWord: 0x9000,
    ),
  ];
}
