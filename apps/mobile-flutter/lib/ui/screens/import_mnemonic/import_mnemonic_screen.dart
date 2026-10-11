import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/primary_button.dart';
import '../../../services/mnemonic_service.dart';

/// Free-text import of an existing 12-word BIP-39 mnemonic phrase.
///
/// User types or pastes 12 BIP-39 words (space-separated). The input
/// is validated on every change via [CryptoBridge.validateMnemonic].
/// A valid mnemonic shows a green checkmark and enables the Import
/// button. On successful import, navigates to PIN setup.
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

    context.go('/set-pin', extra: {
      'mnemonic': mnemonic,
      'passphrase': _passphraseController.text.trim(),
      'addVault': widget.addVault,
      'source': 'imported',
    });
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
        backgroundColor: c.bg,
        body: SafeArea(
        // 整页可滚动：键盘弹出时视口被压缩，固定高度的内容放不下会溢出，
        // 导致 Import 按钮被顶出屏幕。改成可滚动后用户可以滑到按钮。
        child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              // ── AppBar area ─────────────────────────────────────
              const SizedBox(height: 12),

              Align(
                alignment: Alignment.centerLeft,
                child:                 GestureDetector(
                  onTap: () => context.go('/welcome'),
                  child: Icon(
                    Icons.arrow_back,
                    color: c.text.withAlpha(160),
                    size: 24,
                  ),
                ),
              ),

              const SizedBox(height: 16),

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
                  color: c.text.withAlpha(150),
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 28),

              // ── Paste from clipboard button ─────────────────────
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('paste-btn'),
                  onPressed: _pasteFromClipboard,
                  icon: Icon(
                    Icons.content_paste,
                    size: 18,
                    color: c.primary,
                  ),
                  label: Text(
                    l10n.pasteFromClipboard,
                    style: TextStyle(
                      color: c.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: c.primary.withAlpha(100)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(R.lg),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // ── Text input field ─────────────────────────────────
              // 固定高度替代 Expanded：外层 SingleChildScrollView 里高度无界，
              // Expanded 会抛异常。
              SizedBox(
                height: 200,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(R.lg),
                    border: Border.all(
                      color: _borderColor(c),
                      width: 1.5,
                    ),
                  ),
                  child: Stack(
                    children: [
                      TextField(
                        key: const Key('mnemonic-input'),
                        controller: _controller,
                        onChanged: _onTextChanged,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 15,
                          height: 1.6,
                          letterSpacing: 0.4,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'word1 word2 word3 ...',
                          hintStyle: TextStyle(
                            color: c.text.withAlpha(80),
                            fontSize: 15,
                          ),
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        autocorrect: false,
                        enableSuggestions: false,
                      ),

                      // Clear button (top-right corner)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _clear,
                          child: Icon(
                            Icons.close,
                            size: 20,
                            color: c.text.withAlpha(100),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // ── Passphrase field ──────────────────────────────
              Container(
                width: double.infinity,
                height: 140,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(R.lg),
                  border: Border.all(
                    color: c.border,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.passphraseOptional,
                      style: TextStyle(
                        color: c.text.withAlpha(150),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: TextField(
                        key: const Key('passphrase-input'),
                        controller: _passphraseController,
                        obscureText: _obscurePassphrase,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Advanced: additional BIP39 passphrase',
                          hintStyle: TextStyle(
                            color: c.text.withAlpha(80),
                            fontSize: 14,
                          ),
                          suffixIcon: GestureDetector(
                            onTap: () {
                              setState(() {
                                _obscurePassphrase = !_obscurePassphrase;
                              });
                            },
                            child: Icon(
                              _obscurePassphrase
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              size: 20,
                              color: c.text.withAlpha(140),
                            ),
                          ),
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        autocorrect: false,
                        enableSuggestions: false,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // ── Passphrase info text ──────────────────────────
              Text(
                'A passphrase creates a completely different set of wallets. '
                'Leave empty to use the standard BIP-39 seed.',
                style: TextStyle(
                  color: c.text.withAlpha(100),
                  fontSize: 11,
                ),
              ),

              const SizedBox(height: 14),

              // ── Status row: word count + validation ──────────────
              Row(
                children: [
                  // Word counter
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(R.sm),
                      border: Border.all(color: c.border.withAlpha(100)),
                    ),
                    child: Text(
                      l10n.wordsCount(int.parse(_wordCount)),
                      style: TextStyle(
                        color: c.text.withAlpha(180),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Validation indicator
                  if (_hasChecked)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isValid ? Icons.check_circle : Icons.cancel,
                          size: 20,
                          color: _isValid ? c.primary : c.error,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isValid ? l10n.validMnemonic : l10n.invalidMnemonic,
                          style: TextStyle(
                            color: _isValid
                                ? c.primary
                                : c.error,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                ],
              ),

              const SizedBox(height: 16),

              // ── Import button ────────────────────────────────────
              PrimaryButton(
                label: l10n.import,
                onTap: _isValid ? _import : null,
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

  /// Returns the border color for the input field based on validation state.
  Color _borderColor(ColorTokens c) {
    if (!_hasChecked) return c.border;
    if (_isValid) return c.primary;
    return c.error;
  }
}
