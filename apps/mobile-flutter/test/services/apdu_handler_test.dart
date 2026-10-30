/// Unit tests for [ApduHandler] and APDU protocol constants.
///
/// The handler only owns the OS / app shell: dashboard commands, OPEN_APP /
/// QUIT_APP, and the frame-level probes (GET_VERSION, app configuration,
/// ERC-20 ACK). Every chain INS is served by the Rust modules and must be
/// refused here.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/models/apdu_message.dart';
import 'package:open_ledger_app/core/models/chain.dart';
import 'package:open_ledger_app/protocols/apdu/apdu_constants.dart';
import 'package:open_ledger_app/biz/apdu_handler.dart';

void main() {
  late ApduHandler handler;

  setUp(() {
    handler = ApduHandler()
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

  test('getAppName returns "OpenLedgerApp" for non-OS CLA', () {
    final cmd = ApduCommand(
      cla: Cla.global,
      ins: Ins.getAppName,
      p1: 0,
      p2: 0,
    );

    final response = handler.handle(cmd);

    expect(response.isSuccess, isTrue);
    expect(response.data, isNotNull);
    expect(String.fromCharCodes(response.data!), equals('OpenLedgerApp'));
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

  test('ERC-20 provisioning (INS 0x0A) is acknowledged with 9000', () {
    final response = handler.handle(const ApduCommand(
      cla: Cla.os,
      ins: Ins.ethProvideErc20TokenInfo,
      p1: 0,
      p2: 0,
    ));

    expect(response.isSuccess, isTrue);
    expect(response.data, isNull);
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
    final fresh = ApduHandler();

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
      final handler = ApduHandler();
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
    final fresh = ApduHandler();

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

  test('Solana GET_APP_CONFIGURATION (INS 0x04) returns 5 bytes', () {
    handler.setCurrentApp(LedgerApp.solana);

    final response = handler.handle(const ApduCommand(
      cla: Cla.os,
      ins: Ins.solGetAppConfiguration,
      p1: 0,
      p2: 0,
    ));

    // [allow_blind_sign][pubkey_display][major][minor][patch] + 9000
    expect(response.toBytes(),
        equals(Uint8List.fromList([0x00, 0x01, 0x00, 0x01, 0x00, 0x90, 0x00])));
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

  // ═══════════════════════════════════════════════════════════════════
  // Chain INS codes are owned by the Rust modules
  // ═══════════════════════════════════════════════════════════════════

  test('Ethereum chain INS (0x02/0x04/0x08/0x0C) is refused with 6D00', () {
    for (final ins in [
      Ins.getPublicKey,
      Ins.ethSign,
      Ins.signEthPersonalMessage,
      Ins.ethSignEip712,
    ]) {
      final response = handler.handle(
          ApduCommand(cla: Cla.os, ins: ins, p1: 0, p2: 0));
      expect(response.statusWord, Sw.insNotSupported, reason: 'INS $ins');
    }
  });

  test('Solana chain INS (0x05/0x06/0x07) is refused with 6D00', () {
    handler.setCurrentApp(LedgerApp.solana);
    for (final ins in [
      Ins.solGetAddress,
      Ins.solSignMessage,
      Ins.solSignOffchainMessage,
    ]) {
      final response = handler.handle(
          ApduCommand(cla: Cla.os, ins: ins, p1: 0, p2: 0));
      expect(response.statusWord, Sw.insNotSupported, reason: 'INS $ins');
    }
  });

  test('Tron chain INS is refused with 6D00, never misrouted to Ethereum', () {
    handler.setCurrentApp(LedgerApp.tron);
    // INS 0x04 is ETH_SIGN in the Ethereum table and Tron SIGN here. Both are
    // host-owned, so the local table must answer 6D00 in either case.
    for (final ins in [
      Ins.tronGetPublicKey,
      Ins.tronSignTx,
      Ins.tronSignHash,
      Ins.tronSignPersonalMessage,
    ]) {
      final response = handler.handle(
          ApduCommand(cla: Cla.os, ins: ins, p1: 0, p2: 0));
      expect(response.statusWord, Sw.insNotSupported, reason: 'INS $ins');
    }
  });

  test('Bitcoin / Sui CLAs are refused with 6D00', () {
    for (final cla in [Cla.bitcoin, Cla.bitcoinExt, Cla.sui]) {
      final response = handler.handle(
          ApduCommand(cla: cla, ins: Ins.btcGetWalletPublicKey, p1: 0, p2: 0));
      expect(response.statusWord, Sw.insNotSupported, reason: 'CLA $cla');
    }
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
}
