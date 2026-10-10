"""最小 RLP 编码器（构造 legacy ETH 交易用）。"""
from __future__ import annotations


def encode(item) -> bytes:
    if isinstance(item, int):
        if item == 0:
            return b"\x80"
        return encode(item.to_bytes((item.bit_length() + 7) // 8, "big"))
    if isinstance(item, (bytes, bytearray)):
        data = bytes(item)
        if len(data) == 1 and data[0] < 0x80:
            return data
        return _len_prefix(len(data), 0x80) + data
    if isinstance(item, list):
        payload = b"".join(encode(x) for x in item)
        return _len_prefix(len(payload), 0xC0) + payload
    raise TypeError(f"无法 RLP 编码: {type(item)}")


def _len_prefix(length: int, offset: int) -> bytes:
    if length < 56:
        return bytes([offset + length])
    length_bytes = length.to_bytes((length.bit_length() + 7) // 8, "big")
    return bytes([offset + 55 + len(length_bytes)]) + length_bytes


def legacy_tx(
    nonce: int = 0,
    gas_price: int = 1_000_000_000,
    gas_limit: int = 21000,
    to: bytes = bytes.fromhex("3535353535353535353535353535353535353535"),
    value: int = 1000,
    data: bytes = b"",
) -> bytes:
    """返回一笔 legacy 交易的 RLP 字节（6 字段，含待签名部分）。"""
    return encode([nonce, gas_price, gas_limit, to, value, data])
