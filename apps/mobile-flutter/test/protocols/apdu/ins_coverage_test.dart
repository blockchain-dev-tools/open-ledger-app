/// Static INS-table coverage check — the "no silent drift" gate.
///
/// The runtime conformance runner (conformance_test.dart) checks bytes for the
/// handlers that already exist. This test checks the *vocabulary*: that the
/// `Cla` and `Ins` tables in apdu_constants.dart still line up with the official
/// Ledger app INS tables frozen in `spec/apdu/commands.json`, and that every
/// difference is a *declared* one in `spec/apdu/coverage.json`.
///
/// Invariants
///   1. coverage lists every official INS exactly once, and nothing else;
///   2. `aligned` / `differentMeaning` entries point at a Dart constant with
///      the same byte value;
///   3. every Dart `Ins` constant is either mapped by coverage or listed in
///      `dartOnly` — adding / renaming / removing one breaks this test until it
///      is classified, so drift cannot be silent;
///   4. every `ref` resolves to a known id in `spec/apdu/gaps.json`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final specDir = _findSpecDir();
  final repoRoot = specDir.parent.parent.path;

  final commands = _readJson('${specDir.path}/commands.json');
  final coverage = _readJson('${specDir.path}/coverage.json');
  final gapIds = (_readJson('${specDir.path}/gaps.json')['gaps']! as List)
      .cast<Map<String, dynamic>>()
      .map((g) => g['id'] as String)
      .toSet();

  final dartSource = File(
    '$repoRoot/apps/mobile-flutter/lib/protocols/apdu/apdu_constants.dart',
  ).readAsStringSync();
  final dartIns = _parseClassConstants(dartSource, 'Ins');
  final dartCla = _parseClassConstants(dartSource, 'Cla');

  final apps = (commands['apps']! as Map).cast<String, dynamic>();
  final official = <String, Map<String, dynamic>>{};
  apps.forEach((appName, value) {
    final app = (value as Map).cast<String, dynamic>();
    for (final ins in (app['ins']! as List).cast<Map<String, dynamic>>()) {
      official['$appName:${ins['ins']}'] = ins;
    }
  });

  final entries = (coverage['coverage']! as List).cast<Map<String, dynamic>>();
  final dartOnly = (coverage['dartOnly']! as List).cast<Map<String, dynamic>>();

  group('APDU INS coverage · commands.json ↔ apdu_constants.dart', () {
    test('coverage lists every official INS exactly once', () {
      final seen = <String>{};
      for (final c in entries) {
        final key = '${c['app']}:${c['ins']}';
        expect(official, contains(key),
            reason: 'coverage.json references $key, absent from commands.json');
        expect(seen.add(key), isTrue, reason: 'duplicate coverage entry for $key');
      }
      expect(seen, equals(official.keys.toSet()),
          reason: 'coverage.json is stale: official INS added/removed without updating it');
    });

    test('aligned / differentMeaning entries match the Dart constant byte', () {
      for (final c in entries) {
        final at = '${c['app']}:${c['ins']}';
        final state = c['state'] as String;
        if (state == 'missing') {
          expect(c['dart'], isNull,
              reason: '$at is "missing" but names a Dart constant');
          continue;
        }
        expect(state, anyOf('aligned', 'differentMeaning'),
            reason: '$at has unknown state "$state"');
        final name = c['dart'] as String?;
        expect(name, isNotNull, reason: '$at ($state) must name a Dart constant');
        expect(dartIns, contains(name),
            reason: 'coverage.json names Ins.$name for $at, but it no longer exists');
        expect(dartIns[name], _hexInt(c['ins'] as String),
            reason: 'Ins.$name drifted from $at');
      }
    });

    test('every Dart Ins constant is classified', () {
      final mapped = <String>{
        for (final c in entries)
          if (c['dart'] != null) c['dart'] as String,
      };
      final declared = {
        ...mapped,
        ...dartOnly.map((d) => d['dart'] as String),
      };
      final actual = dartIns.keys.toSet();
      expect(actual.difference(declared), isEmpty,
          reason: 'Ins constant(s) not classified in coverage.json (add/rename/remove drift)');
      expect(declared.difference(actual), isEmpty,
          reason: 'coverage.json names Ins constant(s) that no longer exist');
    });

    test('every coverage ref resolves to a gaps.json id', () {
      final refs = <String>[
        for (final c in entries)
          if (c['ref'] != null) c['ref'] as String,
        for (final d in dartOnly)
          if (d['ref'] != null) d['ref'] as String,
      ];
      for (final ref in refs) {
        expect(gapIds, contains(ref),
            reason: 'coverage.json ref "$ref" is not a gaps.json gap id');
      }
    });

    test('every official CLA is known to the Dart Cla table', () {
      final known = dartCla.values.toSet();
      apps.forEach((appName, value) {
        final app = (value as Map).cast<String, dynamic>();
        for (final key in const ['cla', 'frameworkCla']) {
          final raw = app[key] as String?;
          if (raw == null) continue;
          expect(known, contains(_hexInt(raw)),
              reason: '$appName.$key ($raw) has no Cla constant in apdu_constants.dart');
        }
      });
    });
  });
}

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

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

// ── Dart constant parsing ───────────────────────────────────────────────

/// Extract `static const int <name> = 0x<hex>;` declarations from a class body
/// in apdu_constants.dart, ignoring the doc comments.
Map<String, int> _parseClassConstants(String source, String className) {
  final marker = 'class $className {';
  final start = source.indexOf(marker);
  if (start < 0) throw StateError('class $className not found in apdu_constants.dart');
  final bodyStart = start + marker.length;
  final end = source.indexOf('\n}', bodyStart);
  if (end < 0) throw StateError('closing brace for class $className not found');
  final body = source.substring(bodyStart, end);
  final re = RegExp(r'static const int (\w+)\s*=\s*(0x[0-9a-fA-F]+)\s*;');
  return {
    for (final m in re.allMatches(body))
      m.group(1)!: int.parse(m.group(2)!.substring(2), radix: 16),
  };
}

int _hexInt(String s) {
  final v = (s.startsWith('0x') || s.startsWith('0X')) ? s.substring(2) : s;
  return int.parse(v, radix: 16);
}
