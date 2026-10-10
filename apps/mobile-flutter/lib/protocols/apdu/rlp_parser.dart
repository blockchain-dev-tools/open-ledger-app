/// RLP (Recursive Length Prefix) total-length calculator.
///
/// Ported from open-ledger-mono: `packages/apdu/src/parser.ts` — `rlpTotalLength`.
///
/// Returns the expected total byte length of an RLP-encoded item from
/// its leading byte(s), or `-1` if the available bytes are insufficient
/// to determine the length.
///
/// Handles EIP-2718 typed transactions (type prefix `0x01` or `0x02`
/// before the RLP list).
library;

/// Returns expected total byte length from leading RLP byte(s), or -1
/// if incomplete.
///
/// [bytes] may be a full or partial RLP stream. Only the leading
/// length-encoding byte(s) are examined.
///
/// RLP length-encoding rules:
/// - `[0x00, 0x7f]`   — single byte itself (length = 1)
/// - `[0x80, 0xb7]`   — short string: length = 1 + (first - 0x80)
/// - `[0xb8, 0xbf]`   — long string: next N bytes give the payload length
/// - `[0xc0, 0xf7]`   — short list: length = 1 + (first - 0xc0)
/// - `[0xf8, 0xff]`   — long list: next N bytes give the payload length
///
/// For EIP-2718 typed transactions, the first byte is a type prefix
/// (`0x01` = EIP-2930, `0x02` = EIP-1559) that is NOT part of the RLP
/// encoding. The RLP length is computed from the byte after the prefix,
/// and the type prefix is added to the total.
int rlpTotalLength(List<int> bytes) {
  if (bytes.isEmpty) return -1;

  // Skip EIP-2718 transaction type byte (0x01 = EIP-2930, 0x02 = EIP-1559).
  final offset = (bytes[0] == 0x01 || bytes[0] == 0x02) ? 1 : 0;

  if (bytes.length <= offset) return -1;

  final first = bytes[offset];

  // Single byte (0x00–0x7f): the byte itself is the value.
  if (first < 0x80) return offset + 1;

  // Short string (0x80–0xb7): 1 byte header + (first - 0x80) payload.
  if (first < 0xb8) return offset + 1 + (first - 0x80);

  // Long string (0xb8–0xbf): 1 byte header + lb length-bytes + payload.
  if (first < 0xc0) {
    final lb = first - 0xb7;
    if (bytes.length < offset + 1 + lb) return -1;
    int len = 0;
    for (int i = 1; i <= lb; i++) {
      len = (len << 8) | bytes[offset + i];
    }
    return offset + 1 + lb + len;
  }

  // Short list (0xc0–0xf7): 1 byte header + (first - 0xc0) payload.
  if (first < 0xf8) return offset + 1 + (first - 0xc0);

  // Long list (0xf8–0xff): 1 byte header + lb length-bytes + payload.
  final lb = first - 0xf7;
  if (bytes.length < offset + 1 + lb) return -1;
  int len = 0;
  for (int i = 1; i <= lb; i++) {
    len = (len << 8) | bytes[offset + i];
  }
  return offset + 1 + lb + len;
}
