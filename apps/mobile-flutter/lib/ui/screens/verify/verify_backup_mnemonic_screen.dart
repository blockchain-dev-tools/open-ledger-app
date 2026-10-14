import 'package:flutter/material.dart';

import '../../../core/interfaces/backup_verifier.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/grid_background.dart';
import '../../widgets/common/neo_app_bar.dart';
import '../../widgets/common/neo_card.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/verify/verify_result_card.dart';

/// Mnemonic verification — path 1 of ADR-011 §5.
///
/// The user retypes the phrase from their written backup and the verifier
/// recomputes the wallet's Ethereum address from it (baseline E2). Unlike the
/// export screens this is **not** PIN-gated: nothing secret is revealed, only
/// a verdict, and the user is the one supplying the secret.
///
/// With a [verifier] the verdict is live; with `null` the preview fields
/// ([previewInput] / [previewResult]) are rendered verbatim, which is how the
/// design gallery reviews each state without crypto or FFI.
class VerifyBackupMnemonicScreen extends StatefulWidget {
  const VerifyBackupMnemonicScreen({
    super.key,
    this.verifier,
    this.previewInput,
    this.previewResult,
  });

  /// Live verifier; `null` → render the preview fields.
  final IBackupVerifier? verifier;

  /// Preview-only phrase seeded into the input.
  final String? previewInput;

  /// Preview-only verdict rendered without tapping Verify.
  final VerifyResult? previewResult;

  @override
  State<VerifyBackupMnemonicScreen> createState() =>
      _VerifyBackupMnemonicScreenState();
}

class _VerifyBackupMnemonicScreenState
    extends State<VerifyBackupMnemonicScreen> {
  late final TextEditingController _controller;
  VerifyResult? _result;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.previewInput ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final verifier = widget.verifier;
    if (verifier == null) return;
    setState(() {
      _checking = true;
      _result = null;
    });
    // `BackupVerifier` never throws, but a `GestureDetector` callback swallows
    // exceptions silently, so guard the call anyway and surface a verdict.
    VerifyResult result;
    try {
      result = await verifier.verifyMnemonic(_controller.text);
    } catch (_) {
      result = VerifyResult.unavailable;
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;
    final result = _result ?? widget.previewResult;

    return Scaffold(
      // Light follows the neo page tint (pale lime) so the reference grid
      // reads as paper ruling; dark's `groupedBg` equals `bg`, so this only
      // affects light mode.
      backgroundColor: c.groupedBg,
      appBar: neoAppBar(
        c: c,
        darkBackground: c.bg,
        title: Text(l10n.verifySeedTitle),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.text),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: GridBackground(
        // `SizedBox.expand` forces the body to the viewport height so the grid
        // painter (which sizes itself to its child) covers the whole page. A
        // bare `SingleChildScrollView` shrink-wraps to short content, which
        // leaves the grid stopping part-way down. Scrolling is unaffected.
        child: SizedBox.expand(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.spellcheck, size: 44, color: c.primary),
                  const SizedBox(height: 16),
                  Text(
                    l10n.verifySeedHint,
                    style: TextStyle(color: c.text.withAlpha(150), fontSize: 13,
                        height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  _PhraseField(c: c, controller: _controller),
                  const SizedBox(height: 24),
                  // Rebuild on every keystroke so the button enables as soon as
                  // the field is non-empty (the screen has no other text input).
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder: (context, value, _) => PrimaryButton(
                      label: l10n.verifyAction,
                      loading: _checking,
                      onTap: value.text.trim().isEmpty ? null : _verify,
                    ),
                  ),
                  if (result != null) ...[
                    const SizedBox(height: 20),
                    VerifyResultCard(result: result),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Multi-line phrase input: no autocorrect / suggestions, so the OS never
/// learns the words the user types.
class _PhraseField extends StatelessWidget {
  const _PhraseField({required this.c, required this.controller});

  final ColorTokens c;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return NeoCard(
      // Light outlines the field as a neo block; dark falls back to the
      // original hairline box.
      legacyRadius: R.lg,
      legacyEdge: c.border,
      child: TextField(
        key: const Key('verify-seed-input'),
        controller: controller,
        minLines: 3,
        maxLines: 5,
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.none,
        keyboardType: TextInputType.multiline,
        style: TextStyle(color: c.text, fontSize: 14, height: 1.5),
        decoration: InputDecoration(
          hintText: 'abandon abandon abandon …',
          hintStyle: TextStyle(color: c.text.withAlpha(70)),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}
