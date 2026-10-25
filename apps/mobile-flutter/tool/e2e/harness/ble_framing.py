"""Tag-first BLE framing, shared by every GATT transport.

Wire format (see `docs/reference/ble.md`):

- first chunk:  `[tag][seq_hi][seq_lo][total_hi][total_lo][payload]`
- continuation: `[tag][seq_hi][seq_lo][payload]`

Both directions use the same shape. Tag `0x05` carries APDU bytes, `0x08` asks
for the MTU (the reply is a 7-byte frame whose payload is the 2-byte MTU).

Kept free of dbus/gi imports so macOS transports can reuse it.
"""
from __future__ import annotations

TAG_APDU = 0x05
TAG_GET_MTU = 0x08
DEFAULT_MTU = 20


def fragment(apdu: bytes, mtu: int = DEFAULT_MTU, tag: int = TAG_APDU) -> list[bytes]:
    """切分成 tag-first 帧（首块 5B 头 / 续块 3B 头）。"""
    first_cap = mtu - 5
    cont_cap = mtu - 3
    chunks: list[bytes] = []
    offset = 0
    total = len(apdu)
    seq = 0
    while offset < total or seq == 0:
        if seq == 0:
            payload = apdu[offset:offset + first_cap]
            chunks.append(bytes([tag, (seq >> 8) & 0xFF, seq & 0xFF,
                                 (total >> 8) & 0xFF, total & 0xFF]) + payload)
            offset += len(payload)
        else:
            payload = apdu[offset:offset + cont_cap]
            chunks.append(bytes([tag, (seq >> 8) & 0xFF, seq & 0xFF]) + payload)
            offset += len(payload)
        seq += 1
    return chunks


class Reassembler:
    """按 seq 组装 tag-first 帧，凑齐 total 后返回完整 payload。"""

    def __init__(self) -> None:
        self._parts: dict[int, bytes] = {}
        self._total: int | None = None
        self._got = 0
        self.result: bytes | None = None

    def feed(self, chunk: bytes) -> bytes | None:
        if len(chunk) < 3:
            return None
        seq = (chunk[1] << 8) | chunk[2]
        if seq == 0 and len(chunk) >= 5:
            self._total = (chunk[3] << 8) | chunk[4]
            payload = chunk[5:]
        else:
            payload = chunk[3:]
        if seq not in self._parts:
            self._parts[seq] = payload
            self._got += len(payload)
        if self._total is not None and self._got >= self._total:
            ordered = b"".join(self._parts[i] for i in sorted(self._parts))
            self.result = ordered[:self._total]
            self._reset()
            return self.result
        return None

    def _reset(self) -> None:
        self._parts.clear()
        self._total = None
        self._got = 0
