import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';
import 'neo_card.dart';

/// A solid neobrutalist action: [Neo.edge] px outline, flat fill, a hard
/// shadow — and a press that pushes the button into that shadow.
///
/// Light-mode chrome only: while [ColorTokens.neobrutalism] is false the
/// screens keep their original flat actions instead of building this.
///
/// Two tones:
/// - brand (`quiet: false`) — [ColorTokens.actionFill] fill, with
///   [ColorTokens.brandInk] label and outline.
/// - quiet (`quiet: true`) — [ColorTokens.bg] fill, [ColorTokens.text] label,
///   [ColorTokens.neoEdge] outline.
///
/// ```dart
/// NeoButton(label: 'Add Account', icon: Icons.add, expanded: true, onTap: _add)
/// NeoButton(label: 'Copy', quiet: true, onTap: _copy)
/// ```
class NeoButton extends StatelessWidget {
  /// Button label text.
  final String label;

  /// Optional leading icon.
  final IconData? icon;

  /// Called on tap. Always enabled — the neo prototype has no disabled state.
  final VoidCallback onTap;

  /// Stretches the button to its parent's width.
  final bool expanded;

  /// Secondary tone: neutral fill with text-coloured label.
  final bool quiet;

  const NeoButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.expanded = false,
    this.quiet = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final background = quiet ? c.bg : c.actionFill;
    final foreground = quiet ? c.text : c.brandInk;
    final edge = quiet ? c.neoEdge : c.brandInk;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(Neo.radius),
        border: Border.all(color: edge, width: Neo.edge),
        boxShadow: neoShadow(c),
      ),
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    return _NeoPress(
      onTap: onTap,
      child: expanded
          ? SizedBox(width: double.infinity, child: content)
          : content,
    );
  }
}

/// Pushes its child [Neo.lift] px toward its own shadow while held down.
class _NeoPress extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _NeoPress({required this.child, required this.onTap});

  @override
  State<_NeoPress> createState() => _NeoPressState();
}

class _NeoPressState extends State<_NeoPress> {
  bool _down = false;

  void _setDown(bool value) {
    if (_down != value) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setDown(true),
      onTapUp: (_) => _setDown(false),
      onTapCancel: () => _setDown(false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(
          _down ? Neo.lift : 0,
          _down ? Neo.lift : 0,
          0,
        ),
        child: widget.child,
      ),
    );
  }
}
