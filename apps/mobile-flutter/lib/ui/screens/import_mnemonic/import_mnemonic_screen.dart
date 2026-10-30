import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../data/bip39_english.dart';
import '../../../data/bip39_wordlist.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../services/mnemonic_service.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/grid_background.dart';
import '../../widgets/common/neo_app_bar.dart';
import '../../widgets/common/neo_back_button.dart';
import '../../widgets/common/tab_button.dart';
import '../../widgets/mnemonic/enigma_form.dart';
import 'components/import_button.dart';
import 'components/mnemonic_input_field.dart';
import 'components/mnemonic_status_row.dart';
import 'components/mnemonic_suggestions.dart';
import 'components/passphrase_field.dart';
import 'components/paste_button.dart';
import 'components/qr_scan_button.dart';
import 'qr_scan_screen.dart';

/// Free-text import of an existing 12- or 24-word BIP-39 mnemonic phrase.
///
/// User types, pastes or scans a QR code with the space-separated words. The
/// input is validated on every change via [CryptoBridge.validateMnemonic].
/// While the current word is unfinished, an alphabetically ordered BIP-39
/// prefix suggestion strip under the field completes it on tap. A valid
/// mnemonic shows a green checkmark and enables the Import button. On
/// successful import, navigates to PIN setup.
///
/// Each block lives in `components/`; this file owns the controllers,
/// validation and navigation.
///
/// Ported from the original TypeScript implementation.
class ImportMnemonicScreen extends StatefulWidget {
  final MnemonicService? mnemonicService;

  /// When `true`, the imported mnemonic is added to the current session as a
  /// new vault (via `walletService.addVault`) instead of creating a wallet.
  final bool addVault;

  /// Test seam: returns a scanned payload instead of opening the camera. When
  /// null the screen pushes [MnemonicQrScanScreen].
  final Future<String?> Function()? qrScanOverride;

  /// Test seam: replaces the Rust-backed Enigma derivation of the secret
  /// phrase tab. Null uses `generateEnigmaMnemonic`.
  final EnigmaDerive? enigmaDerive;

  const ImportMnemonicScreen({
    super.key,
    this.mnemonicService,
    this.addVault = false,
    this.qrScanOverride,
    this.enigmaDerive,
  });

  @override
  State<ImportMnemonicScreen> createState() => _ImportMnemonicScreenState();
}

class _ImportMnemonicScreenState extends State<ImportMnemonicScreen> {
  /// BIP-39 word counts accepted by the import flow.
  static const Set<int> _validWordCounts = <int>{12, 24};

  /// Maximum number of prefix suggestions shown at once.
  static const int _maxSuggestions = 5;

  final TextEditingController _controller = TextEditingController();
  final TextEditingController _passphraseController = TextEditingController();
  String _wordCount = '0';

  /// Which mode tab is showing in the new-vault flow: 0 imports an existing
  /// phrase, 1 derives one from a riddle + secret. Always 0 for a first-run
  /// import, which has no tabs.
  int _mode = 0;

  /// Secret-phrase inputs, kept here (not in the form) so a tab switch — or
  /// returning from the word review — never loses what the user typed.
  final TextEditingController _riddleController = TextEditingController();
  final TextEditingController _secretController = TextEditingController();
  Bip39WordlistLanguage _enigmaLanguage = Bip39WordlistLanguage.english;

  /// Word total shown by the counter: 12 until the input grows past it.
  int _targetWordCount = 12;
  List<String> _suggestions = const <String>[];
  bool _isValid = false;
  bool _hasChecked = false;
  bool _obscurePassphrase = true;

  @override
  void dispose() {
    _controller.dispose();
    _passphraseController.dispose();
    _riddleController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  /// Splits user input into lowercase, whitespace-separated words.
  List<String> _parseWords(String text) => text
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();

  /// Prefix candidates for the word currently being typed, if any.
  List<String> _suggestionsFor(String text) =>
      bip39InputSuggestions(text, limit: _maxSuggestions);

  /// Parses the input text, counts words, refreshes suggestions, and validates
  /// via CryptoBridge.
  void _onTextChanged(String text) {
    final words = _parseWords(text);
    final validLength = _validWordCounts.contains(words.length);

    setState(() {
      _wordCount = '${words.length}';
      _targetWordCount = words.length > 12 ? 24 : 12;
      _suggestions = _suggestionsFor(text);

      if (validLength) {
        _isValid = widget.mnemonicService!.validateMnemonic(words.join(' '));
        _hasChecked = true;
      } else {
        _isValid = false;
        _hasChecked = words.isNotEmpty;
      }
    });
  }

  /// Completes the in-progress word with [word] and appends a trailing space.
  void _applySuggestion(String word) {
    final text = _controller.text;
    final start = RegExp(r'\S+$').firstMatch(text)?.start ?? text.length;
    final next = '${text.substring(0, start)}$word ';
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _onTextChanged(next);
  }

  /// Pastes clipboard content into the text field.
  void _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data == null || data.text == null) return;

    _controller.text = data.text!;
    _onTextChanged(data.text!);
  }

  /// Scans a recovery-phrase QR code and fills the field with the payload.
  Future<void> _scanQr() async {
    final override = widget.qrScanOverride;
    final raw = override != null
        ? await override()
        : await Navigator.of(context).push<String>(
            MaterialPageRoute<String>(
              builder: (_) => const MnemonicQrScanScreen(),
            ),
          );
    if (!mounted || raw == null) return;

    final words = _parseWords(raw);
    if (!_validWordCounts.contains(words.length)) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.qrScanInvalid)));
      return;
    }

    final mnemonic = words.join(' ');
    _controller.value = TextEditingValue(
      text: mnemonic,
      selection: TextSelection.collapsed(offset: mnemonic.length),
    );
    _onTextChanged(mnemonic);
  }

  /// Clears the text field.
  void _clear() {
    _controller.clear();
    _onTextChanged('');
  }

  /// Leaves the screen: a new-vault import returns to the accounts screen it
  /// was pushed from; a first-run import returns to the welcome screen.
  void _back() {
    if (widget.addVault && context.canPop()) {
      context.pop();
      return;
    }
    context.go(widget.addVault ? '/' : '/welcome');
  }

  /// Hands the derived secret-phrase wallet to the shared word-review step.
  ///
  /// Pushed (not replaced) so the back arrow returns to this screen with the
  /// secret-phrase tab still selected and the riddle intact.
  void _onEnigmaGenerated(EnigmaDerivation derivation) {
    context.push(
      '/enigma-mnemonic',
      extra: <String, Object>{
        'words': derivation.words,
        'language': derivation.language,
        'entropyHex': derivation.entropyHex,
        'riddle': derivation.riddle,
        'secret': derivation.secret,
        'addVault': true,
      },
    );
  }

  /// Navigates to PIN setup with the validated mnemonic.
  void _import() {
    final words = _parseWords(_controller.text);

    if (!_validWordCounts.contains(words.length)) return;

    final mnemonic = words.join(' ');
    if (!widget.mnemonicService!.validateMnemonic(mnemonic)) return;

    context.go(
      '/set-pin',
      extra: {
        'mnemonic': mnemonic,
        'passphrase': _passphraseController.text.trim(),
        'addVault': widget.addVault,
        'source': 'imported',
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
        if (!didPop) _back();
      },
      child: Scaffold(
        // Light follows the neo page tint (pale lime) so the reference grid
        // reads as paper ruling; dark's `groupedBg` equals `bg`, so this only
        // affects light mode.
        backgroundColor: c.groupedBg,
        appBar: neoAppBar(
          c: c,
          // A new vault names itself in the title bar; a first-run import keeps
          // the in-body "Import Wallet" title.
          title: widget.addVault
              ? Text(
                  l10n.newVault,
                  style: TextStyle(color: c.text, fontWeight: FontWeight.w600),
                )
              : null,
          leading: neoBackButton(c, onPressed: _back),
          darkBackground: c.bg,
        ),
        body: GridBackground(
          child: SafeArea(
            child: Column(
              children: [
                // ── Mode tabs (new vault only) ──────────────────────────
                // In place, not a route: importing a phrase and deriving one
                // from a riddle + secret are the two ways to fill a new vault.
                if (widget.addVault) _modeTabs(c, l10n),
                Expanded(
                  child: _mode == 0
                      ? _importPane(c, l10n)
                      : _secretPane(c, l10n),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Switches the new-vault mode tab, dropping focus first so the previous
  /// pane's keyboard does not stay up over the new form.
  void _switchMode(int mode) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_mode != mode) setState(() => _mode = mode);
  }

  /// The import-phrase pane: the scrollable form this screen is named for.
  ///
  /// Scrolls because the on-screen keyboard shrinks the viewport: fixed-height
  /// content would overflow and push the Import button off screen.
  Widget _importPane(ColorTokens c, AppLocalizations l10n) =>
      SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 8),

              // ── Title (first-run import only) ───────────────
              if (!widget.addVault) ...[
                Text(
                  l10n.importMnemonicTitle,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // ── Subtitle ────────────────────────────────────
              Text(
                l10n.importMnemonicHint,
                style: TextStyle(color: c.mutedText(150), fontSize: 14),
              ),

              const SizedBox(height: 28),

              // ── Paste / scan actions ────────────────────────────
              Row(
                children: [
                  Expanded(child: PasteButton(onPressed: _pasteFromClipboard)),
                  const SizedBox(width: 12),
                  Expanded(child: QrScanButton(onPressed: _scanQr)),
                ],
              ),

              // Light gives the neo button's offset shadow room to clear.
              SizedBox(height: c.neobrutalism ? 22 : 18),

              // ── Text input field ─────────────────────────────────
              MnemonicInputField(
                controller: _controller,
                onChanged: _onTextChanged,
                onClear: _clear,
                hasChecked: _hasChecked,
                isValid: _isValid,
              ),

              // ── BIP-39 prefix suggestions ────────────────────────
              if (_suggestions.isNotEmpty) ...[
                const SizedBox(height: 12),
                MnemonicSuggestions(
                  suggestions: _suggestions,
                  onTap: _applySuggestion,
                ),
              ],

              SizedBox(height: c.neobrutalism ? 18 : 14),

              // ── Passphrase field ──────────────────────────────
              PassphraseField(
                controller: _passphraseController,
                obscurePassphrase: _obscurePassphrase,
                onToggleObscure: () {
                  setState(() {
                    _obscurePassphrase = !_obscurePassphrase;
                  });
                },
              ),

              SizedBox(height: c.neobrutalism ? 12 : 8),

              // ── Passphrase info text ──────────────────────────
              Text(
                'A passphrase creates a completely different set of wallets. '
                'Leave empty to use the standard BIP-39 seed.',
                style: TextStyle(color: c.mutedText(100), fontSize: 11),
              ),

              const SizedBox(height: 14),

              // ── Status row: word count + validation ──────────────
              MnemonicStatusRow(
                wordCount: _wordCount,
                targetWordCount: _targetWordCount,
                hasChecked: _hasChecked,
                isValid: _isValid,
              ),

              const SizedBox(height: 16),

              // ── Import button ────────────────────────────────────
              ImportButton(
                key: const Key('import-mnemonic-submit'),
                isValid: _isValid,
                onTap: _import,
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      );

  /// The secret-phrase pane: the same [EnigmaForm] the first-run Enigma screen
  /// renders, shown in place so the tab is a real switch rather than a route.
  Widget _secretPane(ColorTokens c, AppLocalizations l10n) =>
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.enigmaDescription,
              style: TextStyle(
                color: c.mutedText(150),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            EnigmaForm(
              riddleController: _riddleController,
              secretController: _secretController,
              language: _enigmaLanguage,
              onLanguageChanged: (lang) => setState(() {
                _enigmaLanguage = lang;
              }),
              onGenerated: _onEnigmaGenerated,
              derive: widget.enigmaDerive,
            ),
            const SizedBox(height: 24),
          ],
        ),
      );

  /// The mode switch above the panes (new-vault flow only).
  Widget _modeTabs(ColorTokens c, AppLocalizations l10n) => Padding(
    // [TabStrip] reserves the ledge for its shadow, so no extra bottom gap.
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
    child: TabStrip(
      c: c,
      tabs: [
        TabButton(
          key: const Key('add-vault-tab-import'),
          c: c,
          label: l10n.newVaultImportTab,
          selected: _mode == 0,
          onTap: () => _switchMode(0),
        ),
        TabButton(
          key: const Key('add-vault-tab-secret'),
          c: c,
          label: l10n.newVaultSecretTab,
          selected: _mode == 1,
          onTap: () => _switchMode(1),
        ),
      ],
    ),
  );
}
