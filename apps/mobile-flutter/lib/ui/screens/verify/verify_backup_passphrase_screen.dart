import 'package:flutter/material.dart';

import '../../../core/interfaces/backup_verifier.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/grid_background.dart';
import '../../widgets/common/neo_app_bar.dart';
import '../../widgets/common/neo_card.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/verify/verify_result_card.dart';

/// BIP-39 passphrase verification — path 2 of ADR-011 §5.
///
/// The passphrase is never exported (ADR-011 §维度 C), so this is the only way
/// to confirm the user still remembers one. Verdicts are deliberately
/// two-directional: a mismatch can mean a typo **or** that this wallet has no
/// passphrase at all, so [verifyPassphraseHint] tells the user to leave the
/// field empty in that case rather than reading every mismatch as "wrong".
class VerifyBackupPassphraseScreen extends StatefulWidget {
  const VerifyBackupPassphraseScreen({
    super.key,
    this.verifier,
    this.previewResult,
  });

  /// Live verifier; `null` → render [previewResult] verbatim.
  final IBackupVerifier? verifier;

  /// Preview-only verdict rendered without tapping Verify.
  final VerifyResult? previewResult;

  @override
  State<VerifyBackupPassphraseScreen> createState() =>
      _VerifyBackupPassphraseScreenState();
}

class _VerifyBackupPassphraseScreenState
    extends State<VerifyBackupPassphraseScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;
  VerifyResult? _result;
  bool _checking = false;

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
    VerifyResult result;
    try {
      result = await verifier.verifyPassphrase(_controller.text);
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
        title: Text(l10n.verifyPassphraseTitle),
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
                  Icon(Icons.password_outlined, size: 44, color: c.primary),
                  const SizedBox(height: 16),
                  Text(
                    l10n.verifyPassphraseHint,
                    style: TextStyle(
                        color: c.text.withAlpha(150), fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  NeoCard(
                    // Light outlines the field as a neo block; dark falls back
                    // to the original hairline box.
                    legacyRadius: R.lg,
                    legacyEdge: c.border,
                    child: TextField(
                      key: const Key('verify-passphrase-input'),
                      controller: _controller,
                      obscureText: _obscure,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: TextStyle(color: c.text, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: l10n.enterPassphraseOptional,
                        hintStyle: TextStyle(color: c.text.withAlpha(80)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility,
                            color: c.text.withAlpha(150),
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
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
}
