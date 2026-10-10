import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/interfaces/wallet_service.dart';
import '../../../core/models/vault.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../pin/pin_dot_indicator.dart';
import '../pin/pin_number_pad.dart';

/// The user-facing name of [vault], falling back to a localized default when
/// the vault has no label. [index] is its position in `walletService.vaults`.
String vaultDisplayName(Vault vault, int index, AppLocalizations l10n) =>
    vault.label.isEmpty ? '${l10n.vaultWord} ${index + 1}' : vault.label;

/// AppBar title for the Accounts tab: shows the active vault's name with a
/// dropdown affordance. Tapping it opens the vault switcher sheet.
///
/// [onChanged] is invoked after a switch / rename / add / remove so the host
/// screen can rebuild against the new session state.
class VaultSwitcherTitle extends StatelessWidget {
  final IWalletService walletService;
  final VoidCallback? onChanged;

  const VaultSwitcherTitle({
    super.key,
    required this.walletService,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;

    final vaults = walletService.vaults;
    final activeId = walletService.activeVaultId;
    final index = vaults.indexWhere((v) => v.id == activeId);
    final name = index >= 0
        ? vaultDisplayName(vaults[index], index, l10n)
        : l10n.accountsTitle;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openSheet(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Icon(
            Icons.arrow_drop_down,
            color: c.text.withAlpha(160),
          ),
        ],
      ),
    );
  }

  void _openSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xl)),
      ),
      builder: (context) => _VaultSwitcherSheet(
        walletService: walletService,
        onChanged: onChanged,
      ),
    );
  }
}

/// The switcher sheet. Two views share ONE sheet route (house rule: never
/// stack a sheet on a sheet):
/// - **list** — pick the active vault;
/// - **manage** — rename / remove vaults, add a new one, reached from the
///   list footer and left again with the in-sheet back arrow.
class _VaultSwitcherSheet extends StatefulWidget {
  final IWalletService walletService;
  final VoidCallback? onChanged;

  const _VaultSwitcherSheet({
    required this.walletService,
    this.onChanged,
  });

  @override
  State<_VaultSwitcherSheet> createState() => _VaultSwitcherSheetState();
}

class _VaultSwitcherSheetState extends State<_VaultSwitcherSheet> {
  bool _managing = false;

  IWalletService get _ws => widget.walletService;

  // ── Actions ────────────────────────────────────────────────────────

  Future<void> _switch(Vault vault) async {
    try {
      await _ws.switchVault(vault.id);
    } catch (e) {
      if (mounted) _showError(e);
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onChanged?.call();
  }

  Future<void> _rename(Vault vault) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: vault.label);
    final newLabel = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final c = isDark ? ColorTokens.dark : ColorTokens.light;
        return AlertDialog(
          backgroundColor: c.surface,
          title: Text(l10n.renameVault),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: c.text),
            decoration: InputDecoration(hintText: l10n.vaultNameHint),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(controller.text.trim()),
              child: Text(l10n.renameVault),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (newLabel == null) return;

    try {
      await _ws.renameVault(vault.id, newLabel);
    } catch (e) {
      if (mounted) _showError(e);
      return;
    }
    if (!mounted) return;
    setState(() {});
    widget.onChanged?.call();
  }

  Future<void> _remove(Vault vault) async {
    final l10n = AppLocalizations.of(context)!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final c = isDark ? ColorTokens.dark : ColorTokens.light;
        return AlertDialog(
          backgroundColor: c.surface,
          title: Text(l10n.removeVault),
          content: Text(l10n.removeVaultConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                l10n.removeVault,
                style: TextStyle(color: c.error),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    if (!mounted) return;
    final removed = await showDialog<bool>(
      context: context,
      builder: (_) => _PinPromptDialog(
        title: l10n.vaultPinPrompt,
        onSubmit: (pin) async {
          try {
            await _ws.removeVault(vault.id, pin: pin);
            return null;
          } on StateError catch (e) {
            return _localizedPinError(e.message, l10n);
          } catch (e) {
            return e.toString();
          }
        },
      ),
    );
    if (removed != true || !mounted) return;
    setState(() {});
    widget.onChanged?.call();
  }

  void _startNewVault() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push('/import', extra: {'addVault': true});
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$error')),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return SafeArea(
      top: false,
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
          if (_managing)
            _buildManageView(context, c)
          else
            _buildListView(context, c),
        ],
      ),
    );
  }

  // ── List view ──────────────────────────────────────────────────────

  Widget _buildListView(BuildContext context, ColorTokens c) {
    final l10n = AppLocalizations.of(context)!;
    final vaults = _ws.vaults;
    final activeId = _ws.activeVaultId;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          c: c,
          title: l10n.switchVault,
          onClose: () => Navigator.of(context).pop(),
        ),
        Divider(height: 1, color: c.border),
        for (var i = 0; i < vaults.length; i++)
          _VaultTile(
            key: ValueKey('vault-tile-${vaults[i].id}'),
            c: c,
            name: vaultDisplayName(vaults[i], i, l10n),
            selected: vaults[i].id == activeId,
            onTap: () => _switch(vaults[i]),
          ),
        Divider(height: 1, color: c.border),
        _ManageRow(
          c: c,
          label: l10n.manageVaults,
          onTap: () => setState(() => _managing = true),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ── Manage view ────────────────────────────────────────────────────

  Widget _buildManageView(BuildContext context, ColorTokens c) {
    final l10n = AppLocalizations.of(context)!;
    final vaults = _ws.vaults;
    final canRemove = vaults.length > 1;
    // Only the primary tier (depth 0) is capped; a stand-in tier may grow
    // freely, so a stand-in session always offers "New Vault".
    final atLimit = _ws.sessionDepth == 0 && vaults.length >= maxNormalVaults;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          c: c,
          title: l10n.manageVaults,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: c.text.withAlpha(160)),
            onPressed: () => setState(() => _managing = false),
          ),
          onClose: () => Navigator.of(context).pop(),
        ),
        Divider(height: 1, color: c.border),
        for (var i = 0; i < vaults.length; i++)
          _ManageVaultTile(
            key: ValueKey('manage-vault-${vaults[i].id}'),
            c: c,
            name: vaultDisplayName(vaults[i], i, l10n),
            canRemove: canRemove,
            onRename: () => _rename(vaults[i]),
            onRemove: () => _remove(vaults[i]),
          ),
        // A new vault is added to the current session's tier (the service
        // derives the depth from the session), so it is available in every
        // session — including a stand-in one.
        Divider(height: 1, color: c.border),
        _ManageVaultTile(
          key: const ValueKey('new-vault-row'),
          c: c,
          name: l10n.newVault,
          leadingIcon: Icons.add,
          subtitle: atLimit ? l10n.vaultLimitReached : null,
          disabled: atLimit,
          onRename: null,
          onRemove: null,
          onTap: atLimit ? null : _startNewVault,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Shared pieces
// ═══════════════════════════════════════════════════════════════════════

/// A sheet header row: optional leading widget, title, close button.
class _Header extends StatelessWidget {
  final ColorTokens c;
  final String title;
  final Widget? leading;
  final VoidCallback onClose;

  const _Header({
    required this.c,
    required this.title,
    this.leading,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          ?leading,
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: c.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: c.text.withAlpha(140)),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// A selectable vault row in the list view.
class _VaultTile extends StatelessWidget {
  final ColorTokens c;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  const _VaultTile({
    super.key,
    required this.c,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  color: c.text,
                  fontSize: 16,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (selected) Icon(Icons.check, size: 20, color: c.primary),
          ],
        ),
      ),
    );
  }
}

/// The "Manage Vaults" footer row that opens the manage view.
class _ManageRow extends StatelessWidget {
  final ColorTokens c;
  final String label;
  final VoidCallback onTap;

  const _ManageRow({
    required this.c,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(Icons.settings_outlined, size: 20, color: c.text.withAlpha(160)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: c.text.withAlpha(200),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: c.text.withAlpha(80)),
          ],
        ),
      ),
    );
  }
}

/// A manage-view row: vault name + rename / remove actions, or the "new
/// vault" action when [onTap] is set.
class _ManageVaultTile extends StatelessWidget {
  final ColorTokens c;
  final String name;
  final IconData? leadingIcon;
  final String? subtitle;
  final bool disabled;
  final bool canRemove;
  final VoidCallback? onRename;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;

  const _ManageVaultTile({
    super.key,
    required this.c,
    required this.name,
    this.leadingIcon,
    this.subtitle,
    this.disabled = false,
    this.canRemove = true,
    this.onRename,
    this.onRemove,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      child: Row(
        children: [
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: 20, color: c.primary.withAlpha(180)),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: disabled ? c.text.withAlpha(120) : c.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: c.text.withAlpha(120),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onRename != null)
            IconButton(
              tooltip: l10n.renameVault,
              icon: Icon(Icons.edit_outlined,
                  size: 20, color: c.text.withAlpha(160)),
              onPressed: onRename,
            ),
          if (onRemove != null)
            IconButton(
              tooltip: l10n.removeVault,
              icon: Icon(
                Icons.delete_outline,
                size: 20,
                color: canRemove ? c.error : c.text.withAlpha(80),
              ),
              onPressed: canRemove ? onRemove : null,
            ),
        ],
      ),
    );

    if (onTap == null) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: content,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PIN prompt (single dialog — never a sheet stacked on the sheet)
// ═══════════════════════════════════════════════════════════════════════

/// A small modal that collects a 6-digit PIN and delegates the action to
/// [onSubmit]. `onSubmit` returns `null` on success (the dialog pops `true`)
/// or an error message to display while the user retries.
class _PinPromptDialog extends StatefulWidget {
  final String title;
  final Future<String?> Function(String pin) onSubmit;

  const _PinPromptDialog({
    required this.title,
    required this.onSubmit,
  });

  @override
  State<_PinPromptDialog> createState() => _PinPromptDialogState();
}

class _PinPromptDialogState extends State<_PinPromptDialog> {
  static const int _pinLength = 6;

  final List<int> _pin = [];
  String? _error;
  bool _busy = false;

  void _onDigit(int digit) {
    if (_busy || _pin.length >= _pinLength) return;
    setState(() {
      _pin.add(digit);
      _error = null;
    });
    if (_pin.length == _pinLength) _submit();
  }

  void _onBackspace() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin.removeLast());
  }

  Future<void> _submit() async {
    final pin = _pin.join();
    setState(() => _busy = true);
    String? error;
    try {
      error = await widget.onSubmit(pin);
    } catch (e) {
      error = e.toString();
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _error = error;
      _pin.clear();
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      backgroundColor: c.surface,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PinDotIndicator(length: _pinLength, filledCount: _pin.length),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.error, fontSize: 13),
            ),
          ],
          const SizedBox(height: 16),
          PinNumberPad(
            onDigit: _onDigit,
            onBackspace: _onBackspace,
            keyPrefix: 'remove-pin',
            disabled: _busy,
            buttonSize: 56,
            spacing: 8,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}

/// Map the service's auth errors to the localized "Incorrect PIN" string;
/// anything else is surfaced verbatim.
String _localizedPinError(String message, AppLocalizations l10n) {
  if (message == 'Incorrect PIN' ||
      message == 'PIN does not match the current wallet.') {
    return l10n.incorrectPin;
  }
  return message;
}
