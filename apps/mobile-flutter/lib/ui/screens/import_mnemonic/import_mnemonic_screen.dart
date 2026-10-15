import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../../../services/mnemonic_service.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/grid_background.dart';
import '../../widgets/common/neo_app_bar.dart';
import '../../widgets/common/neo_back_button.dart';
import 'components/import_button.dart';
import 'components/mnemonic_input_field.dart';
import 'components/mnemonic_status_row.dart';
import 'components/passphrase_field.dart';
import 'components/paste_button.dart';

/// Free-text import of an existing 12-word BIP-39 mnemonic phrase.
///
/// User types or pastes 12 BIP-39 words (space-separated). The input
/// is validated on every change via [CryptoBridge.validateMnemonic].
/// A valid mnemonic shows a green checkmark and enables the Import
/// button. On successful import, navigates to PIN setup.
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

  const ImportMnemonicScreen({
    super.key,
    this.mnemonicService,
    this.addVault = false,
  });

  @override
  State<ImportMnemonicScreen> createState() => _ImportMnemonicScreenState();
}

class _ImportMnemonicScreenState extends State<ImportMnemonicScreen> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _passphraseController = TextEditingController();
  String _wordCount = '0';
  bool _isValid = false;
  bool _hasChecked = false;
  bool _obscurePassphrase = true;

  @override
  void dispose() {
    _controller.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  /// Parses the input text, counts words, and validates via CryptoBridge.
  void _onTextChanged(String text) {
    final trimmed = text.trim().toLowerCase();
    final words = trimmed.isEmpty
        ? <String>[]
        : trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    setState(() {
      _wordCount = '${words.length}';

      if (words.length == 12) {
        _isValid = widget.mnemonicService!.validateMnemonic(words.join(' '));
        _hasChecked = true;
      } else {
        _isValid = false;
        _hasChecked = words.isNotEmpty && words.length != 12;
      }
    });
  }

  /// Pastes clipboard content into the text field.
  void _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data == null || data.text == null) return;

    _controller.text = data.text!;
    _onTextChanged(data.text!);
  }

  /// Clears the text field.
  void _clear() {
    _controller.clear();
    _onTextChanged('');
  }

  /// Navigates to PIN setup with the validated mnemonic.
  void _import() {
    final words = _controller.text
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    if (words.length != 12) return;

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
        if (!didPop) context.go('/welcome');
      },
      child: Scaffold(
        // Light follows the neo page tint (pale lime) so the reference grid
        // reads as paper ruling; dark's `groupedBg` equals `bg`, so this only
        // affects light mode.
        backgroundColor: c.groupedBg,
        appBar: neoAppBar(
          c: c,
          leading: neoBackButton(c, onPressed: () => context.go('/welcome')),
          darkBackground: c.bg,
        ),
        body: GridBackground(
          child: SafeArea(
            // 整页可滚动：键盘弹出时视口被压缩，固定高度的内容放不下会溢出，
            // 导致 Import 按钮被顶出屏幕。改成可滚动后用户可以滑到按钮。
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 8),

                    // ── Title ───────────────────────────────────────────
                    Text(
                      l10n.importMnemonicTitle,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 10),

                    // ── Subtitle ────────────────────────────────────────
                    Text(
                      l10n.importMnemonicHint,
                      style: TextStyle(
                        color: c.mutedText(150),
                        fontSize: 14,
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── Paste from clipboard button ─────────────────────
                    PasteButton(onPressed: _pasteFromClipboard),

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
                      style: TextStyle(
                        color: c.mutedText(100),
                        fontSize: 11,
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ── Status row: word count + validation ──────────────
                    MnemonicStatusRow(
                      wordCount: _wordCount,
                      hasChecked: _hasChecked,
                      isValid: _isValid,
                    ),

                    const SizedBox(height: 16),

                    // ── Import button ────────────────────────────────────
                    ImportButton(isValid: _isValid, onTap: _import),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
