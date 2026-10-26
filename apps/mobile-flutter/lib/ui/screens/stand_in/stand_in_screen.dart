import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/interfaces/mnemonic_service.dart';
import '../../../core/interfaces/wallet_service.dart';
import '../../../core/models/vault.dart';
import '../../../data/bip39_english.dart';
import '../../../data/bip39_wordlist.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/grid_background.dart';
import '../../widgets/common/neo_app_bar.dart';
import '../../widgets/common/neo_back_button.dart';
import '../import_mnemonic/qr_scan_screen.dart';
import 'views/enigma_tab.dart';
import 'views/generate_tab.dart';
import 'views/import_tab.dart';
import 'views/intro_view.dart';
import 'views/mnemonic_view.dart';
import 'views/pin_view.dart';
import 'views/select_mode_view.dart';
import 'views/status_view.dart';
import 'views/unavailable_view.dart';

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
///
/// This file owns the state machine, the async service calls and the build
/// dispatch only; each view and shared block lives under `views/` and
/// `components/`.
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

  /// BIP-39 word counts accepted by the import tab (mirrors `/import`).
  static const Set<int> _validImportWordCounts = <int>{12, 24};

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
  List<String> _importSuggestions = const <String>[];

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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
    final enigmaLanguage = source == VaultSource.enigma
        ? bip39LanguageCode(_enigmaLanguage)
        : 0;
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
    _importSuggestions = const <String>[];
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
        title: Text(
          l10n.standInWipeConfirmTitle,
          style: TextStyle(color: c.text),
        ),
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
            child: Text(
              l10n.standInRemoveTitle,
              style: TextStyle(color: c.error),
            ),
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
      _importSuggestions = bip39InputSuggestions(text);
      _importValid =
          _validImportWordCounts.contains(words.length) &&
          (widget.mnemonicService?.validateMnemonic(words.join(' ')) ?? false);
    });
  }

  /// Completes the in-progress word with [word] and appends a trailing space.
  void _applyImportSuggestion(String word) {
    final text = _importController.text;
    final start = RegExp(r'\S+$').firstMatch(text)?.start ?? text.length;
    final next = '${text.substring(0, start)}$word ';
    _importController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _onImportChanged(next);
  }

  /// Fills the import field from a scanned recovery-phrase QR code.
  Future<void> _scanImportQr() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const MnemonicQrScanScreen()),
    );
    if (!mounted || raw == null) return;

    final words = _parseWords(raw);
    if (!_validImportWordCounts.contains(words.length)) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.qrScanInvalid)));
      return;
    }

    final mnemonic = words.join(' ');
    _importController.value = TextEditingValue(
      text: mnemonic,
      selection: TextSelection.collapsed(offset: mnemonic.length),
    );
    _onImportChanged(mnemonic);
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
        language: bip39LanguageCode(_enigmaLanguage),
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
      appBar: neoAppBar(
        c: c,
        title: Text(
          l10n.standInTitle,
          style: TextStyle(color: c.text, fontWeight: FontWeight.w600),
        ),
        leading: neoBackButton(c, onPressed: _onBack),
        darkBackground: c.groupedBg,
      ),
      // Light mode paints the neobrutalist reference grid behind the body;
      // GridBackground is a no-op in dark, so its chrome is unchanged.
      body: GridBackground(child: SafeArea(child: _buildBody(c, l10n))),
    );
  }

  Widget _buildBody(ColorTokens c, AppLocalizations l10n) {
    switch (_view) {
      case _View.loading:
        return Center(child: CircularProgressIndicator(color: c.primary));
      case _View.unavailable:
        return UnavailableView(c: c, l10n: l10n);
      case _View.status:
        return StatusView(
          c: c,
          l10n: l10n,
          modeName: _modeName(l10n, _mode),
          onChangePin: _openChangePin,
          onChangeMode: _openSelectMode,
          onRemove: _openRemove,
        );
      case _View.intro:
        return IntroView(
          c: c,
          l10n: l10n,
          wizardMode: _wizardMode,
          onModeSelected: _onWizardModeSelected,
          onContinue: _onIntroContinue,
        );
      case _View.mnemonic:
        return MnemonicView(
          c: c,
          l10n: l10n,
          selectedTab: _mnemonicTab,
          onTabSelected: _selectMnemonicTab,
          body: _buildMnemonicTabBody(c, l10n),
        );
      case _View.selectMode:
        return SelectModeView(
          c: c,
          l10n: l10n,
          mode: _mode,
          onModeSelected: _onManageModeSelected,
        );
      case _View.wizardPin:
      case _View.wizardMainPin:
      case _View.changePin:
      case _View.modePin:
      case _View.removePin:
        final (title, subtitle) = _pinLabels(l10n);
        return PinView(
          c: c,
          title: title,
          subtitle: subtitle,
          pinLength: _pinLength,
          filledCount: _pin.length,
          pinError: _pinError,
          onDigit: _onDigitTap,
          onBackspace: _onBackspaceTap,
        );
    }
  }

  /// Assembles the selected mnemonic-step tab; the tab bar chrome lives in
  /// [MnemonicView], which receives this as its body.
  Widget _buildMnemonicTabBody(ColorTokens c, AppLocalizations l10n) {
    return switch (_mnemonicTab) {
      1 => GenerateTab(
        c: c,
        l10n: l10n,
        words: _generatedWords,
        confirmed: _wordsConfirmed,
        onToggleConfirmed: () =>
            setState(() => _wordsConfirmed = !_wordsConfirmed),
        onContinue: _onGenerateContinue,
      ),
      2 => EnigmaTab(
        c: c,
        l10n: l10n,
        riddleController: _riddleController,
        secretController: _secretController,
        words: _enigmaWords,
        wordsConfirmed: _enigmaWordsConfirmed,
        generating: _enigmaGenerating,
        error: _enigmaError,
        obscureSecret: _obscureSecret,
        language: _enigmaLanguage,
        onFieldChanged: () => setState(() => _enigmaError = null),
        onObscureToggled: () =>
            setState(() => _obscureSecret = !_obscureSecret),
        onLanguageChanged: (value) => setState(() => _enigmaLanguage = value),
        onToggleConfirmed: () =>
            setState(() => _enigmaWordsConfirmed = !_enigmaWordsConfirmed),
        onGenerate: _onEnigmaGenerate,
        onContinue: _onEnigmaContinue,
      ),
      _ => ImportTab(
        c: c,
        l10n: l10n,
        controller: _importController,
        checked: _importChecked,
        valid: _importValid,
        wordCount: _parseWords(_importController.text).length,
        suggestions: _importSuggestions,
        onChanged: _onImportChanged,
        onSuggestionTap: _applyImportSuggestion,
        onScan: _scanImportQr,
        onContinue: _onImportContinue,
      ),
    };
  }

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
}
