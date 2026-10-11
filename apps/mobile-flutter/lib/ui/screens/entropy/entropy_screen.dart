import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../../services/mnemonic_service.dart';

/// Collect 200 touch points from the user to generate entropy for a
/// BIP-39 mnemonic phrase.
///
/// Each tap records X/Y coordinates plus a timestamp. After 200 taps,
/// the data is concatenated and used to seed generation of a 12-word
/// mnemonic via [CryptoBridge.generateMnemonic].
///
/// Ported from the original TypeScript implementation.
class EntropyScreen extends StatefulWidget {
  final MnemonicService? mnemonicService;
  const EntropyScreen({super.key, this.mnemonicService});

  @override
  State<EntropyScreen> createState() => _EntropyScreenState();
}

class _EntropyScreenState extends State<EntropyScreen> {
  int _tapCount = 0;

  static const int _requiredTaps = 200;

  /// Records a touch point and increments the counter.
  void _onTap(TapDownDetails _) {
    if (_tapCount >= _requiredTaps) return;

    setState(() {
      _tapCount++;
    });

    if (_tapCount >= _requiredTaps) {
      _finalize();
    }
  }

  bool _isGenerating = false;
  String? _error;

  /// Generates the mnemonic and navigates to the display screen.
  Future<void> _finalize() async {
    if (_isGenerating) return;
    setState(() {
      _isGenerating = true;
      _error = null;
    });

    try {
      final mnemonic = widget.mnemonicService!.generateMnemonic(strength: 128);

      if (!mounted) return;

      if (mnemonic.isEmpty) {
        throw Exception('Generated empty mnemonic');
      }

      if (!mounted) return;
      context.go('/generate-mnemonic', extra: mnemonic);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to generate recovery phrase: $e';
        _isGenerating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = Theme.of(context).brightness == Brightness.dark
        ? ColorTokens.dark
        : ColorTokens.light;
    final progress = _tapCount / _requiredTaps;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) context.go('/welcome');
      },
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          backgroundColor: c.bg,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: c.text),
            onPressed: () => context.go('/welcome'),
          ),
        ),
        body: SafeArea(
        child: GestureDetector(
          onTapDown: _onTap,
          behavior: HitTestBehavior.opaque,
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Icon ───────────────────────────────────────
                    Icon(
                      Icons.touch_app,
                      size: 72,
                      color: c.primary,
                    ),

                    const SizedBox(height: 28),

                    // ── Title ─────────────────────────────────────
                    Text(
                      l10n.entropyTitle,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── Instruction ───────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        l10n.tapRandomly,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: c.text.withAlpha(160),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),

                    // ── Counter ───────────────────────────────────
                    Text(
                      '$_tapCount / $_requiredTaps touches',
                      style: TextStyle(
                        color: progress >= 1.0
                            ? c.primary
                            : c.text.withAlpha(180),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Progress bar ──────────────────────────────
                    Container(
                      width: 260,
                      height: 10,
                      decoration: BoxDecoration(
                        color: c.border.withAlpha(100),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: progress.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: c.primary,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 44),

                    // ── Tap area hint ─────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(R.lg),
                        border: Border.all(color: c.border.withAlpha(100)),
                      ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.gesture,
                        size: 32,
                        color: _error != null
                            ? c.error
                            : c.primary,
                      ),
                      const SizedBox(height: 10),
                      if (_isGenerating)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: c.primary,
                            ),
                          ),
                        ),
                      Text(
                        _error != null
                            ? _error!
                            : _isGenerating
                                ? l10n.processing
                                : _tapCount >= _requiredTaps
                                    ? l10n.processing
                                    : l10n.entropyInstruction,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _error != null
                              ? c.error.withAlpha(220)
                              : c.text.withAlpha(160),
                          fontSize: 13,
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () {
                            if (!_isGenerating) _finalize();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: c.primary.withAlpha(30),
                              borderRadius: BorderRadius.circular(R.sm),
                              border: Border.all(
                                color: c.primary.withAlpha(100),
                              ),
                            ),
                            child: Text(
                              l10n.retry,
                              style: TextStyle(
                                color: c.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}
