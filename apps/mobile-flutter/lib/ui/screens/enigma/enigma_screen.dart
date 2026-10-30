import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/bip39_wordlist.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/enigma_logo_icon.dart';
import '../../widgets/common/grid_background.dart';
import '../../widgets/common/neo_app_bar.dart';
import '../../widgets/common/neo_back_button.dart';
import '../../widgets/common/neo_card.dart';
import '../../widgets/mnemonic/enigma_form.dart';

/// Enigma wallet creation screen.
///
/// Alternative wallet creation flow: the user provides a personal riddle
/// and secret key. These are combined and hashed to produce deterministic
/// entropy, from which a 24-word BIP-39 mnemonic is derived.
///
/// On success, navigates to [EnigmaMnemonicScreen] with the generated words.
///
/// The inputs themselves live in [EnigmaForm], which the vault manager's
/// "New Vault" Enigma tab renders too.
///
/// Ported from the original TypeScript implementation.
class EnigmaScreen extends StatefulWidget {
  const EnigmaScreen({super.key});

  @override
  State<EnigmaScreen> createState() => _EnigmaScreenState();
}

class _EnigmaScreenState extends State<EnigmaScreen> {
  final _riddleController = TextEditingController();
  final _secretController = TextEditingController();
  Bip39WordlistLanguage _selectedLanguage = Bip39WordlistLanguage.english;

  @override
  void dispose() {
    _riddleController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  /// Leaves the screen: first-run setup returns to Welcome.
  void _onBack() => context.go('/welcome');

  /// Hands the derived words to the review step.
  void _onGenerated(EnigmaDerivation derivation) {
    context.go(
      '/enigma-mnemonic',
      extra: <String, Object>{
        'words': derivation.words,
        'language': derivation.language,
        'entropyHex': derivation.entropyHex,
        'riddle': derivation.riddle,
        'secret': derivation.secret,
        'addVault': false,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = Theme.of(context).brightness == Brightness.dark
        ? ColorTokens.dark
        : ColorTokens.light;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        // Light follows the neo page tint (pale lime) so the reference grid
        // reads as paper ruling; dark's `groupedBg` equals `bg`, so this only
        // affects light mode.
        backgroundColor: c.groupedBg,
        appBar: neoAppBar(
          c: c,
          title: Text(l10n.enigmaWallet),
          leading: neoBackButton(c, onPressed: _onBack),
        ),
        body: GridBackground(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header ──────────────────────────────────────────
                  if (c.neobrutalism)
                    Center(
                      child: NeoCard(
                        fill: c.actionFill,
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: Center(
                            child: EnigmaLogoIcon(color: c.brandInk, size: 48),
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.primary.withAlpha(20),
                        border: Border.all(color: c.primary.withAlpha(60)),
                      ),
                      alignment: Alignment.center,
                      child: EnigmaLogoIcon(color: c.primary, size: 36),
                    ),

                  const SizedBox(height: 24),

                  Text(
                    l10n.enigmaTitle,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.enigmaDescription,
                    style: TextStyle(
                      color: c.mutedText(160),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Inputs + Generate ────────────────────────────────
                  EnigmaForm(
                    riddleController: _riddleController,
                    secretController: _secretController,
                    language: _selectedLanguage,
                    onLanguageChanged: (lang) => setState(() {
                      _selectedLanguage = lang;
                    }),
                    onGenerated: _onGenerated,
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
