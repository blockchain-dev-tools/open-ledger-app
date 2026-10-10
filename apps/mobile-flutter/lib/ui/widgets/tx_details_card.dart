import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../generated/l10n/app_localizations.dart';
import '../../utils/formatting.dart';
import '../theme/color_tokens.dart';

/// Read-only card that renders decoded transaction details.
///
/// Shared by the sign-approval screen and the History expanded row so both
/// surfaces show exactly the same fields. Dispatch is driven by the `type`
/// field of [parsedData] (`eth_tx` / `personal_msg` / `eip712` / `solana_tx`,
/// anything else → raw hex + size).
class TxDetailsCard extends StatefulWidget {
  /// Parsed payload from the Rust SDK. Null or empty → raw fallback.
  final Map<String, dynamic>? parsedData;

  /// Hex-encoded payload that was signed (raw fallback + size).
  final String payloadHex;

  /// Colour tokens for the active theme.
  final ColorTokens c;

  const TxDetailsCard({
    super.key,
    required this.parsedData,
    required this.payloadHex,
    required this.c,
  });

  /// Cached chain name map loaded from assets/chains.json.
  static Map<String, String>? _chainNames;

  /// Load chain names from assets JSON.
  static Future<void> loadChainNames() async {
    if (_chainNames != null) return;
    try {
      final json = await rootBundle.loadString('assets/chains.json');
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      _chainNames = decoded.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      _chainNames = {};
    }
  }

  /// Lookup chain name from loaded data.
  static String chainName(String chainId) {
    final name = _chainNames?[chainId];
    if (name != null) return '$name (ID: $chainId)';
    return 'Chain ID: $chainId';
  }

  @override
  State<TxDetailsCard> createState() => _TxDetailsCardState();
}

class _TxDetailsCardState extends State<TxDetailsCard> {
  /// Per-param decimals override. Key = "method:paramName", value = decimals.
  /// Default for uint256 is 18; user can tap +/- to adjust.
  final Map<String, int> _decimalsOverrides = {};

  bool _dataExpanded = false;

  ColorTokens get c => widget.c;

  /// Track current method name for decimals override key.
  String get _currentMethod {
    final action = widget.parsedData?['action'];
    if (action is Map) return (action['method'] as String?) ?? '';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final parsed = widget.parsedData;

    if (parsed == null || parsed.isEmpty) {
      return _card(
        Column(
          children: [
            _rawDataRow(
                c,
                AppLocalizations.of(context)!.dataHex,
                '0x${widget.payloadHex.substring(0, widget.payloadHex.length.clamp(0, 64))}${widget.payloadHex.length > 64 ? '...' : ''}'),
            const SizedBox(height: 8),
            _rawDataRow(c, AppLocalizations.of(context)!.dataSize,
                '${widget.payloadHex.length ~/ 2} bytes'),
          ],
        ),
      );
    }

    final type = parsed['type'] as String?;

    switch (type) {
      case 'eth_tx':
        return _buildEthTxDetails(parsed);
      case 'personal_msg':
        return _buildPersonalMsgDetails(parsed);
      case 'eip712':
        return _buildEip712Details(parsed);
      case 'solana_tx':
        return _buildSolanaTxDetails(parsed);
      default:
        return _buildRawDetails(parsed);
    }
  }

  Widget _card(Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: c.border.withAlpha(80)),
      ),
      child: child,
    );
  }

  Widget _buildEthTxDetails(Map<String, dynamic> data) {
    return _card(
      Column(
        children: [
          _detailRow(c, AppLocalizations.of(context)!.chain,
              TxDetailsCard.chainName(data['chainId'] as String? ?? '0')),
          const SizedBox(height: 10),
          Container(height: 1, color: c.border.withAlpha(60)),
          const SizedBox(height: 10),
          _buildAddressRow(c, AppLocalizations.of(context)!.to, data['to'] as String? ?? ''),
          const SizedBox(height: 10),
          Container(height: 1, color: c.border.withAlpha(60)),
          const SizedBox(height: 10),
          _detailRow(c, AppLocalizations.of(context)!.value,
              '${weiToEth(data['value'] as String? ?? '0')} ETH'),
          const SizedBox(height: 10),
          Container(height: 1, color: c.border.withAlpha(60)),
          const SizedBox(height: 10),
          _detailRow(c, 'Type', data['txType'] as String? ?? 'legacy'),
          const SizedBox(height: 10),
          Container(height: 1, color: c.border.withAlpha(60)),
          const SizedBox(height: 10),
          _detailRow(c, AppLocalizations.of(context)!.gasLimit, data['gas'] as String? ?? ''),
          const SizedBox(height: 10),
          Container(height: 1, color: c.border.withAlpha(60)),
          const SizedBox(height: 10),
          _detailRow(c, _gasPriceLabel(data['txType'] as String? ?? ''),
              '${weiToGwei(data['gasPrice'] as String? ?? '0')} Gwei'),
          if (data['txType'] == 'eip1559' && data['priorityFee'] != null) ...[
            const SizedBox(height: 10),
            Container(height: 1, color: c.border.withAlpha(60)),
            const SizedBox(height: 10),
            _detailRow(c, AppLocalizations.of(context)!.priorityFee,
                '${weiToGwei(data['priorityFee'] as String? ?? '0')} Gwei'),
          ],
          if (data['nonce'] != null && (data['nonce'] as String?) != '0') ...[
            const SizedBox(height: 10),
            Container(height: 1, color: c.border.withAlpha(60)),
            const SizedBox(height: 10),
            _detailRow(c, AppLocalizations.of(context)!.nonce, data['nonce'] as String? ?? ''),
          ],
          if (data['data'] != null && (data['data'] as String?) != '0x') ...[
            const SizedBox(height: 10),
            Container(height: 1, color: c.border.withAlpha(60)),
            const SizedBox(height: 10),
            _buildDataField(data['data'] as String? ?? ''),
          ],
          if (data['action'] is Map) ...[
            const SizedBox(height: 10),
            Container(height: 1, color: c.border.withAlpha(60)),
            const SizedBox(height: 10),
            _buildDecodedAction(data['action'] as Map<String, dynamic>),
          ],
        ],
      ),
    );
  }

  /// Build the details card for a Solana transaction message summary.
  Widget _buildSolanaTxDetails(Map<String, dynamic> data) {
    final to = data['to'] as String?;
    final lamports = data['lamports'] as String?;
    final programId = data['programId'] as String?;
    final version = data['version'] as String? ?? 'legacy';

    final children = <Widget>[];
    void addSeparated(Widget w) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 10));
        children.add(Container(height: 1, color: c.border.withAlpha(60)));
        children.add(const SizedBox(height: 10));
      }
      children.add(w);
    }

    if (to != null && to.isNotEmpty) {
      addSeparated(_buildAddressRow(c, AppLocalizations.of(context)!.to, to));
    }
    if (lamports != null) {
      addSeparated(_detailRow(
        c,
        AppLocalizations.of(context)!.amount,
        '${_formatWithDecimals(lamports, 9)} SOL',
      ));
    }
    if (programId != null && programId.isNotEmpty) {
      addSeparated(_buildAddressRow(c, 'Program', programId));
    }
    addSeparated(_detailRow(c, 'Type', version));

    return _card(Column(children: children));
  }

  /// Build a human-readable row for a decoded contract action (e.g. ERC-20 transfer).
  Widget _buildDecodedAction(Map<String, dynamic> action) {
    final method = action['method'] as String?;
    final params = action['params'] as List<dynamic>?;
    if (method == null || params == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.code, size: 16, color: c.primary),
            const SizedBox(width: 6),
            Text(
              AppLocalizations.of(context)!.decodedAction,
              style: TextStyle(
                color: c.primary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _detailRow(c, AppLocalizations.of(context)!.methodLabel, method),
        ...params.map((p) {
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _buildParamRow(p as Map<String, dynamic>),
          );
        }),
      ],
    );
  }

  /// Build a display row for a single decoded param, handling nested types.
  Widget _buildParamRow(Map<String, dynamic> param) {
    final name = (param['name'] as String?) ?? '';
    final value = (param['value'] as String?) ?? '';
    final type = (param['type'] as String?) ?? '';

    if (type == 'address') {
      return _buildAddressRow(c, name, value);
    }

    if (type == 'tuple' || type == 'tuple[]') {
      // value is JSON string of nested params
      List<dynamic> nested;
      try {
        nested = jsonDecode(value) as List<dynamic>;
      } catch (_) {
        return _detailRow(c, _paramLabel(name), value);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _paramLabel(name),
            style: TextStyle(
              color: c.text.withAlpha(150),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: nested.map((e) {
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _buildParamRow(e as Map<String, dynamic>),
                );
              }).toList(),
            ),
          ),
        ],
      );
    }

    if (type.startsWith('uint') || type.startsWith('int')) {
      return _buildUintRow(name, value, type);
    }

    if (type == 'bool') {
      return _detailRow(c, _paramLabel(name), value == 'true' ? 'Yes' : 'No');
    }

    if (type == 'bytes' || type == 'bytes32') {
      final display = value.length > 20
          ? '${value.substring(0, 18)}...'
          : value;
      return _detailRow(c, _paramLabel(name), display);
    }

    if (type == 'string') {
      return _detailRow(c, _paramLabel(name), value);
    }

    // address[] / uint256[] etc.
    if (type.endsWith('[]')) {
      List<dynamic> arr;
      try {
        arr = jsonDecode(value) as List<dynamic>;
      } catch (_) {
        return _detailRow(c, _paramLabel(name), value);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_paramLabel(name)} (${arr.length})',
            style: TextStyle(
              color: c.text.withAlpha(150),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              children: arr.asMap().entries.map((e) {
                return Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _detailRow(c, '#${e.key}', e.value.toString()),
                );
              }).toList(),
            ),
          ),
        ],
      );
    }

    return _detailRow(c, _paramLabel(name), value);
  }

  /// Build a row for an address with highlighted prefix/suffix.
  Widget _buildAddressRow(ColorTokens c, String name, String address) {
    final prefix = address.length > 12 ? address.substring(0, 6) : address;
    final suffix = address.length > 12 ? address.substring(address.length - 6) : '';
    final middle = address.length > 12 ? address.substring(6, address.length - 6) : '';

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              _paramLabel(name),
              style: TextStyle(color: c.text.withAlpha(130), fontSize: 13),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SelectableText.rich(
              TextSpan(
                style: const TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
                children: [
                  TextSpan(
                    text: prefix,
                    style: TextStyle(
                      color: c.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (middle.isNotEmpty)
                    TextSpan(
                      text: middle,
                      style: TextStyle(color: c.text),
                    ),
                  if (suffix.isNotEmpty)
                    TextSpan(
                      text: suffix,
                      style: TextStyle(
                        color: c.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  String _gasPriceLabel(String txType) {
    if (txType == 'eip1559') return AppLocalizations.of(context)!.maxFee;
    return AppLocalizations.of(context)!.gasPrice;
  }

  /// Data field with expand/collapse — default max 3 lines.
  Widget _buildDataField(String dataHex) {
    final bytes = dataHex.startsWith('0x') ? (dataHex.length - 2) ~/ 2 : dataHex.length ~/ 2;

    return StatefulBuilder(
      builder: (context, setInnerState) {
        final expanded = _dataExpanded;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    'Data',
                    style: TextStyle(color: c.text.withAlpha(130), fontSize: 13),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    setInnerState(() {
                      _dataExpanded = !_dataExpanded;
                    });
                  },
                  child: Text(
                    expanded ? AppLocalizations.of(context)!.showLess : AppLocalizations.of(context)!.showAll(bytes),
                    style: TextStyle(color: c.primary, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(
              dataHex,
              maxLines: expanded ? null : 3,
              style: TextStyle(
                color: c.text.withAlpha(180),
                fontSize: 11,
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Build a row for uint/int with adjustable decimals.
  Widget _buildUintRow(String name, String rawValue, String type) {
    final key = '$_currentMethod:$name';
    final decimals = _decimalsOverrides[key] ?? 18;
    final formatted = _formatWithDecimals(rawValue, decimals);

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              _paramLabel(name),
              style: TextStyle(color: c.text.withAlpha(130), fontSize: 13),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SelectableText(
                  formatted,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.right,
                ),
                Text(
                  'dec: $decimals',
                  style: TextStyle(
                    color: c.text.withAlpha(100),
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          // Decimals adjuster
          Column(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _decimalsOverrides[key] = (_decimalsOverrides[key] ?? 18) + 1;
                  });
                },
                child: Icon(Icons.arrow_drop_up, size: 18, color: c.text.withAlpha(120)),
              ),
              InkWell(
                onTap: () {
                  setState(() {
                    final current = _decimalsOverrides[key] ?? 18;
                    if (current > 0) {
                      _decimalsOverrides[key] = current - 1;
                    }
                  });
                },
                child: Icon(Icons.arrow_drop_down, size: 18, color: c.text.withAlpha(120)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Format a raw integer string with N decimal places.
  /// "1000000000000000000" / 18 → "1.0"
  String _formatWithDecimals(String raw, int decimals) {
    if (raw.isEmpty || raw == '0') return '0';
    final padded = raw.padLeft(decimals + 1, '0');
    final intPart = padded.substring(0, padded.length - decimals);
    final decPart = padded.substring(padded.length - decimals);
    final trimmed = decPart.replaceAll(RegExp(r'0+$'), '');
    final dec = trimmed.isEmpty ? '' : '.$trimmed';
    return '$intPart$dec';
  }

  /// Convert snake_case param name to display label.
  String _paramLabel(String name) {
    if (name == 'spender') return AppLocalizations.of(context)!.spender;
    if (name == 'amount') return AppLocalizations.of(context)!.amount;
    if (name == 'from') return 'From';
    if (name == 'to') return 'To';
    if (name.isEmpty) return '';
    return name[0].toUpperCase() + name.substring(1);
  }

  Widget _buildPersonalMsgDetails(Map<String, dynamic> data) {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.messageToSign,
            style: TextStyle(
              color: c.text.withAlpha(130),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: SelectableText(
              data['message'] as String? ?? '',
              style: TextStyle(
                color: c.text,
                fontSize: 14,
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEip712Details(Map<String, dynamic> data) {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.eip712TypedData,
            style: TextStyle(
              color: c.primary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            AppLocalizations.of(context)!.domainHash,
            style: TextStyle(color: c.text.withAlpha(130), fontSize: 12),
          ),
          const SizedBox(height: 4),
          SelectableText(
            data['domainHash'] as String? ?? '',
            style: TextStyle(
              color: c.text,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            AppLocalizations.of(context)!.structHash,
            style: TextStyle(color: c.text.withAlpha(130), fontSize: 12),
          ),
          const SizedBox(height: 4),
          SelectableText(
            data['structHash'] as String? ?? '',
            style: TextStyle(
              color: c.text,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRawDetails(Map<String, dynamic> data) {
    final hex = data['hex'] as String? ?? '';
    final size = data['size'] as int? ?? 0;
    final displayHex = hex.length > 80 ? '${hex.substring(0, 80)}...' : hex;

    return _card(
      Column(
        children: [
          _rawDataRow(c, 'Hex', displayHex),
          const SizedBox(height: 8),
          Container(height: 1, color: c.border.withAlpha(60)),
          const SizedBox(height: 8),
          _rawDataRow(c, 'Size', '$size bytes'),
        ],
      ),
    );
  }

  static Widget _detailRow(ColorTokens c, String label, String value) {
    final truncated = value.length > 50
        ? '${value.substring(0, 50)}...'
        : value;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(color: c.text.withAlpha(130), fontSize: 13),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            truncated,
            style: TextStyle(
              color: c.text,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  static Widget _rawDataRow(ColorTokens c, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: c.text.withAlpha(130), fontSize: 13),
        ),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              color: c.text,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
