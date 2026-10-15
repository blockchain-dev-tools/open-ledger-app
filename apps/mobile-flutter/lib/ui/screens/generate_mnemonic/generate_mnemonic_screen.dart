import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/grid_background.dart';
import '../../widgets/common/neo_app_bar.dart';
import '../../widgets/common/neo_back_button.dart';
import '../../widgets/mnemonic/warning_banner.dart';
import '../../widgets/mnemonic/mnemonic_word_grid.dart';
import '../../widgets/common/adaptive_action_button.dart';
import '../../widgets/common/neo_card.dart';

/// Displays the generated 12-word BIP-39 mnemonic in a 3×4 word grid.
///
/// The user must visually confirm they have recorded the phrase before
/// proceeding to the verification quiz.
///
/// Accepts [mnemonic] as a space-separated string of 12 BIP-39 words.
///
/// Ported from the original TypeScript implementation.
class GenerateMnemonicScreen extends StatefulWidget {
  /// The 12-word BIP-39 mnemonic phrase (space-separated).
  final String mnemonic;

  const GenerateMnemonicScreen({super.key, required this.mnemonic});

  @override
  State<GenerateMnemonicScreen> createState() =>
      _GenerateMnemonicScreenState();
}

class _GenerateMnemonicScreenState extends State<GenerateMnemonicScreen> {
  bool _confirmed = false;
  bool _showPassphrase = false;
  bool _obscurePassphrase = true;
  final TextEditingController _passphraseController = TextEditingController();

  @override
  void dispose() {
    _passphraseController.dispose();
    super.dispose();
  }

  List<String> get _words => widget.mnemonic.split(' ');

  /// Navigates to the verification screen with the mnemonic and optional passphrase.
  void _continue() {
    final passphrase = _passphraseController.text.trim();
    context.go('/verify-mnemonic', extra: {
      'mnemonic': widget.mnemonic,
      'passphrase': passphrase,
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = Theme.of(context).brightness == Brightness.dark
        ? ColorTokens.dark
        : ColorTokens.light;
    final words = _words;

    return Scaffold(
      // Light follows the neo page tint (pale lime) so the reference grid
      // reads as paper ruling; dark's `groupedBg` equals `bg`, so this only
      // affects light mode.
      backgroundColor: c.groupedBg,
      appBar: neoAppBar(
        c: c,
        leading: neoBackButton(c, onPressed: () {
          if (context.canPop()) {
            context.pop();
          }
        }),
        darkBackground: c.bg,
      ),
      body: GridBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 8),

                // ── Title ───────────────────────────────────────────
                Text(
                  l10n.generateMnemonicTitle,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 16),

                // ── Warning ─────────────────────────────────────────
                WarningBanner(
                  message: l10n.generateMnemonicWarning,
                ),

                const SizedBox(height: 24),

                // ── Word Grid (3 columns × 4 rows) ──────────────────
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: MnemonicWordGrid(
                        words: words,
                        // Two per row: three leaves the cells too narrow and the
                        // longest BIP-39 words get ellipsised. The wider ratio
                        // keeps the cell height unchanged.
                        columns: 2,
                        childAspectRatio: 4.0,
                        fontSize: 14,
                        // Light draws the neo cells; dark keeps the flat tiles.
                        neo: c.neobrutalism,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Confirmation checkbox ───────────────────────────
                _ConfirmationCheckbox(
                  c: c,
                  confirmed: _confirmed,
                  l10n: l10n,
                  onToggle: () {
                    setState(() {
                      _confirmed = !_confirmed;
                    });
                  },
                ),

                const SizedBox(height: 16),

                _buildPassphraseSection(c, l10n),

                const SizedBox(height: 4),

                // ── Continue button ──────────────────────────────────
                // The neo button has no disabled state, so an unconfirmed
                // checkbox keeps the original flat button even in light mode.
                AdaptiveActionButton(
                  label: l10n.continueButton,
                  onTap: _confirmed ? _continue : null,
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The optional BIP-39 passphrase section: the collapsible toggle plus the
  /// input card it reveals, kept together so the reveal state stays local.
  Widget _buildPassphraseSection(ColorTokens c, AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Passphrase toggle ────────────────────────────
        GestureDetector(
          onTap: () {
            setState(() {
              _showPassphrase = !_showPassphrase;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.advancedBip39Passphrase,
                    style: TextStyle(
                      color: c.mutedText(150),
                      fontSize: 13,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _showPassphrase ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.chevron_right,
                    color: c.mutedText(120),
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Passphrase input (collapsible) ───────────────
        if (_showPassphrase) ...[
          NeoCard(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            // Dark keeps the original hairline-outlined surface card.
            legacyEdge: c.border.withAlpha(100),
            legacyEdgeWidth: 1,
            legacyRadius: R.lg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A passphrase acts as a 13th word. It creates a '
                  'completely different wallet from the same recovery '
                  'phrase. If you use one, you MUST remember it — '
                  'there is no way to recover it.',
                  style: TextStyle(
                    color: c.mutedText(120),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('passphrase-input'),
                  controller: _passphraseController,
                  obscureText: _obscurePassphrase,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    // Light fills with the neo surface (white-on-page);
                    // dark keeps its original `bg` fill.
                    fillColor: c.neobrutalism ? c.surface : c.bg,
                    hintText: l10n.enterPassphraseOptional,
                    hintStyle: TextStyle(
                      color: c.mutedText(80),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        c.neobrutalism ? Neo.radius : R.lg,
                      ),
                      borderSide: BorderSide(
                        color: c.neobrutalism
                            ? c.neoEdge
                            : c.border.withAlpha(100),
                        width: c.neobrutalism ? Neo.edge : 1,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        c.neobrutalism ? Neo.radius : R.lg,
                      ),
                      borderSide: BorderSide(
                        color: c.neobrutalism
                            ? c.neoEdge
                            : c.border.withAlpha(100),
                        width: c.neobrutalism ? Neo.edge : 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        c.neobrutalism ? Neo.radius : R.lg,
                      ),
                      borderSide: BorderSide(
                        color: c.neobrutalism
                            ? c.neoEdge
                            : c.primary,
                        width: c.neobrutalism ? Neo.edge : 1,
                      ),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassphrase
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: c.text.withAlpha(120),
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassphrase = !_obscurePassphrase;
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ConfirmationCheckbox extends StatelessWidget {
  const _ConfirmationCheckbox({
    required this.c,
    required this.confirmed,
    required this.l10n,
    required this.onToggle,
  });

  final ColorTokens c;
  final bool confirmed;
  final AppLocalizations l10n;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: NeoCard(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        // Dark keeps the original hairline-outlined surface card.
        legacyEdge: c.border.withAlpha(100),
        legacyEdgeWidth: 1,
        legacyRadius: R.lg,
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  // Light keeps the black neo outline in every
                  // state; dark keeps its primary/border colouring.
                  color: c.neobrutalism
                      ? c.neoEdge
                      : (confirmed ? c.primary : c.border),
                  width: 2,
                ),
                color: confirmed
                    ? c.primary
                    : Colors.transparent,
              ),
              child: confirmed
                  ? Icon(
                      Icons.check,
                      size: 16,
                      color: c.onPrimary,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Text(
              l10n.iveWrittenItDown,
              style: TextStyle(
                color: c.mutedText(200),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
