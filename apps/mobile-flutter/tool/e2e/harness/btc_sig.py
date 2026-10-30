"""设备签名 → Bitcoin 的 DER 编码。

设备的响应是 `[27+recid][r][s]`（65 字节，compact），而 Bitcoin 的 witness
里的签名是 `DER(r,s) || sighash_type`。这个转换只是格式适配，不改变签名值；
设备侧缺陷（例如 r/s 编码、low-S）仍会在这里暴露为节点拒绝。
"""
from __future__ import annotations


def _der_int(value: bytes) -> bytes:
    """DER INTEGER：去掉多余前导零，最高位为 1 时补一个 0x00。"""
    stripped = value.lstrip(b"\x00") or b"\x00"
    if stripped[0] & 0x80:
        stripped = b"\x00" + stripped
    return b"\x02" + bytes([len(stripped)]) + stripped


def compact_to_der(compact: bytes, sighash_type: int = 0x01) -> bytes:
    """65 字节 compact 签名 → `DER || sighash_type`。"""
    if len(compact) != 65:
        raise ValueError(f"expected a 65-byte compact signature, got {len(compact)}")
    r, s = compact[1:33], compact[33:65]
    body = _der_int(r) + _der_int(s)
    return b"\x30" + bytes([len(body)]) + body + bytes([sighash_type])
