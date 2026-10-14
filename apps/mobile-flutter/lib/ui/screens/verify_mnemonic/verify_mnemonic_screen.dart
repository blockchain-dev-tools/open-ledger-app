import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/common/grid_background.dart';
import '../../widgets/common/neo_app_bar.dart';
import '../../widgets/common/neo_card.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BIP-39 English wordlist subset (200 words) used for distractor choices.
// Full list: 2048 words. This subset covers diverse letters for realism.
// ─────────────────────────────────────────────────────────────────────────────
const List<String> _bip39WordSubset = [
  'abandon', 'ability', 'able', 'about', 'above', 'absent', 'absorb',
  'abstract', 'absurd', 'abuse', 'access', 'accident', 'account', 'accuse',
  'achieve', 'acid', 'acoustic', 'acquire', 'across', 'act', 'action',
  'actor', 'actual', 'adapt', 'add', 'addict', 'address', 'adjust', 'admit',
  'adult', 'advance', 'advice', 'aerobic', 'affair', 'afford', 'afraid',
  'again', 'age', 'agent', 'agree', 'ahead', 'aim', 'air', 'airport',
  'aisle', 'alarm', 'album', 'alcohol', 'alert', 'alien', 'all', 'alley',
  'allow', 'almost', 'alone', 'alpha', 'already', 'also', 'alter', 'always',
  'amateur', 'amazing', 'among', 'amount', 'amused', 'analyst', 'anchor',
  'ancient', 'anger', 'angle', 'angry', 'animal', 'ankle', 'announce',
  'annual', 'another', 'answer', 'antenna', 'antique', 'anxiety', 'any',
  'apart', 'apology', 'appear', 'apple', 'approve', 'april', 'arch',
  'arctic', 'area', 'arena', 'argue', 'arm', 'armed', 'armor', 'army',
  'around', 'arrange', 'arrest', 'arrive', 'arrow', 'art', 'artefact',
  'artist', 'artwork', 'ask', 'aspect', 'assault', 'asset', 'assist',
  'assume', 'asthma', 'athlete', 'atom', 'attack', 'attend', 'attitude',
  'attract', 'auction', 'audit', 'august', 'aunt', 'author', 'auto',
  'autumn', 'average', 'avocado', 'avoid', 'awake', 'aware', 'away',
  'awesome', 'awful', 'awkward', 'axis', 'baby', 'bachelor', 'bacon',
  'badge', 'bag', 'balance', 'balcony', 'ball', 'bamboo', 'banana',
  'banner', 'bar', 'barely', 'bargain', 'barrel', 'base', 'basic',
  'basket', 'battle', 'beach', 'bean', 'beauty', 'because', 'become',
  'beef', 'before', 'begin', 'behave', 'behind', 'believe', 'below',
  'belt', 'bench', 'benefit', 'best', 'betray', 'better', 'between',
  'beyond', 'bicycle', 'bid', 'bike', 'bind', 'biology', 'bird',
  'birth', 'bitter', 'black', 'blade', 'blame', 'blanket', 'blast',
  'bleak', 'bless', 'blind', 'blood', 'blossom', 'blouse', 'blue',
  'blur', 'blush', 'board', 'boat', 'body', 'boil', 'bomb', 'bone',
  'bonus', 'book', 'boost', 'border', 'boring', 'borrow', 'boss',
  'bottom', 'bounce', 'box', 'boy', 'bracket', 'brain', 'brand',
  'brass', 'brave', 'bread', 'breeze', 'brick', 'bridge', 'brief',
  'bright', 'bring', 'brisk', 'broccoli', 'broken', 'bronze', 'broom',
  'brother', 'brown', 'brush', 'bubble', 'buddy', 'budget', 'buffalo',
  'build', 'bulb', 'bulk', 'bullet', 'bundle', 'bunker', 'burden',
  'burger', 'burst', 'bus', 'business', 'busy', 'butter', 'buyer',
  'buzz', 'cabbage', 'cabin', 'cable',
];

/// Quiz the user on specific mnemonic word positions to verify they have
/// recorded the recovery phrase correctly.
///
/// Asks for words at positions 3, 7, and 11 (4-choice each). Incorrect
/// answers increment an error counter but the user can retry until
/// correct. All 3 must be answered correctly to proceed.
///
/// Accepts [mnemonic] as a space-separated string of 12 BIP-39 words.
///
/// Ported from the original TypeScript implementation.
class VerifyMnemonicScreen extends StatefulWidget {
  /// The full creation data map holding mnemonic (and optional passphrase).
  final Map<String, String> creationData;

  /// The 12-word BIP-39 mnemonic phrase to verify.
  String get mnemonic => creationData['mnemonic']!;

  /// Optional BIP-39 passphrase.
  String get passphrase => creationData['passphrase'] ?? '';

  const VerifyMnemonicScreen({super.key, required this.creationData});

  @override
  State<VerifyMnemonicScreen> createState() => _VerifyMnemonicScreenState();
}

class _VerifyMnemonicScreenState extends State<VerifyMnemonicScreen> {
  static const List<int> _quizPositions = [3, 7, 11];

  final Random _random = Random();
  late List<String> _words;
  late List<int> _remainingPositions;
  int _currentQuizIndex = 0;
  List<String> _currentChoices = [];
  String? _feedbackText;
  bool _feedbackCorrect = false;

  @override
  void initState() {
    super.initState();
    _words = widget.mnemonic.split(' ');
    _remainingPositions = List.from(_quizPositions)..shuffle(_random);
    _loadQuiz();
  }

  int get _currentPosition => _remainingPositions.first;

  /// Picks 4 choices: the correct word + 3 random distractors, shuffled.
  void _loadQuiz() {
    final correctWord = _words[_currentPosition - 1]; // 0-indexed

    // Build distractor pool: BIP-39 word subset excluding the correct word.
    final distractorPool = _bip39WordSubset
        .where((w) => w != correctWord)
        .toList();
    distractorPool.shuffle(_random);

    final distractors = distractorPool.take(3).toList();

    _currentChoices = [correctWord, ...distractors]..shuffle(_random);
    _feedbackText = null;
    _feedbackCorrect = false;
  }

  /// Handles a choice tap. Correct → advance to next quiz or finish.
  /// Incorrect → show error feedback, allow retry.
  void _onChoiceTap(String choice) {
    final correctWord = _words[_currentPosition - 1];

    if (choice == correctWord) {
      setState(() {
        _feedbackText = AppLocalizations.of(context)!.correct;
        _feedbackCorrect = true;
      });

      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;

        // 最后一题答对：直接跳转，**不要**清空 _remainingPositions。
        // 一旦清空，`_currentPosition`（= _remainingPositions.first）在本页的
        // 退出转场帧里会读到空列表，抛 `Bad state: No element`。
        if (_remainingPositions.length <= 1) {
          context.go('/set-pin', extra: widget.creationData);
          return;
        }

        setState(() {
          _remainingPositions.removeAt(0);
          _currentQuizIndex++;
          _loadQuiz();
        });
      });
    } else {
      setState(() {
        _feedbackText = AppLocalizations.of(context)!.incorrectTryAgain;
        _feedbackCorrect = false;
      });

      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) {
          setState(() {
            _feedbackText = null;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = Theme.of(context).brightness == Brightness.dark
        ? ColorTokens.dark
        : ColorTokens.light;

    return Scaffold(
      // Light follows the neo page tint (pale lime) so the reference grid
      // reads as paper ruling; dark's `groupedBg` equals `bg`, so this only
      // affects light mode.
      backgroundColor: c.groupedBg,
      appBar: neoAppBar(
        c: c,
        darkBackground: c.bg,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.text),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            }
          },
        ),
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
                  l10n.verifyMnemonicTitle,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 10),

                // ── Subtitle ────────────────────────────────────────
                Text(
                  'Confirm you\'ve saved the correct words',
                  style: TextStyle(
                    color: c.text.withAlpha(150),
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 28),

                // ── Progress indicator ──────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int i = 0; i < _quizPositions.length; i++)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentQuizIndex > i
                              ? c.primary
                              : _currentQuizIndex == i
                                  ? c.primary.withAlpha(180)
                                  : c.border.withAlpha(100),
                          border: Border.all(
                            color: _currentQuizIndex >= i
                                ? c.primary
                                : c.border,
                            width: 2,
                          ),
                        ),
                      ),
                    const SizedBox(width: 12),
                    Text(
                      '${_currentQuizIndex + 1} / ${_quizPositions.length}',
                      style: TextStyle(
                        color: c.text.withAlpha(180),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // ── Quiz prompt ─────────────────────────────────────
                Text(
                  l10n.verifyWordPosition(_currentPosition),
                  style: TextStyle(
                    color: c.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  l10n.whichWord,
                  style: TextStyle(
                    color: c.text.withAlpha(130),
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 28),

                // ── Choice buttons ──────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: _currentChoices.map((word) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GestureDetector(
                            onTap: () => _onChoiceTap(word),
                            // Light outlines each choice as a neo block; dark
                            // falls back to the original hairline tile.
                            child: SizedBox(
                              width: double.infinity,
                              child: NeoCard(
                                legacyRadius: R.lg,
                                legacyEdge: c.border.withAlpha(100),
                                legacyEdgeWidth: 1.5,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 16,
                                ),
                                child: Center(
                                  child: Text(
                                    word,
                                    style: TextStyle(
                                      color: c.text,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                // ── Feedback ────────────────────────────────────────
                if (_feedbackText != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _feedbackText!,
                      style: TextStyle(
                        color: _feedbackCorrect
                            ? c.primary
                            : c.error,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
