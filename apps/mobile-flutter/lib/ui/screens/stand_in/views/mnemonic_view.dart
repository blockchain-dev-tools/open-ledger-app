import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/common/tab_button.dart';

/// The mnemonic step: a three-way Import / Generate / Enigma tab bar over the
/// currently selected [body].
class MnemonicView extends StatelessWidget {
  final ColorTokens c;
  final AppLocalizations l10n;

  /// 0 = import phrase, 1 = generate phrase, 2 = Enigma (riddle + secret).
  final int selectedTab;

  final ValueChanged<int> onTabSelected;

  /// The tab content for [selectedTab], assembled by the screen shell.
  final Widget body;

  const MnemonicView({
    super.key,
    required this.c,
    required this.l10n,
    required this.selectedTab,
    required this.onTabSelected,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // [TabStrip] reserves the ledge for its offset shadow, so light mode
        // needs no extra bottom gap; dark keeps the original flush spacing.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: TabStrip(
            c: c,
            tabs: [
              TabButton(
                key: const ValueKey('standin-tab-import'),
                c: c,
                label: l10n.standInImportTab,
                selected: selectedTab == 0,
                onTap: () => onTabSelected(0),
              ),
              TabButton(
                key: const ValueKey('standin-tab-generate'),
                c: c,
                label: l10n.standInGenerateTab,
                selected: selectedTab == 1,
                onTap: () => onTabSelected(1),
              ),
              TabButton(
                key: const ValueKey('standin-tab-enigma'),
                c: c,
                label: l10n.standInEnigmaTab,
                selected: selectedTab == 2,
                onTap: () => onTabSelected(2),
              ),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}
