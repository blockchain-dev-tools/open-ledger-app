/// Stateful decoder that turns raw BLE log lines into [BleLogEntry] items
/// with **decoded** command parameters and response content.
///
/// Tracks the last received command (CLA/INS) so the following response can
/// be decoded in context:
/// - a `GET_PUBKEY` response → the derived address,
/// - a `GET_APP_AND_VERSION` response → "Ethereum 1.10.3",
/// - a sign response → `v` / `r` / `s`.
///
/// Command lines decode their parameters (BIP-32 path, payload sizes, app
/// name, …). The raw hex line is kept as the expandable [BleLogEntry.detail].
library;

import 'dart:typed_data';

import '../../core/models/ble_log_entry.dart';
import 'apdu_command_name.dart';
import 'apdu_constants.dart';

class ApduLogDecoder {
  /// Last received command — used to decode the matching response content.
  int? _lastCla;
  int? _lastIns;

  /// Command awaiting its response.
  ///
  /// Set by an `APDU command received:` line and consumed by the next
  /// `APDU response:` line, so a request and its reply collapse into a
  /// single log entry (the command row is emitted as [BleLogStatus.pending]
  /// and replaced in place when the response arrives).
  _PendingCommand? _pending;

  /// Decode [rawLine], or return `null` for fragment-level chatter that
  /// would only duplicate an already-logged APDU.
  ///
  /// Hidden lines: `GATT write:` (raw characteristic writes, one per
  /// fragment) and `APDU incoming:` (reassembly progress). The assembled
  /// command/response is logged separately as `APDU command received:` /
  /// `APDU response:`.
  BleLogEntry? decode(String rawLine) {
    if (rawLine.startsWith('GATT write:') ||
        rawLine.startsWith('APDU incoming:')) {
      return null;
    }

    final level = _levelOf(rawLine);

    // ── APDU command received: <hex>  → pending request entry ─────────
    if (rawLine.startsWith('APDU command received:')) {
      final hex = rawLine.substring('APDU command received:'.length).trim();
      final bytes = _hexToBytes(hex);
      if (bytes == null || bytes.length < 5) {
        return BleLogEntry(
            summary: rawLine,
            detail: rawLine,
            level: level,
            status: BleLogStatus.idle,
            raw: rawLine);
      }
      _lastCla = bytes[0];
      _lastIns = bytes[1];
      final pending = _PendingCommand(
        name: apduCommandName(bytes),
        params: _decodeCommandParams(bytes),
        hex: hex,
      );
      _pending = pending;
      return BleLogEntry(
          summary: '${pending.label}  →  …',
          detail: 'IN  $hex',
          level: level,
          status: BleLogStatus.pending,
          raw: rawLine);
    }

    // ── APDU response: <hex>  → resolve the pending request ───────────
    if (rawLine.startsWith('APDU response:')) {
      final hex = rawLine.substring('APDU response:'.length).trim();
      final bytes = _hexToBytes(hex);
      final sw = (bytes != null && bytes.length >= 2)
          ? (bytes[bytes.length - 2] << 8) | bytes[bytes.length - 1]
          : null;
      final swLabel = sw != null ? swName(sw) : '?';
      final payload = (bytes != null && bytes.length >= 2)
          ? bytes.sublist(0, bytes.length - 2)
          : Uint8List(0);
      final content = _decodeResponseContent(payload);
      final ok = sw == Sw.success;

      final pending = _pending;
      _pending = null;
      final label = pending?.label ?? 'response';
      final summary = content.isEmpty
          ? '$label  →  $swLabel'
          : '$label  →  $content ($swLabel)';
      final detail = [
        if (pending != null) 'IN  ${pending.hex}',
        'OUT $hex',
      ].join('\n');
      return BleLogEntry(
          summary: summary,
          detail: detail,
          level: ok ? level : BleLogLevel.error,
          status: ok ? BleLogStatus.success : BleLogStatus.error,
          raw: rawLine);
    }

    // ── ⚠ APDU response send error: <msg>  → resolved (failure) ──────
    if (rawLine.contains('APDU response send error')) {
      final msg = rawLine.replaceFirst('⚠ APDU response send error: ', '');
      return BleLogEntry(
          summary: '⚠ APDU response error: ${msg.trim()}',
          detail: rawLine,
          level: BleLogLevel.error,
          status: BleLogStatus.error,
          raw: rawLine);
    }

    // ── Other lines: plain, non-expandable ───────────────────────────
    return BleLogEntry(
        summary: rawLine,
        detail: null,
        level: level,
        status: BleLogStatus.idle,
        raw: rawLine);
  }

  // ── Command parameter decoding ──────────────────────────────────────

  /// Decodes the data field of a command into readable parameters.
  String _decodeCommandParams(Uint8List apdu) {
    final cla = apdu[0];
    final ins = apdu[1];
    final p1 = apdu[2];
    final p2 = apdu[3];
    final lc = apdu[4];
    final dataLen = lc < (apdu.length - 5) ? lc : (apdu.length - 5);
    final data = dataLen > 0 ? apdu.sublist(5, 5 + dataLen) : Uint8List(0);

    // Commands with no data field. P1/P2 are only surfaced when non-zero,
    // so no-argument commands stay readable in the collapsed row.
    if (data.isEmpty) {
      if ((cla == Cla.global && ins == Ins.getVersion) ||
          (cla == Cla.os && ins == Ins.getVersion)) {
        return '';
      }
      if (p1 == 0 && p2 == 0) return '';
      return 'P1=${_h(p1)} P2=${_h(p2)}';
    }

    // SOL_GET_ADDR: data = BIP-32 path (hardened levels only).
    if (cla == Cla.os && ins == Ins.solGetAddress) {
      return 'path=${_decodePath(data)}';
    }

    // GET_PUBKEY (ETH / Tron / Sui): data = BIP-32 path.
    final isGetPubkey = (cla == Cla.os && ins == Ins.getPublicKey) ||
        (cla == Cla.tron && ins == Ins.tronGetPublicKey) ||
        (cla == Cla.sui && ins == Ins.suiGetPublicKey);
    if (isGetPubkey) {
      return 'P1=${_h(p1)} P2=${_h(p2)} path=${_decodePath(data)}';
    }

    // ETH_SIGN_TX: data = path + RLP-encoded tx.
    // P1=0x02/0x42 = inline EIP-712: data = path + domain_hash(32) + struct_hash(32).
    if (cla == Cla.os && ins == Ins.ethSign) {
      final path = _decodePath(data);
      final consumed = 1 + (_pathCount(data) * 4);
      if (p1 == 0x02 || p1 == 0x42) {
        final hashLen = data.length - consumed;
        return 'path=$path hash=$hashLen bytes';
      }
      final rlpLen = data.length - consumed;
      return 'path=$path RLP=$rlpLen bytes';
    }

    // ETH_SIGN_PERSONAL_MESSAGE: data = path + len(4) + message.
    if (cla == Cla.os && ins == Ins.signEthPersonalMessage) {
      final path = _decodePath(data);
      final consumed = 1 + (_pathCount(data) * 4);
      var msgLen = 0;
      if (data.length >= consumed + 4) {
        msgLen = (data[consumed] << 24) |
            (data[consumed + 1] << 16) |
            (data[consumed + 2] << 8) |
            (data[consumed + 3]);
      }
      return 'path=$path msg=$msgLen bytes';
    }

    // EIP-712: data = path + domain_hash(32) + struct_hash(32).
    if (cla == Cla.os && ins == Ins.ethSignEip712) {
      final path = _decodePath(data);
      final consumed = 1 + (_pathCount(data) * 4);
      final hashLen = data.length - consumed;
      return 'path=$path hash=$hashLen bytes';
    }

    // OPEN_APP: data = app name (ASCII).
    if (cla == Cla.os && ins == 0xD8) {
      final name = String.fromCharCodes(
          data.where((b) => b >= 0x20 && b < 0x7f));
      return '"$name"';
    }

    // Generic fallback.
    return 'P1=${_h(p1)} P2=${_h(p2)} Lc=$lc data=${data.length} bytes';
  }

  // ── Response content decoding (context = last command) ──────────────

  String _decodeResponseContent(Uint8List payload) {
    if (payload.isEmpty) return '';

    final cla = _lastCla;
    final ins = _lastIns;

    // GET_APP_AND_VERSION:
    //   01 [name_len][name][ver_len][version][flags_len][flags]
    if (cla == Cla.global &&
        ins == Ins.getVersion &&
        payload[0] == 0x01) {
      var i = 1;
      final name = _readString(payload, i);
      i += 1 + name.length;
      final version = _readString(payload, i);
      if (name.isNotEmpty || version.isNotEmpty) {
        return '$name $version'.trim();
      }
    }

    // GET_PUBKEY (ETH/Tron/Sui):
    //   [pubkey_len][pubkey 65B][addr_len][addr ASCII hex]
    final isGetPubkey = (cla == Cla.os && ins == Ins.getPublicKey) ||
        (cla == Cla.tron && ins == Ins.tronGetPublicKey) ||
        (cla == Cla.sui && ins == Ins.suiGetPublicKey);
    if (isGetPubkey) {
      final pubkeyLen = payload[0];
      var i = 1 + pubkeyLen;
      if (i < payload.length) {
        final addrLen = payload[i];
        final end = i + 1 + addrLen;
        if (end <= payload.length) {
          final addr = String.fromCharCodes(payload.sublist(i + 1, end));
          if (addr.isNotEmpty) return 'address=0x$addr';
        }
      }
    }

    // SOL_GET_ADDR: bare 32-byte Ed25519 pubkey → base58 address.
    if (cla == Cla.os && ins == Ins.solGetAddress && payload.length == 32) {
      return _base58Encode(payload);
    }

    // Sign responses: [v][r 32B][s 32B] (secp256k1 chains; Solana's 64-byte
    // Ed25519 signature falls through to the generic hex preview).
    final isSign = cla == Cla.os &&
        (ins == Ins.ethSign ||
            ins == Ins.signEthPersonalMessage ||
            ins == Ins.ethSignEip712);
    if (isSign && payload.length >= 65) {
      final v = payload[0];
      final r = _bytesToHex(payload.sublist(1, 33));
      final s = _bytesToHex(payload.sublist(33, 65));
      return 'v=$v r=0x$r s=0x$s';
    }

    // Fallback: payload size + short preview.
    final preview = payload.length > 8
        ? '${_bytesToHex(payload.sublist(0, 8))}…'
        : _bytesToHex(payload);
    return '${payload.length} bytes: $preview';
  }

  // ── BIP-32 path decoding ─────────────────────────────────────────────

  int _pathCount(Uint8List data) => data.isEmpty ? 0 : data[0];

  String _decodePath(Uint8List data) {
    if (data.isEmpty) return '(none)';
    final count = data[0];
    if (count == 0 || data.length < 1 + count * 4) return '(invalid)';
    final parts = <String>[];
    for (var i = 0; i < count; i++) {
      final off = 1 + i * 4;
      final val = (data[off] << 24) |
          (data[off + 1] << 16) |
          (data[off + 2] << 8) |
          data[off + 3];
      final hardened = (val & 0x80000000) != 0;
      final idx = val & 0x7fffffff;
      parts.add('$idx${hardened ? "'" : ''}');
    }
    return parts.join('/');
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  String _readString(Uint8List data, int off) {
    if (off >= data.length) return '';
    final len = data[off];
    final end = off + 1 + len;
    if (end > data.length) return '';
    return String.fromCharCodes(data.sublist(off + 1, end));
  }

  static String _h(int b) =>
      '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}';

  static String _bytesToHex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static BleLogLevel _levelOf(String line) {
    if (line.startsWith('\u26a0 ')) return BleLogLevel.warn;
    if (line.contains(' error') || line.contains('Error')) {
      return BleLogLevel.error;
    }
    return BleLogLevel.info;
  }

  static Uint8List? _hexToBytes(String hex) {
    final clean = hex.replaceAll(RegExp(r'\s+'), '');
    if (clean.isEmpty || clean.length.isOdd) return null;
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final byte = int.tryParse(clean.substring(i * 2, i * 2 + 2), radix: 16);
      if (byte == null) return null;
      out[i] = byte;
    }
    return out;
  }

  static const String _b58Alphabet =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

  /// Encode [bytes] as base58 (Bitcoin/Solana alphabet) — used to show a
  /// Solana public key the same way wallets do.
  static String _base58Encode(Uint8List bytes) {
    if (bytes.isEmpty) return '';
    var zeros = 0;
    while (zeros < bytes.length && bytes[zeros] == 0) {
      zeros++;
    }

    final encoded = List<int>.filled(
        (bytes.length - zeros) * 138 ~/ 100 + 1, 0);
    var length = 0;
    for (var i = zeros; i < bytes.length; i++) {
      var carry = bytes[i];
      var j = 0;
      for (var k = encoded.length - 1; (carry != 0 || j < length) && k >= 0;
          k--, j++) {
        carry += 256 * encoded[k];
        encoded[k] = carry % 58;
        carry ~/= 58;
      }
      length = j;
    }

    var start = encoded.length - length;
    while (start < encoded.length && encoded[start] == 0) {
      start++;
    }
    final sb = StringBuffer();
    for (var i = 0; i < zeros; i++) {
      sb.write('1');
    }
    for (var i = start; i < encoded.length; i++) {
      sb.write(_b58Alphabet[encoded[i]]);
    }
    return sb.toString();
  }
}

/// A received command waiting for its response — carries everything needed
/// to render the collapsed row (`NAME params  →  response summary`) once
/// the matching `APDU response:` line arrives.
class _PendingCommand {
  final String name;
  final String params;
  final String hex;

  const _PendingCommand({
    required this.name,
    required this.params,
    required this.hex,
  });

  /// Command name plus decoded parameters, e.g. `SOL_GET_ADDR path=44'/501'/0'/0'`.
  String get label => params.isEmpty ? name : '$name $params';
}
