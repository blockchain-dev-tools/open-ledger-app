/// APDU conformance runner.
///
/// Drives [ApduHandler] from the language-neutral corpus in `spec/apdu/`, so
/// the Flutter device and the TS simulator are checked against the same
/// bytes. This is the convergence mechanism: prose checklists rot (see the
/// stale F1-F6 table in docs/decisions/002-apdu-protocol-alignment.md), test
/// vectors do not.
///
/// The corpus only covers the OS / app shell. Chain commands are served by
/// the Rust chain-app modules and are verified by their crate tests plus the
/// device e2e suite.
///
/// `spec/apdu/gaps.json` lists known deviations; each surfaces as a skipped
/// test so it cannot silently rot.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/biz/apdu_handler.dart';
import 'package:open_ledger_app/core/models/apdu_message.dart';
import 'package:open_ledger_app/core/models/chain.dart';

void main() {
  final specDir = _findSpecDir();
  final vectors = _loadAllVectors(Directory('${specDir.path}/vectors'));
  final gaps = _loadList(File('${specDir.path}/gaps.json'), 'gaps');

  group('APDU conformance · structural', () {
    for (final v in vectors) {
      final id = v['id'] as String;
      test(id, () {
        final response = _buildHandler(v).handle(_buildCommand(v));
        expect(
          _hex(response.toBytes()),
          (v['response'] as String).toLowerCase(),
          reason: '$id [provenance=${v['provenance']}] ${v['note'] ?? ''}',
        );
      });
    }
  });

  group('APDU known gaps (ADR-tracked)', () {
    for (final gap in gaps) {
      test('${gap['id']} · ${gap['ref']}', () {
        markTestSkipped(gap['description'] as String);
      });
    }
  });
}

// ── Vector → handler ────────────────────────────────────────────────────

ApduHandler _buildHandler(Map<String, dynamic> v) {
  final handler = ApduHandler();
  final app = v['currentApp'] as String?;
  if (app != null) handler.setCurrentApp(LedgerApp.values.byName(app));
  return handler;
}

ApduCommand _buildCommand(Map<String, dynamic> v) => ApduCommand(
      cla: v['cla'] as int,
      ins: v['ins'] as int,
      p1: v['p1'] as int,
      p2: v['p2'] as int,
      data: _bytesOrNull(v['data'] as String?),
    );

// ── Corpus loading ──────────────────────────────────────────────────────

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
      vectors.addAll(_loadList(entity, 'vectors'));
    }
  }
  return vectors;
}

List<Map<String, dynamic>> _loadList(File file, String key) {
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return (json[key] as List).cast<Map<String, dynamic>>();
}

// ── Hex ─────────────────────────────────────────────────────────────────

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
