import 'package:flutter/material.dart';

import '../../../../core/models/vault.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';
import '../components/option_card.dart';
import '../components/section_title.dart';

/// Configured mode picker: the same hide / wipe [OptionCard]s as the wizard
/// intro, but wired to the manage (PIN-gated) selection handler.
class SelectModeView extends StatelessWidget {
  final ColorTokens c;
  final AppLocalizations l10n;

  /// The mode currently stored on the vault.
  final StandInMode mode;

  final ValueChanged<StandInMode> onModeSelected;

  const SelectModeView({
    super.key,
    required this.c,
    required this.l10n,
    required this.mode,
    required this.onModeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        SectionTitle(c: c, title: l10n.standInModeSectionTitle),
        const SizedBox(height: 12),
        OptionCard(
          key: const ValueKey('standin-mode-hide'),
          c: c,
          title: l10n.standInModeHide,
          description: l10n.standInModeHideDesc,
          selected: mode == StandInMode.hide,
          onTap: () => onModeSelected(StandInMode.hide),
        ),
        const SizedBox(height: 10),
        OptionCard(
          key: const ValueKey('standin-mode-wipe'),
          c: c,
          title: l10n.standInModeWipe,
          description: l10n.standInModeWipeDesc,
          selected: mode == StandInMode.wipe,
          danger: true,
          onTap: () => onModeSelected(StandInMode.wipe),
        ),
      ],
    );
  }
}
