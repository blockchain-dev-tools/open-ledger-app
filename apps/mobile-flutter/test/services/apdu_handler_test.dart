/// Unit tests for [ApduHandler] and APDU protocol constants.
///
/// Covers routing, error cases, serialization round-trips, and
/// edge cases (empty data, unknown CLA/INS).
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/models/apdu_message.dart';
import 'package:open_ledger_app/core/models/chain.dart';
import 'package:open_ledger_app/protocols/apdu/apdu_constants.dart';
import 'package:open_ledger_app/biz/apdu_handler.dart';

import '../support/fake_crypto_service.dart';

void main() {
  late ApduHandler handler;

  setUp(() {
    handler = ApduHandler(crypto: const FakeCryptoService())
      // Production only serves APDUs once the user opened an app; the
      // dashboard default is asserted separately below.
      ..setCurrentApp(LedgerApp.ethereum);
  });

  // ═══════════════════════════════════════════════════════════════════
  // OS / Common command tests
  // ═══════════════════════════════════════════════════════════════════

  test('getVersion returns success with version bytes', () {
    final cmd = ApduCommand(
      cla: Cla.os,
      ins: Ins.getVersion,
      p1: 0,
      p2: 0,
    );

    final response = handler.handle(cmd);

    expect(response.isSuccess, isTrue);
    expect(response.sw1, 0x90);
    expect(response.sw2, 0x00);
    expect(response.data, isNotNull);
    // GET_VERSION binary layout: target_id(4B) + se_ver_len(1B)
    // + se_ver + flags_len(1B) + flags(4B) + mcu_ver_len(1B) + mcu_ver.
    final data = response.data!;
    final seVerLen = data[4];
    expect(String.fromCharCodes(data.sublist(5, 5 + seVerLen)),
        equals('1.10.3'));
  });

  test('getAppName returns "OpenLedgerAppApp" for non-OS CLA', () {
    final cmd = ApduCommand(
      cla: Cla.global,
      ins: Ins.getAppName,
      p1: 0,
      p2: 0,
    );

    final response = handler.handle(cmd);

    expect(response.isSuccess, isTrue);
    expect(response.data, isNotNull);
    expect(String.fromCharCodes(response.data!), equals('OpenLedgerAppApp'));
  });

  test('GET_APP_CONFIGURATION returns capability flags and Ethereum version', () {
    final cmd = ApduCommand(
      cla: Cla.os,
      ins: Ins.getAppConfiguration,
      p1: 0,
      p2: 0,
    );

    final response = handler.handle(cmd);

    expect(response.isSuccess, isTrue);
    expect(response.statusWord, Sw.success);
    expect(response.data, equals(Uint8List.fromList([0x01, 0x01, 0x0A, 0x03])));
    expect(response.toBytes(), equals(
      Uint8List.fromList([0x01, 0x01, 0x0A, 0x03, 0x90, 0x00]),
    ));
  });

  // ═══════════════════════════════════════════════════════════════════
  // Exposed app (GET_APP_AND_VERSION) tests
  // ═══════════════════════════════════════════════════════════════════

  /// Extract the app name from a GET_APP_AND_VERSION response:
  /// [0x01] [name_len] [name] [ver_len] [ver] [flags_len] [flags].
  String appNameOf(ApduResponse response) {
    final data = response.data!;
    final nameLen = data[1];
    return String.fromCharCodes(data.sublist(2, 2 + nameLen));
  }

  test('GET_APP_AND_VERSION reports the BOLOS dashboard with no app open', () {
    final fresh = ApduHandler(crypto: const FakeCryptoService());

    final response = fresh.handle(const ApduCommand(
      cla: Cla.global,
      ins: Ins.getVersion,
      p1: 0,
      p2: 0,
    ));

    expect(response.isSuccess, isTrue);
    // Dashboard payloads use format 0x00 — what a real device sends, and the
    // signal wallets use to ask the user to open an app.
    expect(response.data!.first, equals(0x00));
    expect(appNameOf(response), equals('BOLOS'));
  });

  test('OPEN_APP switches the reported app for every chain', () {
    for (final app in LedgerApp.values) {
      final handler = ApduHandler(crypto: const FakeCryptoService());
      handler.handle(ApduCommand(
        cla: Cla.os,
        ins: Ins.openApp,
        p1: 0,
        p2: 0,
        data: Uint8List.fromList(app.ledgerName.codeUnits),
      ));

      final response = handler.handle(const ApduCommand(
        cla: Cla.global,
        ins: Ins.getVersion,
        p1: 0,
        p2: 0,
      ));

      expect(response.data!.first, equals(0x01), reason: app.name);
      expect(appNameOf(response), equals(app.ledgerName), reason: app.name);
    }
  });

  test('QUIT_APP returns the device to the dashboard', () {
    final response = handler.handle(const ApduCommand(
      cla: Cla.os,
      ins: Ins.quitApp,
      p1: 0,
      p2: 0,
    ));

    expect(response.isSuccess, isTrue);
    expect(handler.currentApp, isNull);

    final poll = handler.handle(const ApduCommand(
      cla: Cla.global,
      ins: Ins.getVersion,
      p1: 0,
      p2: 0,
    ));
    expect(poll.data!.first, equals(0x00));
    expect(appNameOf(poll), equals('BOLOS'));
  });

  test('CLA 0xE0 app commands are refused while on the dashboard', () {
    final fresh = ApduHandler(crypto: const FakeCryptoService());

    // GET_APP_CONFIGURATION belongs to the Ethereum app's INS table, which
    // is not loaded when nothing is open.
    final response = fresh.handle(const ApduCommand(
      cla: Cla.os,
      ins: Ins.getAppConfiguration,
      p1: 0,
      p2: 0,
    ));

    expect(response.isSuccess, isFalse);
    expect(response.statusWord, Sw.insNotSupported);
  });

  test('setCurrentApp(LedgerApp.solana) makes GET_APP_AND_VERSION report Solana', () {
    handler.setCurrentApp(LedgerApp.solana);

    final response = handler.handle(const ApduCommand(
      cla: Cla.global,
      ins: Ins.getVersion,
      p1: 0,
      p2: 0,
    ));

    expect(response.isSuccess, isTrue);
    expect(appNameOf(response), equals('Solana'));
  });

  test('OPEN_APP "Solana" also switches GET_APP_AND_VERSION to Solana', () {
    final open = handler.handle(ApduCommand(
      cla: Cla.os,
      ins: Ins.openApp,
      p1: 0,
      p2: 0,
      data: Uint8List.fromList('Solana'.codeUnits),
    ));
    expect(open.isSuccess, isTrue);

    final response = handler.handle(const ApduCommand(
      cla: Cla.global,
      ins: Ins.getVersion,
      p1: 0,
      p2: 0,
    ));

    expect(appNameOf(response), equals('Solana'));
  });

  // ── Tron app identity (real Ledger app-tron speaks CLA 0xE0) ────────

  test('setCurrentApp(LedgerApp.tron) makes GET_APP_AND_VERSION report Tron', () {
    handler.setCurrentApp(LedgerApp.tron);

    final response = handler.handle(const ApduCommand(
      cla: Cla.global,
      ins: Ins.getVersion,
      p1: 0,
      p2: 0,
    ));

    expect(response.isSuccess, isTrue);
    expect(appNameOf(response), equals('Tron'));
  });

  test('OPEN_APP "Tron" also switches GET_APP_AND_VERSION to Tron', () {
    final open = handler.handle(ApduCommand(
      cla: Cla.os,
      ins: Ins.openApp,
      p1: 0,
      p2: 0,
      data: Uint8List.fromList('Tron'.codeUnits),
    ));
    expect(open.isSuccess, isTrue);

    final response = handler.handle(const ApduCommand(
      cla: Cla.global,
      ins: Ins.getVersion,
      p1: 0,
      p2: 0,
    ));

    expect(appNameOf(response), equals('Tron'));
  });

  test('CLA 0xE0 INS 0x06 returns the Tron app config when Tron is open', () {
    handler.setCurrentApp(LedgerApp.tron);

    final response = handler.handle(const ApduCommand(
      cla: Cla.os,
      ins: Ins.tronGetAppConfiguration,
      p1: 0,
      p2: 0,
    ));

    // flags(0x01) + version 0.5.0 — NOT the Ethereum app config 0x01 0A 03.
    expect(response.toBytes(),
        equals(Uint8List.fromList([0x01, 0x00, 0x05, 0x00, 0x90, 0x00])));
  });

  test('CLA 0xE0 INS 0x04 is NOT misrouted to ETH_SIGN when Tron is open', () {
    handler.setCurrentApp(LedgerApp.tron);

    final response = handler.handle(const ApduCommand(
      cla: Cla.os,
      ins: Ins.tronSignTx,
      p1: 0,
      p2: 0,
    ));

    expect(response.isSuccess, isFalse);
    expect(response.statusWord, Sw.insNotSupported);
  });

  test('CLA 0xE0 INS 0x02 routes to the Tron table (mandatory path)', () {
    handler.setCurrentApp(LedgerApp.tron);
    handler.setContext(seedHex: '00' * 32);

    final response = handler.handle(const ApduCommand(
      cla: Cla.os,
      ins: Ins.tronGetPublicKey,
      p1: 0,
      p2: 0,
    ));

    // The Tron table requires a derivation path (WRONG_DATA), whereas the
    // Ethereum GET_ADDRESS would default the path and proceed — so this
    // proves the command reached the Tron table.
    expect(response.statusWord, Sw.wrongData);
  });

  // ═══════════════════════════════════════════════════════════════════
  // Error routing tests
  // ═══════════════════════════════════════════════════════════════════

  test('unknown CLA returns CLA_NOT_SUPPORTED (0x6E00)', () {
    final cmd = ApduCommand(
      cla: 0xFF, // intentionally invalid CLA
      ins: 0x01,
      p1: 0,
      p2: 0,
    );

    final response = handler.handle(cmd);

    expect(response.isSuccess, isFalse);
    expect(response.statusWord, Sw.claNotSupported);
    expect(response.sw1, 0x6E);
    expect(response.sw2, 0x00);
  });

  test('unknown INS returns INS_NOT_SUPPORTED (0x6D00)', () {
    final cmd = ApduCommand(
      cla: Cla.os,
      ins: 0xFF, // invalid INS for OS CLA
      p1: 0,
      p2: 0,
    );

    final response = handler.handle(cmd);

    expect(response.isSuccess, isFalse);
    expect(response.statusWord, Sw.insNotSupported);
    expect(response.sw1, 0x6D);
    expect(response.sw2, 0x00);
  });

  // ═══════════════════════════════════════════════════════════════════
  // Empty command (no data) edge case
  // ═══════════════════════════════════════════════════════════════════

  test('empty command (no data) is handled correctly', () {
    final cmd = ApduCommand(
      cla: Cla.os,
      ins: Ins.getVersion,
      p1: 0,
      p2: 0,
      // data is null — no payload
    );

    final response = handler.handle(cmd);

    expect(response.isSuccess, isTrue);
    expect(response.data, isNotNull);
  });

  // ═══════════════════════════════════════════════════════════════════
  // Serialization round-trip tests
  // ═══════════════════════════════════════════════════════════════════

  test('ApduCommand serialization round-trip preserves all fields', () {
    final original = ApduCommand(
      cla: Cla.os,
      ins: Ins.getVersion,
      p1: 0x01,
      p2: 0x02,
      data: null,
    );

    final bytes = original.toBytes();
    final restored = ApduCommand.fromBytes(bytes);

    expect(restored.cla, original.cla);
    expect(restored.ins, original.ins);
    expect(restored.p1, original.p1);
    expect(restored.p2, original.p2);
    expect(restored.data, isNull);
  });

  test('ApduCommand with data serialization round-trip', () {
    final original = ApduCommand(
      cla: Cla.os,
      ins: Ins.getAppConfiguration,
      p1: 0,
      p2: 0,
      data: Uint8List.fromList([0x01, 0x02, 0x03, 0x04]),
    );

    final bytes = original.toBytes();
    final restored = ApduCommand.fromBytes(bytes);

    expect(restored.cla, original.cla);
    expect(restored.ins, original.ins);
    expect(restored.data, isNotNull);
    expect(restored.data!.length, 4);
    expect(restored.data!, equals([0x01, 0x02, 0x03, 0x04]));
  });

  test('ApduResponse serialization round-trip preserves data and status', () {
    final original = ApduResponse(
      data: Uint8List.fromList([0xAA, 0xBB, 0xCC]),
      sw1: 0x90,
      sw2: 0x00,
    );

    final bytes = original.toBytes();
    final restored = ApduResponse.fromBytes(bytes);

    expect(restored.sw1, original.sw1);
    expect(restored.sw2, original.sw2);
    expect(restored.statusWord, Sw.success);
    expect(restored.isSuccess, isTrue);
    expect(restored.data, isNotNull);
    expect(restored.data!, equals([0xAA, 0xBB, 0xCC]));
  });

  test('ApduResponse error round-trip (no data)', () {
    final original = ApduResponse(
      data: null,
      sw1: 0x6E,
      sw2: 0x00,
    );

    final bytes = original.toBytes();
    final restored = ApduResponse.fromBytes(bytes);

    expect(restored.isSuccess, isFalse);
    expect(restored.statusWord, Sw.claNotSupported);
    expect(restored.data, isNull);
  });

  // ═══════════════════════════════════════════════════════════════════
  // Sw.isSuccess helper tests
  // ═══════════════════════════════════════════════════════════════════

  test('Sw.isSuccess correctly identifies success and error codes', () {
    expect(Sw.isSuccess(Sw.success), isTrue);
    expect(Sw.isSuccess(Sw.insNotSupported), isFalse);
    expect(Sw.isSuccess(Sw.claNotSupported), isFalse);
    expect(Sw.isSuccess(Sw.unknownError), isFalse);
    expect(Sw.isSuccess(Sw.conditionsNotSatisfied), isFalse);
    expect(Sw.isSuccess(Sw.wrongDataLength), isFalse);
  });

  // ═══════════════════════════════════════════════════════════════════
  // Chain handler — context-required tests
  // ═══════════════════════════════════════════════════════════════════
  //
  // These INS codes are now implemented but require wallet context
  // (mnemonic + passphrase). Without context, they return
  // SECURITY_STATUS_NOT_SATISFIED.

  test('Bitcoin get-address without context returns SECURITY_STATUS_NOT_SATISFIED', () {
    final cmd = ApduCommand(
      cla: Cla.bitcoin,
      ins: Ins.btcGetWalletPublicKey,
      p1: 0,
      p2: 0,
    );

    final response = handler.handle(cmd);

    expect(response.isSuccess, isFalse);
    expect(response.statusWord, Sw.securityStatusNotSatisfied);
  });

  test('Bitcoin extended sign-tx without context returns SECURITY_STATUS_NOT_SATISFIED', () {
    final cmd = ApduCommand(
      cla: Cla.bitcoinExt,
      ins: Ins.btcSignTx,
      p1: 0,
      p2: 0,
    );

    final response = handler.handle(cmd);

    expect(response.isSuccess, isFalse);
    expect(response.statusWord, Sw.securityStatusNotSatisfied);
  });

  test('Tron get-address without context returns SECURITY_STATUS_NOT_SATISFIED', () {
    final cmd = ApduCommand(
      cla: Cla.tron,
      ins: Ins.tronGetPublicKey,
      p1: 0,
      p2: 0,
    );

    final response = handler.handle(cmd);

    expect(response.isSuccess, isFalse);
    expect(response.statusWord, Sw.securityStatusNotSatisfied);
  });

  test('Sui get-address without context returns SECURITY_STATUS_NOT_SATISFIED', () {
    final cmd = ApduCommand(
      cla: Cla.sui,
      ins: Ins.suiGetPublicKey,
      p1: 0,
      p2: 0,
    );

    final response = handler.handle(cmd);

    expect(response.isSuccess, isFalse);
    expect(response.statusWord, Sw.securityStatusNotSatisfied);
  });

  // ═══════════════════════════════════════════════════════════════════
  // Chain handler — unknown INS tests
  // ═══════════════════════════════════════════════════════════════════

  test('Bitcoin CLA with unknown INS returns INS_NOT_SUPPORTED', () {
    final cmd = ApduCommand(
      cla: Cla.bitcoin,
      ins: 0xFF,
      p1: 0,
      p2: 0,
    );

    final response = handler.handle(cmd);

    expect(response.isSuccess, isFalse);
    expect(response.statusWord, Sw.insNotSupported);
  });

  test('Tron CLA with unknown INS returns INS_NOT_SUPPORTED', () {
    final cmd = ApduCommand(
      cla: Cla.tron,
      ins: 0xFF,
      p1: 0,
      p2: 0,
    );

    final response = handler.handle(cmd);

    expect(response.isSuccess, isFalse);
    expect(response.statusWord, Sw.insNotSupported);
  });

  test('Sui CLA with unknown INS returns INS_NOT_SUPPORTED', () {
    final cmd = ApduCommand(
      cla: Cla.sui,
      ins: 0xFF,
      p1: 0,
      p2: 0,
    );

    final response = handler.handle(cmd);

    expect(response.isSuccess, isFalse);
    expect(response.statusWord, Sw.insNotSupported);
  });

  // ═══════════════════════════════════════════════════════════════════
  // Solana SIGN — OKX num_signers prefix regression
  // ═══════════════════════════════════════════════════════════════════
  //
  // OKX prefixes the first Solana sign frame with a `num_signers` byte.
  // Without stripping it, depth is mis-read as 1 and the first component
  // becomes 0x04800000 → a non-hardened path that SLIP-10 Ed25519 rejects.
  // Regression: the strip must sit on _handleSolSignMessage, not on the
  // ETH personal-message handler.

  test('Solana SIGN strips OKX prefix and derives the hardened path', () {
    final recorder = _RecordingCryptoService();
    final solHandler = ApduHandler(crypto: recorder)
      ..setContext(seedHex: 'ab' * 32)
      ..setCurrentApp(LedgerApp.solana);

    final data = Uint8List.fromList([
      0x01, // OKX num_signers prefix
      0x04, // path depth
      0x80, 0x00, 0x00, 0x2C, // 44'
      0x80, 0x00, 0x01, 0xF5, // 501'
      0x80, 0x00, 0x00, 0x00, // 0'
      0x80, 0x00, 0x00, 0x00, // 0'
      0x01, 0x00, 0x01, // message bytes
    ]);

    final response = solHandler.handle(ApduCommand(
      cla: Cla.os,
      ins: Ins.solSignMessage,
      p1: 0x01,
      p2: 0x00,
      data: data,
    ));

    expect(response.isSuccess, isTrue);
    expect(recorder.derivedPaths, equals(["m/44'/501'/0'/0'"]));
    expect(recorder.signedMessageHexes.single, equals('010001'));
  });

  // ═══════════════════════════════════════════════════════════════════
  // ETH GET_ADDRESS / GET_PUBLIC_KEY — BIP-32 chain code (P2 flag)
  // ═══════════════════════════════════════════════════════════════════
  //
  // The official Ethereum app appends the 32-byte BIP-32 chain code to the
  // GET_PUBLIC_KEY response when P2=0x01 (`cmd_get_public_key.c:37`,
  // `get_public_key.c:54-57`), so the host can rebuild an xpub. P2=0x00
  // (and any other value) omits it.

  group('ETH GET_ADDRESS chain code (P2)', () {
    late ApduHandler chainHandler;

    setUp(() {
      chainHandler = ApduHandler(crypto: _ChainCodeCryptoService())
        ..setCurrentApp(LedgerApp.ethereum)
        ..setContext(seedHex: '00' * 32);
    });

    test('P2=0x00 omits the chain code', () {
      final response = chainHandler.handle(const ApduCommand(
        cla: Cla.os,
        ins: Ins.getPublicKey,
        p1: 0x00,
        p2: P2.ethNoChainCode,
      ));

      expect(response.isSuccess, isTrue);
      final data = response.data!;
      // [0x41][65B pubkey][0x28][40B addr] — no trailing chain code.
      expect(data.length, equals(1 + 65 + 1 + 40));
      expect(data[0], equals(0x41));
      expect(data[66], equals(0x28));
    });

    test('P2=0x01 appends the 32-byte chain code', () {
      final response = chainHandler.handle(const ApduCommand(
        cla: Cla.os,
        ins: Ins.getPublicKey,
        p1: 0x00,
        p2: P2.ethChainCode,
      ));

      expect(response.isSuccess, isTrue);
      final data = response.data!;
      expect(data.length, equals(1 + 65 + 1 + 40 + 32));
      expect(data[0], equals(0x41));
      expect(data[66], equals(0x28));
      // The trailing 32 bytes are exactly the chain code (bytes 32..63 of the
      // extended key returned by the crypto service).
      expect(data.sublist(data.length - 32),
          equals(_ChainCodeCryptoService.chainCode));
    });

    test('the private-key half still drives the address / pubkey', () {
      final response = chainHandler.handle(const ApduCommand(
        cla: Cla.os,
        ins: Ins.getPublicKey,
        p1: 0x00,
        p2: P2.ethNoChainCode,
      ));

      final data = response.data!;
      expect(data.sublist(1, 66), equals(_ChainCodeCryptoService.publicKey));
      expect(String.fromCharCodes(data.sublist(67, 107)),
          equals(_ChainCodeCryptoService.addressHex));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // ETH P1/P2 validation + INS semantics (ADR-002)
  // ═══════════════════════════════════════════════════════════════════
  //
  // The official Ethereum app validates P1/P2 per command and returns
  // SWO_WRONG_P1_P2 (0x6A86) on anything out of range. Valid P1/P2 with a
  // well-formed payload reaches the signing primitive; FakeCryptoService
  // has no key material, so that surfaces as 0x6F00 (UNKNOWN) — which is
  // exactly the signal that the parameter gate and payload parsing passed.

  group('ETH P1/P2 validation & INS semantics', () {
    late ApduHandler eth;

    setUp(() {
      eth = ApduHandler(crypto: const FakeCryptoService())
        ..setCurrentApp(LedgerApp.ethereum)
        ..setContext(seedHex: '00' * 32);
    });

    // ── GET_PUBLIC_KEY (INS 0x02) ──────────────────────────────────
    test('GET_PUBLIC_KEY rejects P1 outside {0x00, 0x01} with 0x6A86', () {
      final response = eth.handle(const ApduCommand(
        cla: Cla.os,
        ins: Ins.getPublicKey,
        p1: 0x02,
        p2: P2.ethNoChainCode,
      ));
      expect(response.statusWord, Sw.incorrectP1P2);
    });

    test('GET_PUBLIC_KEY rejects P2 outside {0x00, 0x01} with 0x6A86', () {
      final response = eth.handle(const ApduCommand(
        cla: Cla.os,
        ins: Ins.getPublicKey,
        p1: P1.ethConfirm,
        p2: 0x02,
      ));
      expect(response.statusWord, Sw.incorrectP1P2);
    });

    test('GET_PUBLIC_KEY with valid P1/P2 passes the gate (crypto error)', () {
      final response = eth.handle(const ApduCommand(
        cla: Cla.os,
        ins: Ins.getPublicKey,
        p1: P1.ethConfirm,
        p2: P2.ethChainCode,
      ));
      // P1=0x01 / P2=0x01 accepted; FakeCryptoService cannot derive a key.
      expect(response.statusWord, Sw.unknownError);
    });

    test('deriveEthAddressForPath returns the address for a valid path', () {
      final h = ApduHandler(crypto: _ChainCodeCryptoService())
        ..setContext(seedHex: '00' * 32);
      expect(h.deriveEthAddressForPath("m/44'/60'/0'/0/0"),
          equals('0x${_ChainCodeCryptoService.addressHex}'));
    });

    test('deriveEthAddressForPath returns null without wallet context', () {
      expect(handler.deriveEthAddressForPath("m/44'/60'/0'/0/0"), isNull);
    });

    // ── ETH_SIGN (INS 0x04) ────────────────────────────────────────
    test('SIGN rejects P1 outside {0x00, 0x80} with 0x6A86', () {
      final response = eth.handle(ApduCommand(
        cla: Cla.os,
        ins: Ins.ethSign,
        p1: 0x01,
        p2: 0x00,
        data: _ethPathData(const [0x80000000], remainder: const [0xAB]),
      ));
      expect(response.statusWord, Sw.incorrectP1P2);
    });

    test('SIGN rejects P2 outside {0x00, 0x01, 0x02} with 0x6A86', () {
      final response = eth.handle(ApduCommand(
        cla: Cla.os,
        ins: Ins.ethSign,
        p1: 0x00,
        p2: 0x03,
        data: _ethPathData(const [0x80000000], remainder: const [0xAB]),
      ));
      expect(response.statusWord, Sw.incorrectP1P2);
    });

    test('SIGN P2=0x02 (start flow, no data) is acked with 9000', () {
      final response = eth.handle(const ApduCommand(
        cla: Cla.os,
        ins: Ins.ethSign,
        p1: 0x00,
        p2: 0x02,
      ));
      expect(response.statusWord, Sw.success);
    });

    test('SIGN P2=0x01 (store only) accepts the block without signing', () {
      final response = eth.handle(ApduCommand(
        cla: Cla.os,
        ins: Ins.ethSign,
        p1: 0x00,
        p2: 0x01,
        data: _ethPathData(const [0x80000000], remainder: const [0xAB, 0xCD]),
      ));
      // FakeCryptoService can't sign; 9000 proves the store-only path
      // returned before reaching the signing primitive.
      expect(response.statusWord, Sw.success);
    });

    test('SIGN P2=0x00 with a valid payload reaches signing (crypto error)', () {
      final response = eth.handle(ApduCommand(
        cla: Cla.os,
        ins: Ins.ethSign,
        p1: 0x00,
        p2: 0x00,
        data: _ethPathData(const [0x80000000], remainder: const [0xAB]),
      ));
      expect(response.statusWord, Sw.unknownError);
    });

    // ── personal_sign (INS 0x08) ───────────────────────────────────
    test('personal_sign rejects P1 outside {0x00, 0x80} with 0x6A86', () {
      final response = eth.handle(ApduCommand(
        cla: Cla.os,
        ins: Ins.signEthPersonalMessage,
        p1: 0x02,
        p2: 0x00,
        data: _ethPathData(const [0x80000000]),
      ));
      expect(response.statusWord, Sw.incorrectP1P2);
    });

    test('personal_sign rejects a non-zero P2 with 0x6A86', () {
      final response = eth.handle(ApduCommand(
        cla: Cla.os,
        ins: Ins.signEthPersonalMessage,
        p1: 0x00,
        p2: 0x01,
        data: _ethPathData(const [0x80000000]),
      ));
      expect(response.statusWord, Sw.incorrectP1P2);
    });

    test('personal_sign rejects a declared length that disagrees with the chunk',
        () {
      // 4B BE length says 5 but only 2 message bytes follow.
      final response = eth.handle(ApduCommand(
        cla: Cla.os,
        ins: Ins.signEthPersonalMessage,
        p1: 0x00,
        p2: 0x00,
        data: _ethPathData(const [0x80000000],
            remainder: const [0x00, 0x00, 0x00, 0x05, 0xAA, 0xBB]),
      ));
      expect(response.statusWord, Sw.wrongData);
    });

    test('personal_sign with a matching 4B prefix reaches signing', () {
      final response = eth.handle(ApduCommand(
        cla: Cla.os,
        ins: Ins.signEthPersonalMessage,
        p1: 0x00,
        p2: 0x00,
        data: _ethPathData(const [0x80000000],
            remainder: const [0x00, 0x00, 0x00, 0x02, 0xAA, 0xBB]),
      ));
      expect(response.statusWord, Sw.unknownError);
    });

    // ── EIP-712 (INS 0x0C) ─────────────────────────────────────────
    test('EIP-712 rejects a non-zero P1 with 0x6A86', () {
      final response = eth.handle(ApduCommand(
        cla: Cla.os,
        ins: Ins.ethSignEip712,
        p1: 0x01,
        p2: 0x00,
        data: _ethPathData(const [0x80000000], remainder: Uint8List(64)),
      ));
      expect(response.statusWord, Sw.incorrectP1P2);
    });

    test('EIP-712 rejects the reserved V1 P2=0x01 with 0x6A86', () {
      final response = eth.handle(ApduCommand(
        cla: Cla.os,
        ins: Ins.ethSignEip712,
        p1: 0x00,
        p2: 0x01,
        data: _ethPathData(const [0x80000000], remainder: Uint8List(64)),
      ));
      expect(response.statusWord, Sw.incorrectP1P2);
    });

    test('EIP-712 V0 rejects a payload shorter than 64 bytes', () {
      final response = eth.handle(ApduCommand(
        cla: Cla.os,
        ins: Ins.ethSignEip712,
        p1: 0x00,
        p2: 0x00,
        data: _ethPathData(const [0x80000000], remainder: Uint8List(32)),
      ));
      expect(response.statusWord, Sw.wrongData);
    });

    test('EIP-712 V0 with a full 64-byte payload reaches signing', () {
      final response = eth.handle(ApduCommand(
        cla: Cla.os,
        ins: Ins.ethSignEip712,
        p1: 0x00,
        p2: 0x00,
        data: _ethPathData(const [0x80000000], remainder: Uint8List(64)),
      ));
      expect(response.statusWord, Sw.unknownError);
    });
  });
}

/// Build APDU data: `[depth(1B)] [4B BE components...] [remainder]`.
Uint8List _ethPathData(List<int> components, {List<int> remainder = const []}) {
  final bytes = Uint8List(1 + components.length * 4 + remainder.length);
  bytes[0] = components.length;
  for (var i = 0; i < components.length; i++) {
    final value = components[i];
    final offset = 1 + i * 4;
    bytes[offset] = (value >> 24) & 0xFF;
    bytes[offset + 1] = (value >> 16) & 0xFF;
    bytes[offset + 2] = (value >> 8) & 0xFF;
    bytes[offset + 3] = value & 0xFF;
  }
  bytes.setRange(1 + components.length * 4, bytes.length, remainder);
  return bytes;
}

/// Records the path / payload handed to the signing primitives so tests can
/// assert what the handler actually parsed.
class _RecordingCryptoService extends FakeCryptoService {
  final List<String> derivedPaths = [];
  final List<String> signedMessageHexes = [];

  @override
  Uint8List? deriveEd25519PrivateKey(String seedHex, String path) {
    derivedPaths.add(path);
    return Uint8List(32);
  }

  @override
  Uint8List? signSolanaMessage(String privkeyHex, String messageHex) {
    signedMessageHexes.add(messageHex);
    return Uint8List(64);
  }
}

/// Deterministic [ICryptoService] for the ETH chain-code tests: returns a
/// fixed 64-byte extended key (privKey ‖ chainCode) plus a fixed pubkey /
/// address, so the P2 suffix can be asserted byte-for-byte without the Rust
/// `.so`.
class _ChainCodeCryptoService extends FakeCryptoService {
  static final Uint8List privateKey =
      Uint8List.fromList(List<int>.generate(32, (i) => i));
  static final Uint8List chainCode =
      Uint8List.fromList(List<int>.generate(32, (i) => 0x80 + i));
  static final Uint8List publicKey =
      Uint8List.fromList(List<int>.generate(65, (i) => i & 0xff));
  static const String addressHex =
      '0123456789abcdef0123456789abcdef01234567';

  @override
  Uint8List? deriveSecp256k1Extended(String seedHex, String path) =>
      Uint8List.fromList([...privateKey, ...chainCode]);

  @override
  String? ethAddressFromPrivateKey(String privkeyHex) => '0x$addressHex';

  @override
  Uint8List? ethPublicKeyBytes(String privkeyHex) =>
      Uint8List.fromList(publicKey);
}
