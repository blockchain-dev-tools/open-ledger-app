import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';

/// Full-screen camera view that scans a recovery-phrase QR code.
///
/// Returns the first non-empty barcode payload via `Navigator.pop`, or `null`
/// when the user backs out. The payload format matches `SeedQrScreen` (plain,
/// space-separated words); validation happens on the import screen so the
/// single source of truth stays the Rust `validateMnemonic`.
///
/// The chrome is deliberately dark (`ColorTokens.dark`) regardless of the app
/// theme — a camera viewfinder with a white backdrop is unreadable.
class MnemonicQrScanScreen extends StatefulWidget {
  const MnemonicQrScanScreen({super.key});

  @override
  State<MnemonicQrScanScreen> createState() => _MnemonicQrScanScreenState();
}

class _MnemonicQrScanScreenState extends State<MnemonicQrScanScreen> {
  late final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
  );

  /// Guards against a second detection popping the route twice.
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.trim().isEmpty) continue;
      _handled = true;
      Navigator.of(context).pop(raw);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = ColorTokens.dark;

    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              key: const Key('qr-scan-view'),
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error, child) {
                final denied = error.errorCode ==
                    MobileScannerErrorCode.permissionDenied;
                return ColoredBox(
                  color: c.bg,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.videocam_off, size: 40, color: c.text),
                          const SizedBox(height: 16),
                          Text(
                            denied
                                ? l10n.qrScanPermissionDenied
                                : l10n.qrScanCameraError,
                            key: const Key('qr-scan-error'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.text, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        key: const Key('qr-scan-close'),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close, color: c.text),
                      ),
                      Expanded(
                        child: Text(
                          l10n.qrScanTitle,
                          style: TextStyle(
                            color: c.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    l10n.qrScanHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.text.withAlpha(180), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
