"""独立的 Bitcoin P2WPKH 地址编码（BIP-173 bech32 + hash160）。

派生在 JS 侧（`ethverify.mjs` 的 `derive`，BIP-32），地址编码在这里用
Python 标准库完成：与设备侧 Rust 实现是两套独立代码。

`derive_address()` 返回的是 65B 未压缩公钥，这里先压缩再取 hash160，
与 BIP-84 的 P2WPKH 约定一致。
"""
from __future__ import annotations

import hashlib

_CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
_GENERATOR = (0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3)
_BECH32_CONST = 1
_BECH32M_CONST = 0x2BC830A3


def _polymod(values: list[int]) -> int:
    chk = 1
    for value in values:
        top = chk >> 25
        chk = (chk & 0x1FFFFFF) << 5 ^ value
        for index in range(5):
            if (top >> index) & 1:
                chk ^= _GENERATOR[index]
    return chk


def _hrp_expand(hrp: str) -> list[int]:
    return [ord(c) >> 5 for c in hrp] + [0] + [ord(c) & 31 for c in hrp]


def _create_checksum(hrp: str, data: list[int], const: int = _BECH32_CONST) -> list[int]:
    values = _hrp_expand(hrp) + data
    polymod = _polymod(values + [0, 0, 0, 0, 0, 0]) ^ const
    return [(polymod >> 5 * (5 - index)) & 31 for index in range(6)]


def _convertbits(data: bytes, from_bits: int, to_bits: int) -> list[int]:
    acc = 0
    bits = 0
    out: list[int] = []
    maxv = (1 << to_bits) - 1
    for value in data:
        acc = (acc << from_bits) | value
        bits += from_bits
        while bits >= to_bits:
            bits -= to_bits
            out.append((acc >> bits) & maxv)
    if bits:
        out.append((acc << (to_bits - bits)) & maxv)
    return out


def bech32_encode(hrp: str, witness_version: int, program: bytes) -> str:
    data = [witness_version] + _convertbits(program, 8, 5)
    combined = data + _create_checksum(hrp, data)
    return hrp + "1" + "".join(_CHARSET[value] for value in combined)


def encode_segwit(hrp: str, witness_version: int, program: bytes) -> str:
    """BIP-350：v0 用 bech32，v1+ 用 bech32m（Taproot 的 `bc1p…`）。"""
    const = _BECH32_CONST if witness_version == 0 else _BECH32M_CONST
    data = [witness_version] + _convertbits(program, 8, 5)
    combined = data + _create_checksum(hrp, data, const)
    return hrp + "1" + "".join(_CHARSET[value] for value in combined)


def compressed_pubkey(uncompressed: bytes) -> bytes:
    if len(uncompressed) != 65 or uncompressed[0] != 4:
        raise ValueError("expected a 65-byte uncompressed secp256k1 key")
    return bytes([2 + (uncompressed[64] & 1)]) + uncompressed[1:33]


def p2wpkh_address(uncompressed_pubkey: bytes, hrp: str = "bc") -> str:
    pubkey = compressed_pubkey(uncompressed_pubkey)
    digest = hashlib.new("ripemd160", hashlib.sha256(pubkey).digest()).digest()
    return bech32_encode(hrp, 0, digest)
