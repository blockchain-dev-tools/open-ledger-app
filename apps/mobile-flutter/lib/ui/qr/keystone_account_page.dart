import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/interfaces/ur_codec.dart';
import '../../core/models/ur_qr.dart';
import '../../generated/l10n/app_localizations.dart';
import '../theme/color_tokens.dart';

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
      appBar: AppBar(
        backgroundColor: c.groupedBg,
        foregroundColor: c.text,
        title: Text(l10n.keystoneExportTitle),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            _Warning(text: l10n.keystoneExportTestAccount),
            const SizedBox(height: 16),
            Text(
              l10n.keystoneExportHint,
              style: TextStyle(color: c.text.withAlpha(170), fontSize: 13),
            ),
            const SizedBox(height: 12),
            SegmentedButton<_ExportFormat>(
              key: const Key('keystone-account-format'),
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
              onSelectionChanged: (selection) => _selectFormat(selection.first),
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
                    onPressed:
                        _index + _pageSize > _maxAccounts ? null : () => _move(1),
                    icon: const Icon(Icons.chevron_right),
                    color: c.text,
                    tooltip: l10n.keystoneExportNext,
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Center(child: _buildQr(c, frame, l10n)),
            if (_frames.length > 1) ...[
              const SizedBox(height: 8),
              Text(
                '${_frameIndex + 1} / ${_frames.length}',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.text.withAlpha(120), fontSize: 12),
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
            if (_path != null) _Field(label: l10n.keystoneExportPath, value: _path!, c: c),
          ],
        ),
      ),
    );
  }

  Widget _buildQr(ColorTokens c, String? frame, AppLocalizations l10n) {
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
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.text.withAlpha(40)),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // 二维码永远画在白底上，不跟随暗色主题。
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: QrImageView(
        key: const Key('keystone-account-qr'),
        data: frame,
        version: QrVersions.auto,
        size: size - 28,
        backgroundColor: Colors.white,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Colors.black,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Colors.black,
        ),
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  final String text;

  const _Warning({required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.accent.withAlpha(28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.accent.withAlpha(90)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.science_outlined, size: 18, color: c.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: c.text, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: c.text.withAlpha(120), fontSize: 11),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: TextStyle(
              color: c.text,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
