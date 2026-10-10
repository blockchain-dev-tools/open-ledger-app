// Standalone design-gallery entry (ADR-005).
//
// Run:
//   flutter run  -t tool/gallery/main.dart -d chrome   # iteration / review / screenshots
//
// Web is the single supported target (ADR-005). Scenarios are fixed mock
// data plus URL deep links, so hot restart is equivalent to stateful reload.
//
// This entry MUST stay FFI/BLE-free so it compiles for web. The boundary is
// enforced by test/gallery/ffi_guard_test.dart — do not import
// infrastructure/ffi, infrastructure/ble, lib/main.dart or lib/app/.
import 'package:flutter/material.dart';

import 'gallery_app.dart';
import 'gallery_boot.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // NOTE: do not set debugDefaultTargetPlatformOverride here — it throws in
  // release builds, and shoot.sh builds --release. Platform emulation for
  // Material widgets (AppBar title alignment, scrollbars) is pinned via
  // ThemeData(platform: android) in gallery_app.dart.
  runApp(GalleryApp(boot: GalleryBoot.current()));
}
