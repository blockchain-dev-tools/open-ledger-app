import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../biz/qr_sign_flow.dart';
import '../../generated/l10n/app_localizations.dart';
import '../theme/color_tokens.dart';
import '../widgets/common/adaptive_action_button.dart';
import '../widgets/common/grid_background.dart';
import '../widgets/common/neo_app_bar.dart';
import '../widgets/common/neo_card.dart';
import 'keystone_signature_page.dart';

/// 一期只支持交易（1）、个人消息（3）与已编码 typed transaction（4）。
String _dataTypeLabel(AppLocalizations l10n, int dataType) {
  return switch (dataType) {
    1 => l10n.keystoneDataTypeTransaction,
    3 => l10n.keystoneDataTypePersonalMessage,
    4 => l10n.keystoneDataTypeTypedTransaction,
    _ => l10n.keystoneDataTypeUnsupported(dataType),
  };
}

/// 交易里最值得核对的两个字段。`null` 表示这份载荷摊不开（不是交易）。
class _TxSummary {
  final String? to;
  final String amount;
  final Uint8List? data;

  const _TxSummary({
    required this.to,
    required this.amount,
    required this.data,
  });
}

Uint8List? _hexToBytes(String hex) {
  final text = hex.startsWith('0x') ? hex.substring(2) : hex;
  if (text.isEmpty || text.length.isOdd) return null;
  final out = Uint8List(text.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final byte = int.tryParse(text.substring(i * 2, i * 2 + 2), radix: 16);
    if (byte == null) return null;
    out[i] = byte;
  }
  return out;
}

int _bigEndian(Uint8List bytes) {
  var value = 0;
  for (final byte in bytes) {
    value = (value << 8) | byte;
  }
  return value;
}

class _RlpSpan {
  final bool isList;
  final int start;
  final int end;

  const _RlpSpan({
    required this.isList,
    required this.start,
    required this.end,
  });
}

/// 解一个 RLP 项，返回它的内容区间（字符串项直接给区间，列表项只给范围）。
_RlpSpan? _rlpSpan(Uint8List data, int offset) {
  if (offset >= data.length) return null;
  final prefix = data[offset];
  if (prefix <= 0x7f) {
    return _RlpSpan(isList: false, start: offset, end: offset + 1);
  }
  int length;
  int start;
  var isList = false;
  if (prefix <= 0xb7) {
    length = prefix - 0x80;
    start = offset + 1;
  } else if (prefix <= 0xbf) {
    final size = prefix - 0xb7;
    if (offset + 1 + size > data.length) return null;
    length = _bigEndian(data.sublist(offset + 1, offset + 1 + size));
    start = offset + 1 + size;
  } else if (prefix <= 0xf7) {
    length = prefix - 0xc0;
    start = offset + 1;
    isList = true;
  } else {
    final size = prefix - 0xf7;
    if (offset + 1 + size > data.length) return null;
    length = _bigEndian(data.sublist(offset + 1, offset + 1 + size));
    start = offset + 1 + size;
    isList = true;
  }
  if (length < 0 || start + length > data.length) return null;
  return _RlpSpan(isList: isList, start: start, end: start + length);
}

/// 只解最外层列表：字符串项给字节，嵌套列表给 `null`（用不到）。
List<Uint8List?>? _rlpTopList(Uint8List data) {
  final root = _rlpSpan(data, 0);
  if (root == null || !root.isList) return null;
  final items = <Uint8List?>[];
  var offset = root.start;
  while (offset < root.end) {
    final span = _rlpSpan(data, offset);
    if (span == null) return null;
    items.add(span.isList ? null : data.sublist(span.start, span.end));
    offset = span.end;
  }
  return items;
}

String _formatWei(BigInt wei) {
  if (wei == BigInt.zero) return '0 ETH';
  final base = BigInt.from(10).pow(18);
  final whole = wei ~/ base;
  final fraction = (wei % base)
      .toString()
      .padLeft(18, '0')
      .replaceAll(RegExp(r'0+$'), '');
  return fraction.isEmpty ? '$whole ETH' : '$whole.$fraction ETH';
}

_TxSummary? _summarizeTransaction(int dataType, String signDataHex) {
  final raw = _hexToBytes(signDataHex);
  if (raw == null) return null;
  var payload = raw;
  var type = 0;
  if (dataType == 4) {
    if (raw.isEmpty) return null;
    type = raw[0];
    payload = raw.sublist(1);
  } else if (dataType != 1) {
    return null;
  }
  final items = _rlpTopList(payload);
  if (items == null) return null;
  final int toIndex;
  final int valueIndex;
  final int dataIndex;
  switch (type) {
    case 0:
      toIndex = 3;
      valueIndex = 4;
      dataIndex = 5;
    case 1:
      toIndex = 4;
      valueIndex = 5;
      dataIndex = 6;
    case 2:
      toIndex = 5;
      valueIndex = 6;
      dataIndex = 7;
    default:
      return null;
  }
  if (items.length <= valueIndex) return null;
  final value = items[valueIndex];
  if (value == null) return null;
  final to = items[toIndex];
  return _TxSummary(
    to: to == null || to.isEmpty ? null : '0x${_hexOf(to)}',
    amount: _formatWei(
      BigInt.parse('0x${value.isEmpty ? '0' : _hexOf(value)}'),
    ),
    data: dataIndex < items.length ? items[dataIndex] : null,
  );
}

/// 常见 ERC-20 / ERC-721 方法的参数布局，用来把 calldata 摊成人话。
/// 只做展示，不做严格 ABI 校验。
const Map<String, (String, List<String>)> _knownCalls = {
  'a9059cbb': ('transfer', ['address', 'uint256']),
  '095ea7b3': ('approve', ['address', 'uint256']),
  '23b872dd': ('transferFrom', ['address', 'address', 'uint256']),
  '39509351': ('increaseAllowance', ['address', 'uint256']),
  'a457c2d7': ('decreaseAllowance', ['address', 'uint256']),
  'a22cb465': ('setApprovalForAll', ['address', 'bool']),
  '42842e0e': ('safeTransferFrom', ['address', 'address', 'uint256']),
};

class _DecodedCall {
  final String title;
  final List<String> params;
  final String rawHex;

  const _DecodedCall({
    required this.title,
    required this.params,
    required this.rawHex,
  });
}

const int _maxCalldataPreviewChars = 600;

String _hexOf(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// 把 calldata 拆成「方法 + 参数」；认不出的方法只给选择器与原始十六进制。
_DecodedCall? _decodeCall(Uint8List? data) {
  if (data == null || data.isEmpty) return null;
  final hex = _hexOf(data);
  final rawHex = hex.length <= _maxCalldataPreviewChars
      ? '0x$hex'
      : '0x${hex.substring(0, _maxCalldataPreviewChars)}…';
  if (data.length < 4) {
    return _DecodedCall(title: '0x$hex', params: const [], rawHex: rawHex);
  }
  final selector = hex.substring(0, 8);
  final known = _knownCalls[selector];
  if (known == null) {
    return _DecodedCall(title: '0x$selector', params: const [], rawHex: rawHex);
  }
  final (name, types) = known;
  final params = <String>[];
  var offset = 4;
  for (final type in types) {
    if (offset + 32 > data.length) {
      params.add('—');
      offset += 32;
      continue;
    }
    final word = data.sublist(offset, offset + 32);
    if (type == 'address') {
      params.add('0x${_hexOf(word.sublist(12))}');
    } else if (type == 'uint256') {
      params.add(BigInt.parse('0x${_hexOf(word)}').toString());
    } else if (type == 'bool') {
      params.add(word.last == 0 ? 'false' : 'true');
    } else {
      params.add('0x${_hexOf(word)}');
    }
    offset += 32;
  }
  return _DecodedCall(
    title: '$name(${types.join(',')})',
    params: params,
    rawHex: rawHex,
  );
}

/// 个人消息直接摊开成文字，方便核对「签的到底是什么」。
String? _messagePreview(int dataType, String signDataHex) {
  if (dataType != 3) return null;
  final raw = _hexToBytes(signDataHex);
  if (raw == null || raw.isEmpty) return null;
  String text;
  try {
    text = utf8.decode(raw);
  } on FormatException {
    return null;
  }
  if (text.trim().isEmpty) return null;
  return text.length <= 200 ? text : '${text.substring(0, 200)}…';
}

/// 审阅页：把请求里所有能核对的字段摊开，再让用户决定签不签。
///
/// 不展示原始 `sign_data` 的完整十六进制（一笔交易可能几 KB），只展示
/// 哈希、长度与来源/地址；契约要求的两项（origin、address）缺一不可。
class KeystoneReviewPage extends StatefulWidget {
  final QrSignFlow flow;

  const KeystoneReviewPage({super.key, required this.flow});

  @override
  State<KeystoneReviewPage> createState() => _KeystoneReviewPageState();
}

class _KeystoneReviewPageState extends State<KeystoneReviewPage> {
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    widget.flow.addListener(_onFlowChanged);
  }

  @override
  void dispose() {
    widget.flow.removeListener(_onFlowChanged);
    super.dispose();
  }

  void _onFlowChanged() {
    if (!mounted) return;
    setState(() {});
    if (widget.flow.phase == QrSignPhase.signature && !_navigating) {
      _navigating = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => KeystoneSignaturePage(flow: widget.flow),
        ),
      );
    }
  }

  void _reject() {
    widget.flow.reject();
    Navigator.of(context).pop();
  }

  void _retry() {
    widget.flow.start();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;
    final request = widget.flow.request;
    final tx = request == null
        ? null
        : _summarizeTransaction(request.dataType, request.signDataHex);
    final message = request == null
        ? null
        : _messagePreview(request.dataType, request.signDataHex);
    final call = _decodeCall(tx?.data);
    final signing = widget.flow.phase == QrSignPhase.signing;
    final failed = widget.flow.phase == QrSignPhase.failed;

    return Scaffold(
      key: const Key('keystone-review-page'),
      backgroundColor: c.groupedBg,
      appBar: neoAppBar(
        c: c,
        darkBackground: c.groupedBg,
        automaticallyImplyLeading: false,
        title: Text(l10n.keystoneReviewTitle),
      ),
      body: request == null
          ? const SizedBox.shrink()
          : GridBackground(
              child: SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                        children: [
                          _DetailBlock(
                            c: c,
                            children: [
                              _Row(
                                label: l10n.keystoneReviewDataType,
                                value: _dataTypeLabel(l10n, request.dataType),
                                c: c,
                              ),
                              if (request.chainId != null)
                                _Row(
                                  label: l10n.keystoneReviewChain,
                                  value: '${request.chainId}',
                                  c: c,
                                ),
                              _Row(
                                label: l10n.keystoneReviewOrigin,
                                value: request.origin ?? '—',
                                c: c,
                                emphasize: true,
                              ),
                              _Row(
                                label: l10n.keystoneReviewPath,
                                value: request.path,
                                c: c,
                                mono: true,
                              ),
                              _Row(
                                label: l10n.keystoneReviewAddress,
                                value: request.address ?? '—',
                                c: c,
                                mono: true,
                                emphasize: true,
                              ),
                              _Row(
                                label: l10n.keystoneReviewDataHash,
                                value: request.signingHashHex,
                                c: c,
                                mono: true,
                              ),
                              _Row(
                                label: l10n.keystoneReviewDataSize,
                                value: '${request.signDataBytes} B',
                                c: c,
                              ),
                              if (tx != null) ...[
                                if (tx.to != null)
                                  _Row(
                                    label: l10n.keystoneReviewTo,
                                    value: tx.to!,
                                    c: c,
                                    mono: true,
                                    emphasize: true,
                                  ),
                                _Row(
                                  label: l10n.keystoneReviewAmount,
                                  value: tx.amount,
                                  c: c,
                                ),
                              ],
                              if (message != null)
                                _Row(
                                  label: l10n.keystoneReviewMessage,
                                  value: message,
                                  c: c,
                                ),
                            ],
                          ),
                          if (call != null)
                            _CallBlock(
                              label: l10n.keystoneReviewCalldata,
                              unknownLabel: l10n.keystoneReviewUnknownMethod,
                              call: call,
                              c: c,
                            ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: c.error.withAlpha(
                                c.neobrutalism ? 20 : 24,
                              ),
                              borderRadius: BorderRadius.circular(
                                c.neobrutalism ? Neo.radius : 12,
                              ),
                              border: Border.all(
                                color: c.neobrutalism
                                    ? c.neoEdge
                                    : c.error.withAlpha(80),
                                width: c.neobrutalism ? Neo.edge : 1,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (c.neobrutalism) ...[
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    size: 18,
                                    color: c.error,
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Text(
                                    l10n.keystoneReviewWarning,
                                    style: TextStyle(
                                      color: c.text,
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (failed) ...[
                            const SizedBox(height: 12),
                            Text(
                              l10n.keystoneErrorSigning,
                              key: const Key('keystone-review-error'),
                              style: TextStyle(color: c.error, fontSize: 13),
                            ),
                            if (widget.flow.errorDetail != null)
                              Text(
                                widget.flow.errorDetail!,
                                style: TextStyle(
                                  color: c.text.withAlpha(130),
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: AdaptiveActionButton(
                              key: const Key('keystone-review-reject'),
                              label: l10n.keystoneReject,
                              quiet: true,
                              legacyOutlineColor: c.error,
                              onTap: signing ? null : _reject,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AdaptiveActionButton(
                              key: const Key('keystone-review-approve'),
                              label: failed
                                  ? l10n.keystoneRetry
                                  : l10n.keystoneApprove,
                              loading: signing,
                              onTap: failed ? _retry : widget.flow.approve,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Detail rows as one block: a neo card in light mode, bare rows in dark.
class _DetailBlock extends StatelessWidget {
  final ColorTokens c;
  final List<Widget> children;

  const _DetailBlock({required this.c, required this.children});

  @override
  Widget build(BuildContext context) {
    if (!c.neobrutalism) return Column(children: children);
    return NeoCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(children: children),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final ColorTokens c;
  final bool mono;
  final bool emphasize;
  const _Row({
    required this.label,
    required this.value,
    required this.c,
    this.mono = false,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
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
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: TextStyle(
              color: c.text,
              fontSize: emphasize ? 14 : 13,
              fontWeight: emphasize ? FontWeight.w600 : FontWeight.w400,
              fontFamily: mono ? 'monospace' : null,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// calldata 单独成块：方法签名 + 逐个参数，认不出的方法退回原始十六进制。
class _CallBlock extends StatelessWidget {
  final String label;
  final String unknownLabel;
  final _DecodedCall call;
  final ColorTokens c;

  const _CallBlock({
    required this.label,
    required this.unknownLabel,
    required this.call,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    final known = call.params.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
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
          if (c.neobrutalism)
            NeoCard(padding: const EdgeInsets.all(10), child: _body(known))
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.text.withAlpha(40)),
              ),
              child: _body(known),
            ),
        ],
      ),
    );
  }

  Widget _body(bool known) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                call.title,
                style: TextStyle(
                  color: c.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            if (!known) ...[
              const SizedBox(width: 8),
              Text(
                unknownLabel,
                style: TextStyle(color: c.text.withAlpha(110), fontSize: 11),
              ),
            ],
          ],
        ),
        if (known) ...[
          const SizedBox(height: 6),
          for (final param in call.params)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SelectableText(
                '· $param',
                style: TextStyle(
                  color: c.text,
                  fontSize: 12,
                  fontFamily: 'monospace',
                  height: 1.35,
                ),
              ),
            ),
        ] else ...[
          const SizedBox(height: 6),
          SelectableText(
            call.rawHex,
            style: TextStyle(
              color: c.text.withAlpha(180),
              fontSize: 11,
              fontFamily: 'monospace',
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}
