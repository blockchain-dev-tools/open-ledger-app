import 'package:flutter/material.dart';

import '../../../core/interfaces/backup_verifier.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/grid_background.dart';
import '../../widgets/common/neo_app_bar.dart';
import '../../widgets/common/neo_card.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/verify/verify_result_card.dart';

/// Enigma (riddle + key) verification — path 3 of ADR-011 §5.
///
/// Only reachable for an Enigma-created vault; the verifier re-derives the
/// phrase with the `enigmaLanguage` persisted at creation (the hidden
/// variable — the same riddle + key in another language yields a different
/// phrase) and compares it word-by-word against the vault's mnemonic.
class VerifyBackupEnigmaScreen extends StatefulWidget {
  const VerifyBackupEnigmaScreen({
    super.key,
    this.verifier,
    this.previewRiddle,
    this.previewResult,
  });

  /// Live verifier; `null` → render [previewResult] verbatim.
  final IBackupVerifier? verifier;

  /// Preview-only riddle seeded into the input.
  final String? previewRiddle;

  /// Preview-only verdict rendered without tapping Verify.
  final VerifyResult? previewResult;

  @override
  State<VerifyBackupEnigmaScreen> createState() =>
      _VerifyBackupEnigmaScreenState();
}

class _VerifyBackupEnigmaScreenState extends State<VerifyBackupEnigmaScreen> {
  late final TextEditingController _riddleController;
  final TextEditingController _secretController = TextEditingController();
  bool _obscure = true;
  VerifyResult? _result;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _riddleController =
        TextEditingController(text: widget.previewRiddle ?? '');
  }

  @override
  void dispose() {
    _riddleController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final verifier = widget.verifier;
    if (verifier == null) return;
    setState(() {
      _checking = true;
      _result = null;
    });
    VerifyResult result;
    try {
      result = await verifier.verifyEnigma(
        _riddleController.text,
        _secretController.text,
      );
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
        title: Text(l10n.verifyEnigmaTitle),
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
                  Icon(Icons.auto_awesome_outlined, size: 44, color: c.primary),
                  const SizedBox(height: 16),
                  Text(
                    l10n.verifyEnigmaHint,
                    style: TextStyle(
                        color: c.text.withAlpha(150), fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  _label(c, l10n.enigmaRiddleLabel),
                  const SizedBox(height: 8),
                  _field(
                    c: c,
                    key: const Key('verify-enigma-riddle'),
                    controller: _riddleController,
                    minLines: 2,
                    maxLines: 4,
                    hint: null,
                  ),
                  const SizedBox(height: 20),
                  _label(c, l10n.enigmaSecretLabel),
                  const SizedBox(height: 8),
                  _field(
                    c: c,
                    key: const Key('verify-enigma-secret'),
                    controller: _secretController,
                    obscure: _obscure,
                    suffix: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                        color: c.text.withAlpha(150),
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: l10n.verifyAction,
                    loading: _checking,
                    onTap: _verify,
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

  Widget _label(ColorTokens c, String text) => Text(
        text,
        style: TextStyle(
          color: c.text.withAlpha(160),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      );

  Widget _field({
    required ColorTokens c,
    required Key key,
    required TextEditingController controller,
    int minLines = 1,
    int maxLines = 1,
    bool obscure = false,
    Widget? suffix,
    String? hint,
  }) {
    return NeoCard(
      // Light outlines the field as a neo block; dark falls back to the
      // original hairline box.
      legacyRadius: R.lg,
      legacyEdge: c.border,
      child: TextField(
        key: key,
        controller: controller,
        minLines: minLines,
        maxLines: maxLines,
        obscureText: obscure,
        autocorrect: false,
        enableSuggestions: false,
        style: TextStyle(color: c.text, fontSize: 14, height: 1.5),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: c.text.withAlpha(70)),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          suffixIcon: suffix,
        ),
      ),
    );
  }
}
