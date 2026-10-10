import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/interfaces/mnemonic_service.dart';
import '../../../core/interfaces/wallet_service.dart';
import '../../../core/models/vault.dart';
import '../../../data/bip39_wordlist.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/mnemonic/mnemonic_word_grid.dart';
import '../../widgets/mnemonic/warning_banner.dart';
import '../../widgets/pin/pin_dot_indicator.dart';
import '../../widgets/pin/pin_number_pad.dart';

/// Secondary-text colour for this screen, tuned per theme so body/value copy
/// clears WCAG AA contrast (4.5:1).
///
/// A single alpha cannot serve both backgrounds: on light, `text` is
/// near-black on white, so the 130–150 alpha used pre-review lands at only
/// ~3.3–4.2:1. Light therefore takes the higher value; dark keeps a lower
/// alpha so secondary copy still reads softer than primary.
Color _secondaryText(ColorTokens c, Brightness brightness) =>
    c.text.withAlpha(brightness == Brightness.dark ? 160 : 190);

/// Stand-in wallet setup and management (ADR-009).
///
/// Reached from Settings → Security in **any** session. A single stateful
/// screen drives both the first-time wizard and the configured status view.
/// Every credential prompt stays inside this route — two-pass PIN entry reuses
/// [PinNumberPad] / [PinDotIndicator] — so no bottom sheet is ever stacked on
/// another; confirmations use plain dialogs.
///
/// Reachable from a stand-in session too: a stand-in may itself configure a
/// stand-in one tier deeper (`depth + 1`), so the wizard nests. Every prompt
/// therefore speaks in terms of the *current* PIN, not a "main" one — from a
/// nested session the credential being re-verified is that session's own PIN.
class StandInScreen extends StatefulWidget {
  /// Wallet lifecycle API — the only service the screen mutates.
  final IWalletService? walletService;

  /// Mnemonic generation / validation for the wizard.
  final IMnemonicService? mnemonicService;

  /// Design-gallery only: open the unconfigured wizard directly on the
  /// mnemonic step (Import / Generate / Enigma tabs) so the tab bar can be
  /// captured without driving a tap. Inert in production (default `false`).
  final bool previewMnemonicStep;

  const StandInScreen({
    super.key,
    this.walletService,
    this.mnemonicService,
    this.previewMnemonicStep = false,
  });

  @override
  State<StandInScreen> createState() => _StandInScreenState();
}

/// Which top-level view the screen is currently showing.
enum _View {
  loading,
  unavailable,
  status,
  intro,
  mnemonic,
  wizardPin,
  wizardMainPin,
  changePin,
  selectMode,
  modePin,
  removePin,
}

class _StandInScreenState extends State<StandInScreen> {
  static const int _pinLength = 6;

  _View _view = _View.loading;

  /// Stored stand-in behaviour mode.
  StandInMode _mode = StandInMode.hide;

  // ── Wizard state ────────────────────────────────────────────────────

  /// Mode chosen in the intro step.
  StandInMode _wizardMode = StandInMode.hide;

  /// 0 = import phrase, 1 = generate phrase, 2 = Enigma (riddle + secret).
  int _mnemonicTab = 0;

  /// Resolved mnemonic for the stand-in vault (set when leaving step 2).
  String? _mnemonic;
  List<String> _generatedWords = const [];
  bool _wordsConfirmed = false;

  final TextEditingController _importController = TextEditingController();
  bool _importValid = false;
  bool _importChecked = false;

  // ── Enigma tab state ────────────────────────────────────────────────

  final TextEditingController _riddleController = TextEditingController();
  final TextEditingController _secretController = TextEditingController();
  bool _obscureSecret = true;

  /// Wordlist used for the riddle → mnemonic derivation (English by default).
  Bip39WordlistLanguage _enigmaLanguage = Bip39WordlistLanguage.english;

  /// Words produced by the last successful Enigma derivation (24 for a
  /// stand-in phrase), empty until the user generates.
  List<String> _enigmaWords = const [];
  bool _enigmaWordsConfirmed = false;
  bool _enigmaGenerating = false;
  String? _enigmaError;

  // ── PIN entry state (shared across every credential prompt) ─────────

  final List<int> _pin = [];
  int _pinPhase = 0;
  String? _firstPin;
  String? _standInPin;
  String? _oldPin;
  String? _pinError;

  /// Target mode for a pending "change behaviour" action.
  StandInMode? _pendingMode;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _importController.dispose();
    _riddleController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  // ── Data loading ────────────────────────────────────────────────────

  Future<void> _load() async {
    final ws = widget.walletService;
    if (ws == null) {
      if (mounted) setState(() => _view = _View.unavailable);
      return;
    }
    final configured = await ws.hasStandIn();
    final mode = await ws.standInMode();
    if (!mounted) return;
    setState(() {
      _mode = mode;
      _wizardMode = mode;
      if (configured) {
        _view = _View.status;
      } else if (widget.previewMnemonicStep) {
        _view = _View.mnemonic;
      } else {
        _view = _View.intro;
      }
    });
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  String _modeName(AppLocalizations l10n, StandInMode mode) =>
      mode == StandInMode.wipe ? l10n.standInModeWipe : l10n.standInModeHide;

  /// Maps the service's [StateError] messages to localized copy.
  String _localizedError(Object error, AppLocalizations l10n) {
    if (error is StateError) {
      switch (error.message) {
        case 'Incorrect PIN':
          return l10n.incorrectPin;
        case 'This action requires a primary session.':
          return l10n.standInPrimaryRequired;
        case 'The stand-in PIN must differ from your main PIN.':
          return l10n.standInPinSameAsMain;
        case 'Stand-in wallet already configured.':
          return l10n.standInAlreadyConfigured;
        case 'No stand-in wallet configured.':
          return l10n.standInNotConfigured;
      }
      return error.message;
    }
    return error.toString();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ── PIN entry ───────────────────────────────────────────────────────

  void _onDigitTap(int digit) {
    if (_pin.length >= _pinLength) return;
    setState(() {
      _pin.add(digit);
      _pinError = null;
    });
    if (_pin.length == _pinLength) _onPinComplete();
  }

  void _onBackspaceTap() {
    if (_pin.isEmpty) return;
    setState(() => _pin.removeLast());
  }

  /// Clears buffers + phase, keeping the current [view]. Call inside setState.
  void _resetPinFields() {
    _pin.clear();
    _pinPhase = 0;
    _firstPin = null;
    _pinError = null;
  }

  void _setPinError(String message) {
    setState(() {
      _pinError = message;
      _pin.clear();
    });
  }

  Future<void> _onPinComplete() async {
    final entered = _pin.join();
    switch (_view) {
      case _View.wizardPin:
        if (_pinPhase == 0) {
          setState(() {
            _firstPin = entered;
            _pinPhase = 1;
            _pin.clear();
          });
        } else if (entered == _firstPin) {
          setState(() {
            _standInPin = entered;
            _view = _View.wizardMainPin;
            _resetPinFields();
          });
        } else {
          setState(() {
            _pinPhase = 0;
            _firstPin = null;
          });
          _setPinError(AppLocalizations.of(context)!.pinMismatch);
        }
      case _View.wizardMainPin:
        await _submitConfigure(entered);
      case _View.changePin:
        await _handleChangePin(entered);
      case _View.modePin:
        await _submitMode(entered);
      case _View.removePin:
        await _submitRemove(entered);
      default:
        break;
    }
  }

  Future<void> _handleChangePin(String entered) async {
    final l10n = AppLocalizations.of(context)!;
    if (_pinPhase == 0) {
      setState(() {
        _oldPin = entered;
        _pinPhase = 1;
        _pin.clear();
      });
    } else if (_pinPhase == 1) {
      setState(() {
        _firstPin = entered;
        _pinPhase = 2;
        _pin.clear();
      });
    } else if (entered == _firstPin) {
      await _submitUpdatePin(_oldPin!, entered);
    } else {
      setState(() {
        _pinPhase = 1;
        _firstPin = null;
      });
      _setPinError(l10n.pinMismatch);
    }
  }

  // ── Service actions ─────────────────────────────────────────────────

  Future<void> _submitConfigure(String mainPin) async {
    final ws = widget.walletService!;
    final l10n = AppLocalizations.of(context)!;
    // Record how the stand-in mnemonic originated (ADR-011 §4): the Enigma tab
    // persists its wordlist, the generate tab is "generated", else "imported".
    final source = switch (_mnemonicTab) {
      2 => VaultSource.enigma,
      1 => VaultSource.generated,
      _ => VaultSource.imported,
    };
    final enigmaLanguage =
        source == VaultSource.enigma ? _enigmaLanguage.index : 0;
    try {
      await ws.configureStandIn(
        _mnemonic!,
        pin: _standInPin!,
        mainPin: mainPin,
        mode: _wizardMode,
        source: source,
        enigmaLanguage: enigmaLanguage,
      );
    } catch (e) {
      if (!mounted) return;
      _setPinError(_localizedError(e, l10n));
      return;
    }
    if (!mounted) return;
    _showSnack(l10n.standInCreated);
    setState(() {
      _mode = _wizardMode;
      _view = _View.status;
      _resetWizard();
    });
  }

  Future<void> _submitUpdatePin(String oldPin, String newPin) async {
    final ws = widget.walletService!;
    final l10n = AppLocalizations.of(context)!;
    try {
      await ws.updateStandInPin(oldPin: oldPin, newPin: newPin);
    } catch (e) {
      if (!mounted) return;
      _setPinError(_localizedError(e, l10n));
      setState(() {
        _pinPhase = 0;
        _firstPin = null;
        _oldPin = null;
      });
      return;
    }
    if (!mounted) return;
    _showSnack(l10n.standInPinUpdated);
    setState(() {
      _view = _View.status;
      _resetPinFields();
    });
  }

  Future<void> _submitMode(String mainPin) async {
    final ws = widget.walletService!;
    final l10n = AppLocalizations.of(context)!;
    final target = _pendingMode ?? _mode;
    try {
      await ws.updateStandInMode(pin: mainPin, mode: target);
    } catch (e) {
      if (!mounted) return;
      _setPinError(_localizedError(e, l10n));
      return;
    }
    if (!mounted) return;
    _showSnack(l10n.standInModeUpdated);
    setState(() {
      _mode = target;
      _pendingMode = null;
      _view = _View.status;
      _resetPinFields();
    });
  }

  Future<void> _submitRemove(String mainPin) async {
    final ws = widget.walletService!;
    final l10n = AppLocalizations.of(context)!;
    try {
      await ws.removeStandIn(pin: mainPin);
    } catch (e) {
      if (!mounted) return;
      _setPinError(_localizedError(e, l10n));
      return;
    }
    if (!mounted) return;
    _showSnack(l10n.standInRemoved);
    setState(() {
      _mode = StandInMode.hide;
      _wizardMode = StandInMode.hide;
      _view = _View.intro;
      _resetWizard();
    });
  }

  void _resetWizard() {
    _resetPinFields();
    _mnemonic = null;
    _generatedWords = const [];
    _wordsConfirmed = false;
    _mnemonicTab = 0;
    _importController.clear();
    _importValid = false;
    _importChecked = false;
    _riddleController.clear();
    _secretController.clear();
    _obscureSecret = true;
    _enigmaLanguage = Bip39WordlistLanguage.english;
    _enigmaWords = const [];
    _enigmaWordsConfirmed = false;
    _enigmaGenerating = false;
    _enigmaError = null;
    _pendingMode = null;
  }

  // ── Navigation between steps ────────────────────────────────────────

  void _onBack() {
    switch (_view) {
      case _View.mnemonic:
        setState(() => _view = _View.intro);
      case _View.wizardPin:
        setState(() {
          _view = _View.mnemonic;
          _resetPinFields();
        });
      case _View.wizardMainPin:
        setState(() {
          _view = _View.wizardPin;
          _resetPinFields();
        });
      case _View.modePin:
        setState(() {
          _view = _View.selectMode;
          _pendingMode = null;
          _resetPinFields();
        });
      case _View.changePin:
      case _View.removePin:
        setState(() {
          _view = _View.status;
          _resetPinFields();
        });
      case _View.selectMode:
        setState(() => _view = _View.status);
      case _View.intro:
      case _View.status:
      case _View.unavailable:
      case _View.loading:
        if (context.canPop()) context.pop();
    }
  }

  // ── Confirmations ───────────────────────────────────────────────────

  Future<bool> _confirmWipe() async {
    final l10n = AppLocalizations.of(context)!;
    final c = _tokens(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(l10n.standInWipeConfirmTitle,
            style: TextStyle(color: c.text)),
        content: Text(
          l10n.standInWipeConfirmBody,
          style: TextStyle(color: c.text.withAlpha(200), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.standInModeWipe, style: TextStyle(color: c.error)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<bool> _confirmRemove() async {
    final l10n = AppLocalizations.of(context)!;
    final c = _tokens(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(l10n.standInRemoveTitle, style: TextStyle(color: c.text)),
        content: Text(
          l10n.standInRemoveConfirm,
          style: TextStyle(color: c.text.withAlpha(200), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.standInRemoveTitle,
                style: TextStyle(color: c.error)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // ── Wizard step handlers ────────────────────────────────────────────

  void _onIntroContinue() {
    setState(() {
      _view = _View.mnemonic;
      _mnemonicTab = 0;
    });
  }

  Future<void> _onWizardModeSelected(StandInMode mode) async {
    if (mode == _wizardMode) return;
    if (mode == StandInMode.wipe && !await _confirmWipe()) return;
    if (!mounted) return;
    setState(() => _wizardMode = mode);
  }

  void _selectMnemonicTab(int index) {
    setState(() {
      _mnemonicTab = index;
      if (index == 1 && _generatedWords.isEmpty) {
        final generated = widget.mnemonicService?.generateMnemonic() ?? '';
        _generatedWords = generated.trim().isEmpty
            ? const []
            : generated.trim().split(RegExp(r'\s+'));
      }
    });
  }

  List<String> _parseWords(String text) => text
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();

  void _onImportChanged(String text) {
    final words = _parseWords(text);
    setState(() {
      _importChecked = words.isNotEmpty;
      _importValid = words.length == 12 &&
          (widget.mnemonicService?.validateMnemonic(words.join(' ')) ?? false);
    });
  }

  void _onImportContinue() {
    final words = _parseWords(_importController.text);
    setState(() {
      _mnemonic = words.join(' ');
      _view = _View.wizardPin;
      _resetPinFields();
    });
  }

  void _onGenerateContinue() {
    setState(() {
      _mnemonic = _generatedWords.join(' ');
      _view = _View.wizardPin;
      _resetPinFields();
    });
  }

  // ── Enigma tab ──────────────────────────────────────────────────────

  /// Localized name for a BIP-39 wordlist, shared with the Enigma flow.
  String _localizedLanguageName(
    AppLocalizations l10n,
    Bip39WordlistLanguage lang,
  ) {
    switch (lang) {
      case Bip39WordlistLanguage.english:
        return l10n.languageEnglish;
      case Bip39WordlistLanguage.chineseSimplified:
        return l10n.languageChinese;
    }
  }

  /// Derives the 24-word phrase from the riddle + secret, then shows the
  /// word grid for confirmation. Failures are surfaced in place (never throws
  /// into the gesture callback).
  Future<void> _onEnigmaGenerate() async {
    final svc = widget.mnemonicService;
    if (svc == null) return;
    final l10n = AppLocalizations.of(context)!;
    final riddle = _riddleController.text.trim();
    final secret = _secretController.text.trim();
    if (riddle.isEmpty || secret.isEmpty || _enigmaGenerating) return;

    setState(() {
      _enigmaGenerating = true;
      _enigmaError = null;
    });

    // Brief delay to surface the processing state, mirroring the main
    // wallet's Enigma screen.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    try {
      final words = svc.generateEnigmaMnemonic(
        riddle,
        secret,
        language: _enigmaLanguage.index,
      );
      if (!mounted) return;
      setState(() {
        _enigmaGenerating = false;
        _enigmaWords = words;
        _enigmaWordsConfirmed = false;
        _enigmaError = words.isEmpty ? l10n.noMnemonicGenerated : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _enigmaGenerating = false;
        _enigmaError = l10n.noMnemonicGenerated;
      });
    }
  }

  void _onEnigmaContinue() {
    setState(() {
      _mnemonic = _enigmaWords.join(' ');
      _view = _View.wizardPin;
      _resetPinFields();
    });
  }

  // ── Status actions ──────────────────────────────────────────────────

  void _openChangePin() => setState(() {
        _view = _View.changePin;
        _resetPinFields();
      });

  void _openSelectMode() => setState(() => _view = _View.selectMode);

  Future<void> _openRemove() async {
    if (!await _confirmRemove()) return;
    if (!mounted) return;
    setState(() {
      _view = _View.removePin;
      _resetPinFields();
    });
  }

  Future<void> _onManageModeSelected(StandInMode mode) async {
    if (mode == _mode) return;
    if (mode == StandInMode.wipe && !await _confirmWipe()) return;
    if (!mounted) return;
    setState(() {
      _pendingMode = mode;
      _view = _View.modePin;
      _resetPinFields();
    });
  }

  // ── Build ───────────────────────────────────────────────────────────

  static ColorTokens _tokens(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? ColorTokens.dark
          : ColorTokens.light;

  @override
  Widget build(BuildContext context) {
    final c = _tokens(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      // Tinted grouped background so surface cards stay distinct in light
      // mode too (bg == surface == #FFFFFF would erase every card edge).
      backgroundColor: c.groupedBg,
      appBar: AppBar(
        backgroundColor: c.groupedBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.text),
          onPressed: _onBack,
        ),
        title: Text(
          l10n.standInTitle,
          style: TextStyle(color: c.text, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(child: _buildBody(c, l10n)),
    );
  }

  Widget _buildBody(ColorTokens c, AppLocalizations l10n) {
    switch (_view) {
      case _View.loading:
        return Center(child: CircularProgressIndicator(color: c.primary));
      case _View.unavailable:
        return _buildUnavailable(c, l10n);
      case _View.status:
        return _buildStatus(c, l10n);
      case _View.intro:
        return _buildIntro(c, l10n);
      case _View.mnemonic:
        return _buildMnemonic(c, l10n);
      case _View.selectMode:
        return _buildSelectMode(c, l10n);
      case _View.wizardPin:
      case _View.wizardMainPin:
      case _View.changePin:
      case _View.modePin:
      case _View.removePin:
        return _buildPin(c, l10n);
    }
  }

  Widget _buildUnavailable(ColorTokens c, AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: c.text.withAlpha(120)),
            const SizedBox(height: 16),
            Text(
              l10n.standInUnavailable,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _secondaryText(c, Theme.of(context).brightness),
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Status view ─────────────────────────────────────────────────────

  Widget _buildStatus(ColorTokens c, AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(R.lg),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(R.lg),
                ),
                child: Icon(Icons.shield_outlined, color: c.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.standInConfigured,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${l10n.standInCurrentModeLabel}: '
                      '${_modeName(l10n, _mode)}',
                      style: TextStyle(
                        color: _secondaryText(c, Theme.of(context).brightness),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Actions share one inset card with hairline dividers — the same
        // grouped language as the Settings list, not three floating cards.
        _ActionGroup(
          c: c,
          rows: [
            _ActionRow(
              key: const ValueKey('standin-action-change-pin'),
              c: c,
              icon: Icons.lock_outline,
              label: l10n.standInChangePinTitle,
              onTap: _openChangePin,
            ),
            _ActionRow(
              key: const ValueKey('standin-action-change-mode'),
              c: c,
              icon: Icons.tune,
              label: l10n.standInChangeModeTitle,
              value: _modeName(l10n, _mode),
              onTap: _openSelectMode,
            ),
            _ActionRow(
              key: const ValueKey('standin-action-remove'),
              c: c,
              icon: Icons.delete_outline,
              label: l10n.standInRemoveTitle,
              destructive: true,
              onTap: _openRemove,
            ),
          ],
        ),
      ],
    );
  }

  // ── Intro (threat model + mode) ─────────────────────────────────────

  Widget _buildIntro(ColorTokens c, AppLocalizations l10n) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            children: [
              Text(
                l10n.standInThreatTitle,
                style: TextStyle(
                  color: c.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.standInThreatBody,
                style: TextStyle(
                  color: _secondaryText(c, Theme.of(context).brightness),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 26),
              _SectionTitle(c: c, title: l10n.standInModeSectionTitle),
              const SizedBox(height: 10),
              _OptionCard(
                key: const ValueKey('standin-mode-hide'),
                c: c,
                title: l10n.standInModeHide,
                description: l10n.standInModeHideDesc,
                selected: _wizardMode == StandInMode.hide,
                onTap: () => _onWizardModeSelected(StandInMode.hide),
              ),
              const SizedBox(height: 10),
              _OptionCard(
                key: const ValueKey('standin-mode-wipe'),
                c: c,
                title: l10n.standInModeWipe,
                description: l10n.standInModeWipeDesc,
                selected: _wizardMode == StandInMode.wipe,
                danger: true,
                onTap: () => _onWizardModeSelected(StandInMode.wipe),
              ),
            ],
          ),
        ),
        // Pinned action area — the CTA sits at the bottom safe edge instead
        // of floating mid-page with a dead half-screen beneath it.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: PrimaryButton(
            key: const Key('standin-intro-continue'),
            label: l10n.continueButton,
            onTap: _onIntroContinue,
          ),
        ),
      ],
    );
  }

  // ── Mnemonic step ───────────────────────────────────────────────────

  Widget _buildMnemonic(ColorTokens c, AppLocalizations l10n) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            children: [
              _TabButton(
                key: const ValueKey('standin-tab-import'),
                c: c,
                label: l10n.standInImportTab,
                selected: _mnemonicTab == 0,
                onTap: () => _selectMnemonicTab(0),
              ),
              const SizedBox(width: 8),
              _TabButton(
                key: const ValueKey('standin-tab-generate'),
                c: c,
                label: l10n.standInGenerateTab,
                selected: _mnemonicTab == 1,
                onTap: () => _selectMnemonicTab(1),
              ),
              const SizedBox(width: 8),
              _TabButton(
                key: const ValueKey('standin-tab-enigma'),
                c: c,
                label: l10n.standInEnigmaTab,
                selected: _mnemonicTab == 2,
                onTap: () => _selectMnemonicTab(2),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (_mnemonicTab) {
            1 => _buildGenerateTab(c, l10n),
            2 => _buildEnigmaTab(c, l10n),
            _ => _buildImportTab(c, l10n),
          },
        ),
      ],
    );
  }

  Widget _buildImportTab(ColorTokens c, AppLocalizations l10n) {
    final secondary = _secondaryText(c, Theme.of(context).brightness);
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.standInCreateTitle,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.importMnemonicHint,
                  style: TextStyle(color: secondary, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(R.lg),
                    border: Border.all(
                      color: !_importChecked
                          ? c.border
                          : (_importValid ? c.primary : c.error),
                      width: 1.5,
                    ),
                  ),
                  child: TextField(
                    key: const Key('standin-mnemonic-input'),
                    controller: _importController,
                    onChanged: _onImportChanged,
                    maxLines: null,
                    style: TextStyle(color: c.text, fontSize: 15, height: 1.6),
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
                    autocorrect: false,
                    enableSuggestions: false,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      '${_parseWords(_importController.text).length} / 12',
                      style: TextStyle(color: secondary, fontSize: 13),
                    ),
                    const Spacer(),
                    if (_importChecked)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _importValid ? Icons.check_circle : Icons.cancel,
                            size: 18,
                            color: _importValid ? c.primary : c.error,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _importValid
                                ? l10n.validMnemonic
                                : l10n.invalidMnemonic,
                            style: TextStyle(
                              color: _importValid ? c.primary : c.error,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: PrimaryButton(
            key: const Key('standin-import-continue'),
            label: l10n.continueButton,
            onTap: _importValid ? _onImportContinue : null,
          ),
        ),
      ],
    );
  }

  Widget _buildGenerateTab(ColorTokens c, AppLocalizations l10n) {
    final secondary = _secondaryText(c, Theme.of(context).brightness);
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.standInCreateTitle,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                WarningBanner(message: l10n.generateMnemonicWarning),
                const SizedBox(height: 18),
                if (_generatedWords.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      l10n.noMnemonicGenerated,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: secondary, fontSize: 13),
                    ),
                  )
                else
                  MnemonicWordGrid(words: _generatedWords, columns: 3),
                const SizedBox(height: 20),
                _CheckRow(
                  key: const ValueKey('standin-written-down'),
                  c: c,
                  label: l10n.iveWrittenItDown,
                  checked: _wordsConfirmed,
                  onTap: () =>
                      setState(() => _wordsConfirmed = !_wordsConfirmed),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: PrimaryButton(
            key: const Key('standin-generate-continue'),
            label: l10n.continueButton,
            onTap: _wordsConfirmed ? _onGenerateContinue : null,
          ),
        ),
      ],
    );
  }

  /// Enigma tab — riddle + secret key derive a deterministic 24-word phrase.
  ///
  /// Mirrors the main wallet's Enigma screen (multiline riddle, wordlist
  /// picker, masked secret with a reveal toggle, tip copy). Before generation
  /// the pinned CTA derives the phrase; afterwards the grid + "I've written it
  /// down" gate the continue action, exactly like the generate tab.
  Widget _buildEnigmaTab(ColorTokens c, AppLocalizations l10n) {
    final secondary = _secondaryText(c, Theme.of(context).brightness);
    final canGenerate = _riddleController.text.trim().isNotEmpty &&
        _secretController.text.trim().isNotEmpty;
    final generated = _enigmaWords.isNotEmpty;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.standInCreateTitle,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.enigmaDescription,
                  style: TextStyle(color: secondary, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 18),
                if (generated) ...[
                  WarningBanner(message: l10n.generateMnemonicWarning),
                  const SizedBox(height: 18),
                  MnemonicWordGrid(
                    words: _enigmaWords,
                    columns: 4,
                    fontSize: 12,
                    childAspectRatio: 2.0,
                    cellSpacing: 6.0,
                  ),
                  const SizedBox(height: 20),
                  _CheckRow(
                    key: const ValueKey('standin-enigma-written-down'),
                    c: c,
                    label: l10n.iveWrittenItDown,
                    checked: _enigmaWordsConfirmed,
                    onTap: () => setState(
                        () => _enigmaWordsConfirmed = !_enigmaWordsConfirmed),
                  ),
                ] else ...[
                  _fieldLabel(c, l10n.yourRiddle),
                  const SizedBox(height: 8),
                  _enigmaField(
                    c: c,
                    controller: _riddleController,
                    fieldKey: const Key('standin-enigma-riddle'),
                    hint: l10n.enterMemorablePhrase,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 20),
                  _fieldLabel(c, l10n.mnemonicLanguage),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(R.lg),
                      border: Border.all(color: c.border),
                    ),
                    child: DropdownButton<Bip39WordlistLanguage>(
                      key: const ValueKey('standin-enigma-language'),
                      value: _enigmaLanguage,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      dropdownColor: c.surface,
                      style: TextStyle(color: c.text, fontSize: 15),
                      icon: Icon(Icons.arrow_drop_down,
                          color: c.text.withAlpha(120)),
                      items: Bip39WordlistLanguage.values.map((lang) {
                        return DropdownMenuItem(
                          value: lang,
                          child: Text(_localizedLanguageName(l10n, lang)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _enigmaLanguage = value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  _fieldLabel(c, l10n.secretKey),
                  const SizedBox(height: 8),
                  _enigmaField(
                    c: c,
                    controller: _secretController,
                    fieldKey: const Key('standin-enigma-secret'),
                    hint: l10n.enterSecretKey,
                    obscure: _obscureSecret,
                    suffix: IconButton(
                      key: const ValueKey('standin-enigma-secret-toggle'),
                      icon: Icon(
                        _obscureSecret ? Icons.visibility_off : Icons.visibility,
                        color: c.text.withAlpha(150),
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscureSecret = !_obscureSecret),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.tipLongUnique,
                    style: TextStyle(
                      color: c.text.withAlpha(100),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  if (_enigmaError != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _enigmaError!,
                      style: TextStyle(color: c.error, fontSize: 13),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: generated
              ? PrimaryButton(
                  key: const Key('standin-enigma-continue'),
                  label: l10n.continueButton,
                  onTap: _enigmaWordsConfirmed ? _onEnigmaContinue : null,
                )
              : PrimaryButton(
                  key: const Key('standin-enigma-generate'),
                  label: l10n.generateWallet,
                  loading: _enigmaGenerating,
                  onTap: canGenerate && !_enigmaGenerating
                      ? _onEnigmaGenerate
                      : null,
                ),
        ),
      ],
    );
  }

  /// Field label used inside the Enigma tab (matches the main Enigma screen).
  Widget _fieldLabel(ColorTokens c, String text) => Text(
        text,
        style: TextStyle(
          color: c.text.withAlpha(200),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      );

  /// Surface-filled text field shared by the Enigma tab's riddle + secret.
  Widget _enigmaField({
    required ColorTokens c,
    required TextEditingController controller,
    required Key fieldKey,
    required String hint,
    int maxLines = 1,
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextField(
      key: fieldKey,
      controller: controller,
      maxLines: obscure ? 1 : maxLines,
      obscureText: obscure,
      style: TextStyle(color: c.text, fontSize: 15),
      // Rebuild so the generate CTA tracks the field contents; also clears a
      // previous failure as soon as the user edits the inputs.
      onChanged: (_) => setState(() => _enigmaError = null),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: c.text.withAlpha(100), fontSize: 14),
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.all(16),
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.lg),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.lg),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.lg),
          borderSide: BorderSide(color: c.primary, width: 1.5),
        ),
      ),
      // Only the masked secret key disables suggestions/autocorrect — that is
      // what legitimately triggers the IME's secure mode on some ROMs. The
      // riddle stays a plain text field so the normal keyboard is shown
      // (matching the main Enigma screen).
      autocorrect: !obscure,
      enableSuggestions: !obscure,
    );
  }

  // ── Mode selection (configured) ─────────────────────────────────────

  Widget _buildSelectMode(ColorTokens c, AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        _SectionTitle(c: c, title: l10n.standInModeSectionTitle),
        const SizedBox(height: 12),
        _OptionCard(
          key: const ValueKey('standin-mode-hide'),
          c: c,
          title: l10n.standInModeHide,
          description: l10n.standInModeHideDesc,
          selected: _mode == StandInMode.hide,
          onTap: () => _onManageModeSelected(StandInMode.hide),
        ),
        const SizedBox(height: 10),
        _OptionCard(
          key: const ValueKey('standin-mode-wipe'),
          c: c,
          title: l10n.standInModeWipe,
          description: l10n.standInModeWipeDesc,
          selected: _mode == StandInMode.wipe,
          danger: true,
          onTap: () => _onManageModeSelected(StandInMode.wipe),
        ),
      ],
    );
  }

  // ── PIN prompt ──────────────────────────────────────────────────────

  (String, String) _pinLabels(AppLocalizations l10n) {
    switch (_view) {
      case _View.wizardPin:
        return _pinPhase == 0
            ? (l10n.standInPinTitle, l10n.standInPinSubtitle)
            : (l10n.standInPinConfirmTitle, l10n.standInPinSubtitle);
      case _View.changePin:
        return switch (_pinPhase) {
          0 => (l10n.standInCurrentPinTitle, ''),
          1 => (l10n.standInNewPinTitle, l10n.standInPinSubtitle),
          _ => (l10n.standInNewPinConfirmTitle, ''),
        };
      case _View.wizardMainPin:
      case _View.modePin:
      case _View.removePin:
        return (l10n.standInMainPinTitle, l10n.standInMainPinSubtitle);
      default:
        return (l10n.standInTitle, '');
    }
  }

  Widget _buildPin(ColorTokens c, AppLocalizations l10n) {
    final (title, subtitle) = _pinLabels(l10n);
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 56,
                color: c.primary.withAlpha(120),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _secondaryText(c, Theme.of(context).brightness),
                    fontSize: 14,
                  ),
                ),
              ],
              const SizedBox(height: 26),
              PinDotIndicator(length: _pinLength, filledCount: _pin.length),
              if (_pinError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _pinError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.error, fontSize: 14),
                ),
              ],
              const SizedBox(height: 28),
              PinNumberPad(
                onDigit: _onDigitTap,
                onBackspace: _onBackspaceTap,
                keyPrefix: 'standin-pin',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Shared pieces
// ═══════════════════════════════════════════════════════════════════════

/// A selectable mode card: title + description with a leading check.
class _OptionCard extends StatelessWidget {
  final ColorTokens c;
  final String title;
  final String description;
  final bool selected;
  final bool danger;
  final VoidCallback onTap;

  const _OptionCard({
    super.key,
    required this.c,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = danger ? c.error : c.primary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          // A 40 alpha fill reads as brighter than the neutral surface in
          // dark and as a soft tint over the grouped bg in light — the
          // border alone was doing all the work at 20.
          color: selected ? accent.withAlpha(40) : c.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(
            color: selected ? accent : c.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? accent : Colors.transparent,
                border: Border.all(
                  color: selected ? accent : c.border,
                  width: 2,
                ),
              ),
              child: selected
                  ? Icon(Icons.check, size: 14, color: c.onPrimary)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: _secondaryText(c, Theme.of(context).brightness),
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The section label above a group of [_OptionCard]s — one style shared by
/// the intro (wizard) and the configured mode picker.
class _SectionTitle extends StatelessWidget {
  final ColorTokens c;
  final String title;

  const _SectionTitle({required this.c, required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: _secondaryText(c, Theme.of(context).brightness),
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// One inset surface card holding tappable [rows] separated by indented
/// hairlines — the same grouped language as the Settings list.
class _ActionGroup extends StatelessWidget {
  final ColorTokens c;
  final List<Widget> rows;

  const _ActionGroup({required this.c, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(R.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              Divider(
                height: 1,
                thickness: 0.5,
                // Align the divider with the title text (after the icon).
                indent: 54,
                color: c.border.withAlpha(140),
              ),
          ],
        ],
      ),
    );
  }
}

/// A tappable row inside an [_ActionGroup] — matches the Settings row
/// metrics (24px icon, 17pt title, hairline-divided) instead of the old
/// standalone card per action.
class _ActionRow extends StatelessWidget {
  final ColorTokens c;
  final IconData icon;
  final String label;
  final String? value;
  final bool destructive;
  final VoidCallback onTap;

  const _ActionRow({
    super.key,
    required this.c,
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = destructive ? c.error : c.text;
    final secondary = _secondaryText(c, Theme.of(context).brightness);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Icon(
              icon,
              size: 24,
              color: destructive ? c.error : c.text.withAlpha(160),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 17,
                fontWeight: FontWeight.w400,
              ),
            ),
            if (value != null)
              Expanded(
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: secondary, fontSize: 17),
                ),
              )
            else
              const Spacer(),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: c.text.withAlpha(80),
            ),
          ],
        ),
      ),
    );
  }
}

/// A pill-shaped tab selector for the mnemonic step.
class _TabButton extends StatelessWidget {
  final ColorTokens c;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({
    super.key,
    required this.c,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? c.primary : c.surface,
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: selected ? c.primary : c.border),
          ),
          alignment: Alignment.center,
          // Three tabs share one 390pt row; CJK labels are wide, so the text
          // scales down rather than overflowing on narrow devices.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                color: selected ? c.onPrimary : c.text.withAlpha(190),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A confirmation checkbox row (mirrors the mnemonic "I've written it down").
class _CheckRow extends StatelessWidget {
  final ColorTokens c;
  final String label;
  final bool checked;
  final VoidCallback onTap;

  const _CheckRow({
    super.key,
    required this.c,
    required this.label,
    required this.checked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: c.border.withAlpha(100)),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.sm),
                border: Border.all(
                  color: checked ? c.primary : c.border,
                  width: 2,
                ),
                color: checked ? c.primary : Colors.transparent,
              ),
              child: checked
                  ? Icon(Icons.check, size: 16, color: c.onPrimary)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: c.text.withAlpha(200), fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
