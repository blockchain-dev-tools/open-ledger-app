import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/interfaces/ur_codec.dart';
import '../../core/models/ur_qr.dart';
import '../../generated/l10n/app_localizations.dart';
import '../theme/color_tokens.dart';
import '../widgets/common/grid_background.dart';
import '../widgets/common/neo_app_bar.dart';
import '../widgets/common/neo_mono_block.dart';
import '../widgets/common/qr_display_card.dart';

/// 账户导出页：手机显示 `crypto-account` 二维码，主机扫码导入。
///
/// 两种形态（主机的要求不同，实测得出的结论）：
/// - MetaMask：一张码带一页 5 个**叶子地址描述符**。它按页取地址
///   （`getAddressesPage(0, 5)`），只带一个会报 `Address not found for index 1`。
/// - OKX / Keystone 标准：一个**账户级公钥**（`m/44'/60'/0'`），主机自行派生。
class KeystoneAccountPage extends StatefulWidget {
  final IUrCodec codec;

  /// 本机钱包当前解锁的 seed —— 主机从二维码派生出的账户必须与本机一致。
  final String seedHex;

  final int initialIndex;

  const KeystoneAccountPage({
    super.key,
    required this.codec,
    required this.seedHex,
    this.initialIndex = 0,
  });

  @override
  State<KeystoneAccountPage> createState() => _KeystoneAccountPageState();
}

enum _ExportFormat { metaMask, keystone }

class _KeystoneAccountPageState extends State<KeystoneAccountPage> {
  /// MetaMask 一页要的地址数。
  static const int _pageSize = 5;

  static const int _fragmentLength = 60;

  /// 原型只导出 10 个账户。
  static const int _maxAccounts = 10;

  static const String _accountPath = "m/44'/60'/0'";

  late int _index = widget.initialIndex;
  _ExportFormat _format = _ExportFormat.metaMask;
  List<String> _frames = const [];
  List<String> _addresses = const [];
  String? _path;
  String? _error;
  int _frameIndex = 0;
  Timer? _loop;

  bool get _accountLevel => _format == _ExportFormat.keystone;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _pathFor(int index) =>
      _accountLevel ? _accountPath : "m/44'/60'/0'/0/$index";

  void _load() {
    _loop?.cancel();
    setState(() {
      _error = null;
      _frames = const [];
      _frameIndex = 0;
    });
    try {
      final export = widget.codec.encodeAccount(
        seedHex: widget.seedHex,
        path: _pathFor(_index),
        count: _pageSize,
        accountLevel: _accountLevel,
        fragmentLength: _fragmentLength,
      );
      setState(() {
        _frames = export.frames;
        _addresses = export.addresses;
        _path = export.path;
      });
      if (export.frames.length > 1) {
        _loop = Timer.periodic(const Duration(milliseconds: 500), (_) {
          if (!mounted) return;
          setState(() => _frameIndex = (_frameIndex + 1) % _frames.length);
        });
      }
    } on UrCodecException catch (error) {
      setState(() => _error = error.message);
    }
  }

  void _move(int delta) {
    final next = _index + delta * _pageSize;
    if (next < 0 || next + _pageSize > _maxAccounts) return;
    _index = next;
    _load();
  }

  void _selectFormat(_ExportFormat format) {
    if (format == _format) return;
    setState(() {
      _format = format;
      _index = 0;
    });
    _load();
  }

  @override
  void dispose() {
    _loop?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;
    final frame = _frames.isEmpty ? null : _frames[_frameIndex];

    return Scaffold(
      key: const Key('keystone-account-page'),
      backgroundColor: c.groupedBg,
      appBar: neoAppBar(
        c: c,
        darkBackground: c.groupedBg,
        title: Text(l10n.keystoneExportTitle),
      ),
      body: GridBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Text(
                l10n.keystoneExportHint,
                style: TextStyle(color: c.mutedText(170), fontSize: 13),
              ),
              const SizedBox(height: 12),
              SegmentedButton<_ExportFormat>(
                key: const Key('keystone-account-format'),
                // 日间模式把分段控件画成 neo 块：黑描边、lime 选中块、紧圆角。
                style: c.neobrutalism
                    ? SegmentedButton.styleFrom(
                        backgroundColor: c.surface,
                        foregroundColor: c.text,
                        selectedBackgroundColor: c.actionFill,
                        selectedForegroundColor: c.brandInk,
                        side: BorderSide(color: c.neoEdge, width: Neo.edge),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Neo.radius),
                        ),
                      )
                    : null,
                segments: [
                  ButtonSegment(
                    value: _ExportFormat.metaMask,
                    label: Text(l10n.keystoneExportFormatMetaMask),
                  ),
                  ButtonSegment(
                    value: _ExportFormat.keystone,
                    label: Text(l10n.keystoneExportFormatKeystone),
                  ),
                ],
                selected: {_format},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    _selectFormat(selection.first),
              ),
              const SizedBox(height: 16),
              if (!_accountLevel)
                Row(
                  children: [
                    IconButton(
                      key: const Key('keystone-account-prev'),
                      onPressed: _index == 0 ? null : () => _move(-1),
                      icon: const Icon(Icons.chevron_left),
                      color: c.text,
                      tooltip: l10n.keystoneExportPrev,
                    ),
                    Expanded(
                      child: Text(
                        l10n.keystoneExportAccountRange(
                          _index,
                          _index + _pageSize - 1,
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('keystone-account-next'),
                      onPressed: _index + _pageSize > _maxAccounts
                          ? null
                          : () => _move(1),
                      icon: const Icon(Icons.chevron_right),
                      color: c.text,
                      tooltip: l10n.keystoneExportNext,
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              Center(child: _buildQr(c, frame)),
              if (_frames.length > 1) ...[
                const SizedBox(height: 8),
                Text(
                  '${_frameIndex + 1} / ${_frames.length}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.mutedText(120), fontSize: 12),
                ),
              ],
              const SizedBox(height: 20),
              if (_addresses.isNotEmpty)
                _Field(
                  label: l10n.keystoneExportPageAddresses,
                  value: [
                    for (var i = 0; i < _addresses.length; i++)
                      '${_index + i}  ${_addresses[i]}',
                  ].join('\n'),
                  c: c,
                ),
              if (_path != null)
                _Field(label: l10n.keystoneExportPath, value: _path!, c: c),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQr(ColorTokens c, String? frame) {
    final size = MediaQuery.of(context).size.shortestSide * 0.72;
    if (_error != null) {
      return Container(
        key: const Key('keystone-account-error'),
        width: size,
        height: size,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(
            c.neobrutalism ? Neo.radius : R.lg,
          ),
          border: Border.all(
            color: c.neobrutalism ? c.neoEdge : c.text.withAlpha(40),
            width: c.neobrutalism ? Neo.edge : 1,
          ),
        ),
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: TextStyle(color: c.error, fontSize: 13),
        ),
      );
    }
    if (frame == null) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(child: CircularProgressIndicator(color: c.accent)),
      );
    }
    // 白底二维码卡片；日间模式由 QrDisplayCard 加黑描边，深色保留细边。
    return QrDisplayCard(
      key: const Key('keystone-account-qr'),
      data: frame,
      size: size - 24,
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String value;
  final ColorTokens c;

  const _Field({required this.label, required this.value, required this.c});

  @override
  Widget build(BuildContext context) {
    final text = SelectableText(
      value,
      style: TextStyle(color: c.text, fontSize: 13, fontFamily: 'monospace'),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: c.mutedText(120),
              fontSize: 11,
              fontWeight: c.neobrutalism ? FontWeight.w600 : null,
            ),
          ),
          const SizedBox(height: 4),
          // 日间模式把数据收进带黑框的块里；深色保持裸文本。
          NeoMonoBlock(child: text),
        ],
      ),
    );
  }
}
