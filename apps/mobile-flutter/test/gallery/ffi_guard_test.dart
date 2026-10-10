// ADR-005 hard boundary: the design gallery (`tool/gallery/`) compiles for
// Flutter web, where dart:ffi and BLE-peripheral plugins do not exist. This
// test scans the gallery sources for forbidden imports so the boundary can
// never be crossed by accident. It needs no device and no Rust library.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gallery stays FFI/BLE-free (web-compatible)', () {
    final galleryDir = Directory('tool/gallery');
    expect(
      galleryDir.existsSync(),
      isTrue,
      reason: 'tool/gallery directory missing',
    );

    // Substring matches are intentionally simple: these tokens only appear in
    // import lines, and a false positive would just read as a code smell.
    const forbidden = <String>[
      'infrastructure/ffi/',
      'infrastructure/ble/',
      'package:ffi/',
      'dart:ffi',
      // AppState wires the real BLE peripheral; the gallery assembles its
      // own fake dependencies instead.
      'package:open_ledger_app/app/',
      '../../lib/app/',
      '../../lib/main.dart',
    ];

    final violations = <String>[];
    for (final entity in galleryDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (!line.startsWith('import') && !line.startsWith('export')) {
          continue;
        }
        for (final token in forbidden) {
          if (line.contains(token)) {
            violations.add('${entity.path}:${i + 1}: contains "$token"\n'
                '  ${lines[i].trim()}');
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Gallery must not import FFI/BLE/app entry points:\n'
          '${violations.join('\n')}',
    );
  });
}
