import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/interfaces/chain_ble_control.dart';
import '../../../core/models/ble_types.dart';
import '../../../core/models/chain.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../utils/formatting.dart';
import '../../theme/color_tokens.dart';
import '../common/neo_button.dart';
import '../common/neo_card.dart';
import '../common/neo_rule.dart';
import '../common/neo_sheet.dart';
import 'ble_log_controller.dart';
import 'ble_log_view.dart';

/// Deep blue for the Bluetooth glyph while the peripheral is broadcasting.
/// The only blue the app needs, so it stays local rather than joining the
/// shared token set.
const Color _broadcastBlue = Color(0xFF1565C0);

/// Bottom sheet controlling the single BLE peripheral.
///
/// Two views share ONE sheet route (house rule: never stack a sheet on a
/// sheet):
/// - **control** — idle: pick which chain app to expose and start
///   advertising (a single-select grid of visible chain tiles); active: show
///   the active chain + state, offer Stop and hot-switching to any other
///   chain;
/// - **logs** — the live APDU log, reached from the control header and
///   left again with the in-sheet back button.
class BleControlSheet {
  const BleControlSheet._();

  static Future<void> open(
    BuildContext context, {
    required IChainBleControl control,
    required List<Chain> chains,
    BleLogController? logController,
    bool showLogs = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      // Neo outlines the panel in brand ink with the tighter corners, like the
      // option sheets; dark keeps the original soft, rounded sheet.
      shape: neoSheetShape(c),
      builder: (context) => _BleControlSheetContent(
        control: control,
        chains: chains,
        c: c,
        logController: logController,
        showLogsInitially: showLogs,
      ),
    );
  }
}

class _BleControlSheetContent extends StatefulWidget {
  final IChainBleControl control;

  /// Chains the Vault currently shows — the picker must match that list, so a
  /// chain the user never added is never offered here.
  final List<Chain> chains;
  final ColorTokens c;
  final BleLogController? logController;
  final bool showLogsInitially;

  const _BleControlSheetContent({
    required this.control,
    required this.chains,
    required this.c,
    this.logController,
    this.showLogsInitially = false,
  });

  @override
  State<_BleControlSheetContent> createState() =>
      _BleControlSheetContentState();
}

class _BleControlSheetContentState extends State<_BleControlSheetContent> {
  late bool _logs = widget.showLogsInitially && widget.logController != null;

  /// The log view is only reachable when a controller was supplied.
  bool get _showLogs => _logs && widget.logController != null;

  /// Only the incoming page drives the sheet's height — the outgoing one is
  /// stacked on top (and clipped) so it can slide away without holding the
  /// height open while the sheet shrinks.
  static Widget _pageLayout(Widget? current, List<Widget> previous) {
    return Stack(
      clipBehavior: Clip.hardEdge,
      alignment: Alignment.topCenter,
      children: [
        for (final child in previous)
          Positioned(top: 0, left: 0, right: 0, child: child),
        ?current,
      ],
    );
  }

  /// Tapping a chain selects it and starts advertising. Tapping the chain
  /// that is already on stops it — there is no separate Stop button; the
  /// tile's power badge is the affordance (see [_ChainCell]).
  ///
  /// The sheet never auto-dismisses. Starting or switching also flips to
  /// the log view so the user watches the host handshake happen; stopping
  /// stays on the control view (nothing to watch).
  Future<void> _toggleChain(Chain chain, bool isActive) async {
    if (isActive) {
      await widget.control.stop();
      return;
    }
    await widget.control.startChain(chain);
    if (!mounted || widget.logController == null) return;
    setState(() => _logs = true);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final logs = widget.logController;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            neoSheetHandle(c),
            // Both views are pinned to the same height, so opening or leaving
            // the log never resizes the sheet. They slide horizontally like
            // pages (logs in from the right, control back from the left)
            // instead of swapping in place.
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: _pageLayout,
                transitionBuilder: (child, animation) {
                  // The target view fixes the travel direction: logs enter
                  // from the right (+x), control returns from the left (-x);
                  // the outgoing view exits the opposite way.
                  final incoming =
                      child.key == ValueKey(_showLogs ? 'logs' : 'control');
                  final side = _showLogs ? 1.0 : -1.0;
                  final tween = incoming
                      ? Tween(begin: Offset(side, 0), end: Offset.zero)
                      : Tween(begin: Offset(-side, 0), end: Offset.zero);
                  return SlideTransition(
                    position: animation.drive(tween),
                    child: child,
                  );
                },
                child: _showLogs
                    ? SizedBox(
                        key: const ValueKey('logs'),
                        height: screenHeight * 0.6,
                        child: BleLogView(
                          controller: logs!,
                          c: c,
                          onBack: () => setState(() => _logs = false),
                        ),
                      )
                    : SizedBox(
                        key: const ValueKey('control'),
                        height: screenHeight * 0.6,
                        child: _buildControlView(context, c, logs),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlView(
    BuildContext context,
    ColorTokens c,
    BleLogController? logs,
  ) {
    final l10n = AppLocalizations.of(context)!;

    return ListenableBuilder(
      listenable: widget.control,
      builder: (context, _) {
        final control = widget.control;
        final state = control.bleState;
        final activeChain = control.activeChain;
        final active = activeChain != null &&
            (state == BleState.broadcasting ||
                state == BleState.connected);
        final connected = state == BleState.connected;
        final error = state == BleState.error;

        final String statusText = error
            ? l10n.error
            : connected
                ? l10n.connected
                : active
                    ? l10n.broadcasting
                    : '';

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
              child: Row(
                children: [
                  Icon(
                    active || error
                        ? (connected
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth)
                        : Icons.bluetooth_outlined,
                    size: 20,
                    // Neo turns the glyph deep blue while broadcasting; dark
                    // keeps the brand lime.
                    color: error
                        ? c.error
                        : active
                            ? (c.neobrutalism ? _broadcastBlue : c.primary)
                            : c.text.withAlpha(160),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (active || error) && activeChain != null
                              ? l10n.chainLabel(activeChain.id)
                              : l10n.blePeripheral,
                          style: TextStyle(
                            color: c.text,
                            fontSize: 16,
                            // Neo gives the sheet title the same weight the
                            // option sheets use.
                            fontWeight: c.neobrutalism
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                        Text(
                          statusText.isNotEmpty
                              ? statusText
                              : l10n.startBleBroadcasting,
                          style: TextStyle(
                            // Neo inks the status line black (errors stay red);
                            // dark keeps the muted grey.
                            color: error
                                ? c.error
                                : c.neobrutalism
                                    ? c.brandInk
                                    : c.text.withAlpha(130),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('ble-sheet-close'),
                    icon: Icon(Icons.close,
                        color: c.neobrutalism
                            ? c.brandInk
                            : c.text.withAlpha(140)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Neo rules the header off with a black line, matching the option
            // sheets; dark keeps the hairline.
            neoRule(c),
            // ── Chain grid (3 columns) ─────────────────────
            // Chain selection is a single-select choice, so a grid of
            // chain tiles reads far denser than full-width rows —
            // the only per-row information was "which one is selected".
            //
            // Tiles + hint scroll as one block. The panel is pinned to the log
            // view's height and the tiles' height follows the sheet's width,
            // so a short panel would otherwise overflow instead of scrolling.
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.15,
                        children: [
                          for (final chain in widget.chains)
                            _ChainCell(
                              key: ValueKey('ble-chain-${chain.id}'),
                              c: c,
                              chain: chain,
                              selected: active && activeChain == chain,
                              disabled: control.isSignPending,
                              onTap: () => _toggleChain(
                                  chain, active && activeChain == chain),
                            ),
                        ],
                      ),
                    ),
                    // ── Hint ───────────────────────────────────
                    // Sits directly under the tiles, where the finger already
                    // is, so the gesture is taught in every state: how to start
                    // (idle) and how to stop (active). Hidden only while a
                    // signing request locks the tiles.
                    if (!control.isSignPending)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                        child: Text(
                          active
                              ? l10n.tapActiveChainToStop
                              : l10n.tapChainToStartBroadcast,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            // Neo inks it black; dark keeps the muted grey.
                            color: c.neobrutalism
                                ? c.brandInk
                                : c.text.withAlpha(110),
                            fontSize: 12,
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            // ── Log entry ───────────────────────────────────────
            // Centred and lifted off the panel edge: it is the only way into
            // the log, so it reads as a real action rather than a stray label.
            if (logs != null)
              Padding(
                key: const Key('ble-sheet-logs'),
                // Neo's button carries a [Neo.lift] shadow, and neither tone
                // should sit flush against the sheet's bottom edge.
                padding: const EdgeInsets.only(bottom: 28),
                child: Center(
                  child: c.neobrutalism
                      ? NeoButton(
                          label: l10n.bleLogs,
                          trailingIcon: Icons.chevron_right,
                          quiet: true,
                          onTap: () => setState(() => _logs = true),
                        )
                      : InkWell(
                          onTap: () => setState(() => _logs = true),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  l10n.bleLogs,
                                  style: TextStyle(
                                    color: c.text.withAlpha(180),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  size: 20,
                                  color: c.text.withAlpha(100),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ChainCell extends StatelessWidget {
  final ColorTokens c;
  final Chain chain;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  const _ChainCell({
    super.key,
    required this.c,
    required this.chain,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // A selected tile means "this chain is broadcasting"; tapping it again
    // stops, so its label describes that action rather than a selection.
    final String label = selected
        ? l10n.stopBroadcast
        : l10n.bleBroadcastAs(l10n.chainLabel(chain.id));

    return Semantics(
      button: true,
      selected: selected,
      enabled: !disabled,
      label: label,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: disabled ? null : onTap,
          child: Opacity(
            opacity: disabled ? 0.45 : 1,
            // Neo outlines every tile in brand ink and fills the broadcasting
            // one with bright lime; dark keeps the original tinted chip.
            child: NeoCard(
              lifted: false,
              fill: selected ? c.actionFill : null,
              legacyBackground:
                  selected ? c.primary.withAlpha(22) : c.text.withAlpha(10),
              legacyEdge: selected ? c.primary : Colors.transparent,
              legacyEdgeWidth: 1.5,
              legacyRadius: 14,
              child: Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Chain logo keeps its own brand colours (matches
                        // the FAB), so a chain reads the same everywhere.
                        SizedBox(
                          width: 34,
                          height: 34,
                          child: SvgPicture.asset(
                            chain.iconAssetPath,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            l10n.chainLabel(chain.id),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              // Neo inks every label black and heavy; dark keeps
                              // the brand-lime / muted pair.
                              color: c.neobrutalism
                                  ? c.brandInk
                                  : selected
                                      ? c.primary
                                      : c.text.withAlpha(200),
                              fontSize: 13,
                              fontWeight: c.neobrutalism
                                  ? FontWeight.w800
                                  : selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // The badge is the "tap again to stop" affordance — the
                  // active tile is the only place a stop action exists.
                  if (selected)
                    Positioned(
                      top: 5,
                      right: 5,
                      child: Container(
                        width: 19,
                        height: 19,
                        decoration: BoxDecoration(
                          // Deep-green tag in neo; dark keeps the lime disc.
                          color: c.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.power_settings_new,
                          size: 13,
                          color: c.onAccent,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
