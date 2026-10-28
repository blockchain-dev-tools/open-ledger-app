"""独立的 base58 / base58check 编码（用于 Solana / Tron 地址断言）。

刻意不复用设备侧 Rust 实现：这里只用 Python 标准库。
"""
from __future__ import annotations

import hashlib

_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"


def encode(data: bytes) -> str:
    """裸 base58 编码。"""
    value = int.from_bytes(data, "big")
    out = ""
    while value:
        value, rem = divmod(value, 58)
        out = _ALPHABET[rem] + out
    # 前导 0x00 变成 '1'
    pad = 0
    for byte in data:
        if byte != 0:
            break
        pad += 1
    return "1" * pad + out


def encode_check(data: bytes) -> str:
    """base58check：data || SHA256d(data)[:4]。"""
    checksum = hashlib.sha256(hashlib.sha256(data).digest()).digest()[:4]
    return encode(data + checksum)
