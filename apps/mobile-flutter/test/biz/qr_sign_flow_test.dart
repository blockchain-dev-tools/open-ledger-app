/// Unit tests for [QrSignFlow].
///
/// Covers the scanning state machine (progress, duplicates, non-UR noise),
/// the review hand-off, approve → signature frames, address mismatch,
/// timeout, unavailable codec, parser/signer failures and teardown.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/biz/qr_sign_flow.dart';
import 'package:open_ledger_app/core/interfaces/ur_codec.dart';
import 'package:open_ledger_app/core/models/ur_qr.dart';

// ═══════════════════════════════════════════════════════════════════════
// Fakes
// ═══════════════════════════════════════════════════════════════════════

class _FakeSession implements IUrSession {
  _FakeSession(this.frames, {required this.resultType});

  final List<String> frames;
  final String resultType;
  final Set<String> _seen = <String>{};
  bool disposed = false;

  bool get complete => _seen.length == frames.length;

  @override
  UrReceiveProgress receive(String part) {
    if (_seen.contains(part)) {
      return UrReceiveProgress(
        status: UrPartStatus.duplicate,
        received: _seen.length,
        total: frames.length,
      );
    }
    _seen.add(part);
    return UrReceiveProgress(
      status: complete ? UrPartStatus.complete : UrPartStatus.pending,
      received: _seen.length,
      total: frames.length,
    );
  }

  @override
  UrSessionResult? result() => complete
      ? UrSessionResult(
          type: resultType,
          cbor: Uint8List.fromList(const [0xA1, 0x01, 0x02]),
        )
      : null;

  @override
  void dispose() => disposed = true;
}

class _FakeCodec implements IUrCodec {
  _FakeCodec({
    this.available = true,
    this.frames = const ['ur:eth-sign-request/1-2/a', 'ur:eth-sign-request/2-2/b'],
    this.resultType = 'eth-sign-request',
    this.addressMatches = true,
    this.parseThrows = false,
    this.signThrows = false,
    this.signatureFrames = const ['ur:eth-signature/1-1/sig'],
  });

  bool available;
  List<String> frames;
  String resultType;
  bool addressMatches;
  bool parseThrows;
  bool signThrows;
  List<String> signatureFrames;

  _FakeSession? lastSession;
  int newSessionCalls = 0;
  int signCalls = 0;

  @override
  bool get isAvailable => available;

  @override
  IUrSession newSession() {
    newSessionCalls++;
    return lastSession = _FakeSession(frames, resultType: resultType);
  }

  @override
  EthSignRequestView parseSignRequest(Uint8List cbor) {
    if (parseThrows) throw const UrCodecException('bad dCBOR');
    return const EthSignRequestView(
      requestIdHex: '00112233445566778899aabbccddeeff',
      dataType: 1,
      chainId: 1,
      path: "m/44'/60'/0'/0/0",
      address: '0x9858EfFD232B4033E47d90003D41EC34ECAEDa94',
      origin: 'metamask',
      signDataHex: 'deadbeef',
      signingHashHex: 'aabbcc',
    );
  }

  @override
  EthSignResult signRequest(Uint8List cbor, String seedHex) {
    signCalls++;
    if (signThrows) throw const UrCodecException('derive failed');
    return EthSignResult(
      requestIdHex: '00112233445566778899aabbccddeeff',
      signature: Uint8List.fromList(List<int>.filled(65, 1)),
      address: '0x9858EfFD232B4033E47d90003D41EC34ECAEDa94',
      addressMatches: addressMatches,
    );
  }

  @override
  List<String> encodeSignature({
    required String requestIdHex,
    required Uint8List signature,
    String? origin,
    int fragmentLength = 0,
  }) => signatureFrames;

  @override
  CryptoAccountExport encodeAccount({
    required String seedHex,
    required String path,
    int count = 1,
    bool accountLevel = false,
    int fragmentLength = 0,
  }) => CryptoAccountExport(
    frames: const ['ur:crypto-account/1-1/a'],
    address: '0x9858EfFD232B4033E47d90003D41EC34ECAEDa94',
    addresses: const ['0x9858EfFD232B4033E47d90003D41EC34ECAEDa94'],
    path: "m/44'/60'/0'/0/0",
  );
}

const _seed = '5eb00bbd';

QrSignFlow _flow(_FakeCodec codec, {Duration? timeout}) => QrSignFlow(
  codec: codec,
  seedHex: _seed,
  timeout: timeout ?? const Duration(seconds: 60),
);

/// Feed every frame of [codec] in order; returns after the flow reaches review.
void _scanToReview(QrSignFlow flow, _FakeCodec codec) {
  for (final frame in codec.frames) {
    flow.submitFrame(frame);
  }
}

// ═══════════════════════════════════════════════════════════════════════

void main() {
  group('QrSignFlow scanning', () {
    test('start opens a session and enters scanning', () {
      final codec = _FakeCodec();
      final flow = _flow(codec);
      flow.start();

      expect(flow.phase, QrSignPhase.scanning);
      expect(codec.newSessionCalls, 1);
      flow.dispose();
    });

    test('non-UR scan results are ignored', () {
      final flow = _flow(_FakeCodec());
      flow.start();
      flow.submitFrame('https://example.com');
      flow.submitFrame('  ');

      expect(flow.phase, QrSignPhase.scanning);
      expect(flow.progress, isNull);
      flow.dispose();
    });

    test('partial frames report progress, completion enters review', () {
      final flow = _flow(_FakeCodec());
      flow.start();

      flow.submitFrame('ur:eth-sign-request/1-2/a');
      expect(flow.phase, QrSignPhase.scanning);
      expect(flow.progress?.received, 1);
      expect(flow.progress?.total, 2);

      flow.submitFrame('ur:eth-sign-request/2-2/b');
      expect(flow.phase, QrSignPhase.review);
      expect(flow.request?.chainId, 1);
      expect(flow.request?.origin, 'metamask');
      flow.dispose();
    });

    test('duplicate frames do not advance progress', () {
      final flow = _flow(_FakeCodec());
      flow.start();

      flow.submitFrame('ur:eth-sign-request/1-2/a');
      flow.submitFrame('ur:eth-sign-request/1-2/a');

      expect(flow.phase, QrSignPhase.scanning);
      expect(flow.progress?.status, UrPartStatus.duplicate);
      expect(flow.progress?.received, 1);
      flow.dispose();
    });

    test('a completed non-sign-request UR fails as unexpectedQr', () {
      final codec = _FakeCodec(
        frames: const ['ur:crypto-account/1-1/a'],
        resultType: 'crypto-account',
      );
      final flow = _flow(codec);
      flow.start();
      flow.submitFrame('ur:crypto-account/1-1/a');

      expect(flow.phase, QrSignPhase.failed);
      expect(flow.failure, QrSignFailure.unexpectedQr);
      expect(codec.lastSession?.disposed, isTrue);
      flow.dispose();
    });

    test('unparsable request fails as invalidRequest', () {
      final codec = _FakeCodec(
        frames: const ['ur:eth-sign-request/1-1/a'],
        parseThrows: true,
      );
      final flow = _flow(codec);
      flow.start();
      flow.submitFrame('ur:eth-sign-request/1-1/a');

      expect(flow.phase, QrSignPhase.failed);
      expect(flow.failure, QrSignFailure.invalidRequest);
      expect(flow.errorDetail, 'bad dCBOR');
      flow.dispose();
    });

    test('unavailable codec fails without opening a session', () {
      final codec = _FakeCodec(available: false);
      final flow = _flow(codec);
      flow.start();

      expect(flow.phase, QrSignPhase.failed);
      expect(flow.failure, QrSignFailure.codecUnavailable);
      expect(codec.newSessionCalls, 0);
      flow.dispose();
    });

    test('timeout tears the session down', () async {
      final codec = _FakeCodec();
      final flow = _flow(codec, timeout: Duration.zero);
      flow.start();
      final session = codec.lastSession;

      await Future<void>.delayed(Duration.zero);

      expect(flow.phase, QrSignPhase.failed);
      expect(flow.failure, QrSignFailure.timeout);
      expect(session?.disposed, isTrue);
      flow.dispose();
    });
  });

  group('QrSignFlow review', () {
    test('approve signs and exposes signature frames', () {
      final codec = _FakeCodec();
      final flow = _flow(codec);
      flow.start();
      _scanToReview(flow, codec);

      flow.approve();

      expect(flow.phase, QrSignPhase.signature);
      expect(codec.signCalls, 1);
      expect(flow.signatureFrames, ['ur:eth-signature/1-1/sig']);
      flow.dispose();
    });

    test('address mismatch fails instead of producing frames', () {
      final codec = _FakeCodec(addressMatches: false);
      final flow = _flow(codec);
      flow.start();
      _scanToReview(flow, codec);

      flow.approve();

      expect(flow.phase, QrSignPhase.failed);
      expect(flow.failure, QrSignFailure.signingFailed);
      expect(flow.signatureFrames, isEmpty);
      flow.dispose();
    });

    test('empty signature frames fail as signingFailed', () {
      final codec = _FakeCodec(signatureFrames: const []);
      final flow = _flow(codec);
      flow.start();
      _scanToReview(flow, codec);

      flow.approve();

      expect(flow.phase, QrSignPhase.failed);
      expect(flow.failure, QrSignFailure.signingFailed);
      flow.dispose();
    });

    test('signer exceptions fail as signingFailed', () {
      final codec = _FakeCodec(signThrows: true);
      final flow = _flow(codec);
      flow.start();
      _scanToReview(flow, codec);

      flow.approve();

      expect(flow.phase, QrSignPhase.failed);
      expect(flow.failure, QrSignFailure.signingFailed);
      expect(flow.errorDetail, 'derive failed');
      flow.dispose();
    });

    test('reject returns to idle and drops the session', () {
      final codec = _FakeCodec();
      final flow = _flow(codec);
      flow.start();
      final session = codec.lastSession;
      _scanToReview(flow, codec);

      flow.reject();

      expect(flow.phase, QrSignPhase.idle);
      expect(flow.request, isNull);
      expect(flow.progress, isNull);
      expect(session?.disposed, isTrue);
      flow.dispose();
    });

    test('frames after cancel are ignored', () {
      final codec = _FakeCodec();
      final flow = _flow(codec);
      flow.start();
      flow.cancel();

      flow.submitFrame('ur:eth-sign-request/1-2/a');

      expect(flow.phase, QrSignPhase.idle);
      expect(flow.progress, isNull);
      flow.dispose();
    });

    test('dispose tears the session down mid-scan', () {
      final codec = _FakeCodec();
      final flow = _flow(codec);
      flow.start();
      final session = codec.lastSession;

      flow.dispose();

      expect(session?.disposed, isTrue);
    });
  });
}
