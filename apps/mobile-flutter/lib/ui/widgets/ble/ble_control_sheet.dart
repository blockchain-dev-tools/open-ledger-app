import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/interfaces/chain_ble_control.dart';
import '../../../core/models/ble_types.dart';
import '../../../core/models/chain.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../utils/formatting.dart';
import '../../theme/color_tokens.dart';
import 'ble_log_controller.dart';
import 'ble_log_view.dart';

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

  /// Chains shown in the picker, in the registry's canonical order.
  static const chains = Chain.visible;

  static Future<void> open(
    BuildContext context, {
    required IChainBleControl control,
    BleLogController? logController,
    bool showLogs = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => _BleControlSheetContent(
        control: control,
        c: c,
        logController: logController,
        showLogsInitially: showLogs,
      ),
    );
  }
}

class _BleControlSheetContent extends StatefulWidget {
  final IChainBleControl control;
  final ColorTokens c;
  final BleLogController? logController;
  final bool showLogsInitially;

  const _BleControlSheetContent({
    required this.control,
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
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.text.withAlpha(60),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // The control view and the log view differ a lot in height, so
            // animate the resize; the two views also slide horizontally like
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
                    : KeyedSubtree(
                        key: const ValueKey('control'),
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
                    color: error
                        ? c.error
                        : active
                            ? c.primary
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
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          statusText.isNotEmpty
                              ? statusText
                              : l10n.startBleBroadcasting,
                          style: TextStyle(
                            color: error ? c.error : c.text.withAlpha(130),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (logs != null)
                    IconButton(
                      tooltip: l10n.bleLogs,
                      icon: Icon(Icons.article_outlined,
                          color: c.text.withAlpha(150)),
                      onPressed: () => setState(() => _logs = true),
                    ),
                  IconButton(
                    key: const Key('ble-sheet-close'),
                    icon: Icon(Icons.close, color: c.text.withAlpha(140)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.border),
            // ── Chain grid (3 columns) ─────────────────────
            // Chain selection is a single-select choice, so a grid of
            // chain tiles reads far denser than full-width rows —
            // the only per-row information was "which one is selected".
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
                  for (final chain in BleControlSheet.chains)
                    _ChainCell(
                      key: ValueKey('ble-chain-${chain.id}'),
                      c: c,
                      chain: chain,
                      selected: active && activeChain == chain,
                      disabled: control.isSignPending,
                      onTap: () =>
                          _toggleChain(chain, active && activeChain == chain),
                    ),
                ],
              ),
            ),
            // ── Hint ─────────────────────────────────────────────
            // This slot is always filled so the gesture is taught in every
            // state: how to start (idle) and how to stop (active). Hidden
            // only while a signing request locks the tiles.
            if (!control.isSignPending)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
                child: Text(
                  active
                      ? l10n.tapActiveChainToStop
                      : l10n.tapChainToStartBroadcast,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.text.withAlpha(110),
                    fontSize: 12,
                  ),
                ),
              )
            else
              const SizedBox(height: 8),
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
            child: Container(
              decoration: BoxDecoration(
                color:
                    selected ? c.primary.withAlpha(22) : c.text.withAlpha(10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? c.primary : Colors.transparent,
                  width: 1.5,
                ),
              ),
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
                              color: selected ? c.primary : c.text.withAlpha(200),
                              fontSize: 13,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
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
                          color: c.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.power_settings_new,
                          size: 13,
                          color: c.onPrimary,
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
