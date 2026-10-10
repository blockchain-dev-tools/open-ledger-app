/// Real-crypto conformance runner — the counterpart to
/// [conformance_test.dart].
///
/// `conformance_test.dart` executes `needsCrypto: false` vectors against
/// [FakeCryptoService] (fast, no Rust). This runner executes the
/// `needsCrypto: true` vectors against the **real Rust FFI**
/// ([CryptoServiceAdapter]) and, because a real seed is available, also
/// asserts the ADR-002 fixes that cannot be reproduced with fake key
/// material (P1/P2 validation, chain-code layout, personal_sign length
/// prefix, EIP-712 V0 signatures).
///
/// The whole file self-skips when the cdylib cannot be loaded, so a plain
/// `flutter test` stays green (these appear as `skipped`, never `failed`).
/// To actually run it, build the host cdylib and point the loader at it:
/// ```
/// cargo build --manifest-path crates/Cargo.toml --release
/// LD_LIBRARY_PATH=$PWD/crates/target/release \
///   flutter test test/protocols/apdu/real_crypto_conformance_test.dart
/// ```
/// On a device the `.so` is bundled as a jniLib, so the same file runs
/// unchanged under `flutter test integration_test/` if moved there.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/biz/apdu_handler.dart';
import 'package:open_ledger_app/core/models/apdu_message.dart';
import 'package:open_ledger_app/core/models/chain.dart';
import 'package:open_ledger_app/protocols/apdu/apdu_constants.dart';
import 'package:open_ledger_app/infrastructure/ffi/crypto_service_adapter.dart';

/// Fixed 64-byte seed (the one the corpus snapshots were taken with).
const String _seedHex =
    '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f'
    '202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f';

/// Standard Ethereum derivation path (m/44'/60'/0'/0/0).
const List<int> _ethPathComponents = [
  0x8000002C, // 44'
  0x8000003C, // 60'
  0x80000000, // 0'
  0x00000000, // 0
  0x00000000, // 0
];

void main() {
  const crypto = CryptoServiceAdapter();
  final skipReason = _ffiUnavailableReason(crypto);

  if (skipReason != null) {
    // ignore: avoid_print
    print('[real-crypto] skipped: $skipReason');
  }

  // ═══════════════════════════════════════════════════════════════════
  // Corpus: needsCrypto vectors, byte-for-byte against the real FFI
  // ═══════════════════════════════════════════════════════════════════

  group('APDU conformance · needsCrypto vectors (real Rust FFI)', () {
    final specDir = _findSpecDir();
    final vectors = _loadAllVectors(Directory('${specDir.path}/vectors'))
        .where((v) => v['needsCrypto'] == true)
        .toList();

    test('corpus is non-empty (vectors are actually being exercised)', () {
      expect(vectors, isNotEmpty,
          reason: 'expected ≥1 needsCrypto vector under spec/apdu/vectors');
    }, skip: skipReason);

    for (final v in vectors) {
      test(v['id'] as String, () {
        final handler = ApduHandler(crypto: crypto);
        final app = v['currentApp'] as String?;
        if (app != null) handler.setCurrentApp(LedgerApp.values.byName(app));
        handler.setContext(seedHex: v['seedHex'] as String);

        final response = handler.handle(ApduCommand(
          cla: v['cla'] as int,
          ins: v['ins'] as int,
          p1: v['p1'] as int,
          p2: v['p2'] as int,
          data: _bytesOrNull(v['data'] as String?),
        ));

        expect(
          _hex(response.toBytes()),
          (v['response'] as String).toLowerCase(),
          reason: '${v['id']} [${v['provenance']}] ${v['note'] ?? ''}',
        );
      }, skip: skipReason);
    }
  });

  // ═══════════════════════════════════════════════════════════════════
  // ADR-002 fixes — real key material
  // ═══════════════════════════════════════════════════════════════════

  group('ADR-002 fixes · real crypto', () {
    late ApduHandler handler;

    setUp(() {
      handler = ApduHandler(crypto: crypto)
        ..setCurrentApp(LedgerApp.ethereum)
        ..setContext(seedHex: _seedHex);
    });

    ApduCommand cmd(int ins, {int p1 = 0, int p2 = 0, Uint8List? data}) =>
        ApduCommand(cla: Cla.os, ins: ins, p1: p1, p2: p2, data: data);

    // ── Address derivation consistency ─────────────────────────────
    test('address from seed+path equals address from derived private key', () {
      final fromSeed = crypto.deriveEthAddress(_seedHex, "m/44'/60'/0'/0/0");
      final priv = crypto.deriveSecp256k1PrivateKey(_seedHex, "m/44'/60'/0'/0/0");
      expect(priv, isNotNull);
      final fromPriv = crypto.ethAddressFromPrivateKey(crypto.hexEncode(priv!));

      expect(fromSeed, isNotNull);
      expect(fromSeed!.toLowerCase(), equals(fromPriv!.toLowerCase()));
    }, skip: skipReason);

    test('deriveEthAddressForPath matches the GET_PUBLIC_KEY response address',
        () {
      final viaHelper = handler.deriveEthAddressForPath("m/44'/60'/0'/0/0");
      final response = handler.handle(cmd(Ins.getPublicKey));
      expect(response.isSuccess, isTrue);

      final data = response.data!;
      final addrLen = data[66];
      final addrFromResponse =
          String.fromCharCodes(data.sublist(67, 67 + addrLen));

      expect(viaHelper, isNotNull);
      expect(viaHelper!.replaceFirst('0x', '').toLowerCase(),
          equals(addrFromResponse.toLowerCase()));
    }, skip: skipReason);

    // ── GET_PUBLIC_KEY P1/P2 (fix g3) ──────────────────────────────
    test('GET_PUBLIC_KEY rejects P1=0x02 with 0x6A86 (real context)', () {
      expect(handler.handle(cmd(Ins.getPublicKey, p1: 0x02)).statusWord,
          Sw.incorrectP1P2);
    }, skip: skipReason);

    test('GET_PUBLIC_KEY rejects P2=0x02 with 0x6A86 (real context)', () {
      expect(handler.handle(cmd(Ins.getPublicKey, p2: 0x02)).statusWord,
          Sw.incorrectP1P2);
    }, skip: skipReason);

    test('GET_PUBLIC_KEY P2=0x01 appends exactly 32 bytes of chain code', () {
      final resp = handler.handle(cmd(Ins.getPublicKey, p2: P2.ethChainCode));
      final data = resp.data!;
      // [0x41][65B pubkey][0x28][40B addr][32B chain code] (SW is not in data).
      expect(data.length, equals(1 + 65 + 1 + 40 + 32));
      expect(data[0], equals(0x41));
      expect(data[66], equals(0x28));
    }, skip: skipReason);

    // ── SIGN P2 flow control (fix g4) ──────────────────────────────
    test('SIGN P2=0x02 (start flow, no data) is acked with 9000', () {
      expect(handler.handle(cmd(Ins.ethSign, p2: 0x02)).statusWord,
          Sw.success);
    }, skip: skipReason);

    test('SIGN P2=0x01 (store only) acks a complete tx without a signature',
        () {
      final response = handler.handle(cmd(
        Ins.ethSign,
        p2: 0x01,
        data: _pathData(_ethPathComponents, remainder: const [0xc1, 0x01]),
      ));
      expect(response.statusWord, Sw.success);
      expect(response.data, isNull);
    }, skip: skipReason);

    test('SIGN rejects P1=0x01 / P2=0x03 with 0x6A86 (real context)', () {
      expect(
          handler
              .handle(cmd(Ins.ethSign,
                  p1: 0x01,
                  data: _pathData(_ethPathComponents,
                      remainder: const [0xc1, 0x01])))
              .statusWord,
          Sw.incorrectP1P2);
      expect(
          handler
              .handle(cmd(Ins.ethSign,
                  p2: 0x03,
                  data: _pathData(_ethPathComponents,
                      remainder: const [0xc1, 0x01])))
              .statusWord,
          Sw.incorrectP1P2);
    }, skip: skipReason);

    // ── personal_sign length prefix (fix g5) ───────────────────────
    test('personal_sign signs the message behind the 4B BE length prefix', () {
      const message = [0xde, 0xad, 0xbe, 0xef];
      final response = handler.handle(cmd(
        Ins.signEthPersonalMessage,
        data: _pathData(_ethPathComponents,
            remainder: const [0x00, 0x00, 0x00, 0x04, ...message]),
      ));

      expect(response.isSuccess, isTrue);
      // secp256k1 signature = r(32) || s(32) || v(1).
      expect(response.data, isNotNull);
      expect(response.data!.length, equals(65));
    }, skip: skipReason);

    test('personal_sign is deterministic for identical input', () {
      final data = _pathData(_ethPathComponents,
          remainder: const [0x00, 0x00, 0x00, 0x04, 0xde, 0xad, 0xbe, 0xef]);
      final a = handler.handle(cmd(Ins.signEthPersonalMessage, data: data));
      final b = handler.handle(cmd(Ins.signEthPersonalMessage, data: data));
      expect(_hex(a.data!), equals(_hex(b.data!)));
    }, skip: skipReason);

    test('personal_sign rejects a lying length prefix with 0x6A80', () {
      final response = handler.handle(cmd(
        Ins.signEthPersonalMessage,
        // Declares 5 bytes but only 2 follow.
        data: _pathData(_ethPathComponents,
            remainder: const [0x00, 0x00, 0x00, 0x05, 0xaa, 0xbb]),
      ));
      expect(response.statusWord, Sw.wrongData);
    }, skip: skipReason);

    // ── EIP-712 V0 single-step (fix g7) ────────────────────────────
    test('EIP-712 V0 (P2=0x00) signs domain+struct hashes', () {
      final response = handler.handle(cmd(
        Ins.ethSignEip712,
        data: _pathData(_ethPathComponents, remainder: Uint8List(64)),
      ));
      expect(response.isSuccess, isTrue);
      expect(response.data!.length, equals(65));
    }, skip: skipReason);

    test('EIP-712 rejects the reserved V1 P2=0x01 with 0x6A86', () {
      final response = handler.handle(cmd(
        Ins.ethSignEip712,
        p2: 0x01,
        data: _pathData(_ethPathComponents, remainder: Uint8List(64)),
      ));
      expect(response.statusWord, Sw.incorrectP1P2);
    }, skip: skipReason);

    test('EIP-712 rejects a payload shorter than 64 bytes with 0x6A80', () {
      final response = handler.handle(cmd(
        Ins.ethSignEip712,
        data: _pathData(_ethPathComponents, remainder: Uint8List(32)),
      ));
      expect(response.statusWord, Sw.wrongData);
    }, skip: skipReason);
  });
}

// ── FFI availability ────────────────────────────────────────────────────

/// Returns `null` when the real Rust cdylib is loadable, otherwise a skip
/// message. A missing `.so` makes `_loadLibrary()` throw on first use, which
/// is exactly the "not available in this environment" signal.
String? _ffiUnavailableReason(CryptoServiceAdapter crypto) {
  try {
    final addr = crypto.deriveEthAddress(_seedHex, "m/44'/60'/0'/0/0");
    if (addr == null) {
      return 'real Rust FFI returned null (cdylib missing or stub build?)';
    }
    return null;
  } catch (e) {
    return 'real Rust FFI not loadable — build the host cdylib and set '
        'LD_LIBRARY_PATH (cargo build --manifest-path crates/Cargo.toml '
        '--release; LD_LIBRARY_PATH=crates/target/release). Cause: $e';
  }
}

// ── Vector → handler helpers ────────────────────────────────────────────

/// Build APDU data: `[depth(1B)] [4B BE components...] [remainder]`.
Uint8List _pathData(List<int> components, {List<int> remainder = const []}) {
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

/// Walk up from the test's working directory to the repo-root `spec/apdu/`.
Directory _findSpecDir() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    final candidate = Directory('${dir.path}/spec/apdu');
    if (candidate.existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError('spec/apdu not found above ${Directory.current.path}');
}

List<Map<String, dynamic>> _loadAllVectors(Directory dir) {
  final vectors = <Map<String, dynamic>>[];
  for (final entity in dir.listSync()) {
    if (entity is File && entity.path.endsWith('.json')) {
      final json =
          jsonDecode(entity.readAsStringSync()) as Map<String, dynamic>;
      vectors.addAll((json['vectors'] as List).cast<Map<String, dynamic>>());
    }
  }
  return vectors;
}

Uint8List? _bytesOrNull(String? hex) => hex == null ? null : _fromHex(hex);

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _fromHex(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
