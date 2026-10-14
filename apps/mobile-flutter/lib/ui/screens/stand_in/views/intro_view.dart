import 'package:flutter/material.dart';

import '../../../../core/models/vault.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_button.dart';
import '../../../widgets/common/primary_button.dart';
import '../components/option_card.dart';
import '../components/section_title.dart';
import '../stand_in_style.dart';

/// First wizard step: the threat-model copy plus the hide / wipe mode picker,
/// pinned to a full-width Continue CTA.
class IntroView extends StatelessWidget {
  final ColorTokens c;
  final AppLocalizations l10n;

  /// Mode currently chosen in the wizard.
  final StandInMode wizardMode;

  final ValueChanged<StandInMode> onModeSelected;
  final VoidCallback onContinue;

  const IntroView({
    super.key,
    required this.c,
    required this.l10n,
    required this.wizardMode,
    required this.onModeSelected,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
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
                  color: standInSecondaryText(c, Theme.of(context).brightness),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 26),
              SectionTitle(c: c, title: l10n.standInModeSectionTitle),
              const SizedBox(height: 10),
              OptionCard(
                key: const ValueKey('standin-mode-hide'),
                c: c,
                title: l10n.standInModeHide,
                description: l10n.standInModeHideDesc,
                selected: wizardMode == StandInMode.hide,
                onTap: () => onModeSelected(StandInMode.hide),
              ),
              const SizedBox(height: 10),
              OptionCard(
                key: const ValueKey('standin-mode-wipe'),
                c: c,
                title: l10n.standInModeWipe,
                description: l10n.standInModeWipeDesc,
                selected: wizardMode == StandInMode.wipe,
                danger: true,
                onTap: () => onModeSelected(StandInMode.wipe),
              ),
            ],
          ),
        ),
        // Pinned action area — the CTA sits at the bottom safe edge instead
        // of floating mid-page with a dead half-screen beneath it.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: c.neobrutalism
              ? NeoButton(
                  key: const Key('standin-intro-continue'),
                  label: l10n.continueButton,
                  expanded: true,
                  onTap: onContinue,
                )
              : PrimaryButton(
                  key: const Key('standin-intro-continue'),
                  label: l10n.continueButton,
                  onTap: onContinue,
                ),
        ),
      ],
    );
  }
}
