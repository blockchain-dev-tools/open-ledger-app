"""最小 Bitcoin 交易序列化（仅标准库）。

只覆盖 E2E 需要的东西：P2WPKH 的 scriptPubKey、非 witness 的 txid 预映像、
带 witness 的最终广播字节。刻意不复用设备侧实现。
"""
from __future__ import annotations

import hashlib
from dataclasses import dataclass, field


def sha256d(data: bytes) -> bytes:
    return hashlib.sha256(hashlib.sha256(data).digest()).digest()


def varint(value: int) -> bytes:
    if value < 0xFD:
        return bytes([value])
    if value <= 0xFFFF:
        return b"\xfd" + value.to_bytes(2, "little")
    if value <= 0xFFFFFFFF:
        return b"\xfe" + value.to_bytes(4, "little")
    return b"\xff" + value.to_bytes(8, "little")


def p2wpkh_script(pubkey_hash: bytes) -> bytes:
    """`OP_0 <20-byte push>`，即 bech32 v0 的 scriptPubKey。"""
    if len(pubkey_hash) != 20:
        raise ValueError("pubkey hash must be 20 bytes")
    return bytes([0x00, 0x14]) + pubkey_hash


def p2pkh_script_code(pubkey_hash: bytes) -> bytes:
    """BIP-143 的 scriptCode：P2WPKH 用等价的 P2PKH 脚本（25 字节，不含长度前缀）。

    preimage 里的 `varint(len) ‖ scriptCode` 由 `btc_sighash` 负责，这里再加
    长度前缀会变成 `0x19 0x19 76a9…`，签名必然无效。
    """
    if len(pubkey_hash) != 20:
        raise ValueError("pubkey hash must be 20 bytes")
    return bytes([0x76, 0xA9, 0x14]) + pubkey_hash + bytes([0x88, 0xAC])


@dataclass
class TxIn:
    txid: str  # RPC 的十六进制（大端展示）
    vout: int
    sequence: int = 0xFFFFFFFD
    witness: list[bytes] = field(default_factory=list)

    def outpoint(self) -> bytes:
        return bytes.fromhex(self.txid)[::-1] + self.vout.to_bytes(4, "little")


@dataclass
class TxOut:
    value: int  # satoshi
    script: bytes

    def serialize(self) -> bytes:
        return self.value.to_bytes(8, "little") + varint(len(self.script)) + self.script


@dataclass
class Tx:
    inputs: list[TxIn]
    outputs: list[TxOut]
    version: int = 2
    locktime: int = 0

    def _body(self, with_witness: bool) -> bytes:
        out = self.version.to_bytes(4, "little")
        if with_witness:
            out += b"\x00\x01"  # segwit marker + flag
        out += varint(len(self.inputs))
        for txin in self.inputs:
            out += txin.outpoint() + b"\x00" + txin.sequence.to_bytes(4, "little")
        out += varint(len(self.outputs))
        for txout in self.outputs:
            out += txout.serialize()
        if with_witness:
            for txin in self.inputs:
                out += varint(len(txin.witness))
                for item in txin.witness:
                    out += varint(len(item)) + item
        out += self.locktime.to_bytes(4, "little")
        return out

    def serialize(self) -> bytes:
        """最终广播字节（带 witness）。"""
        if any(txin.witness for txin in self.inputs):
            return self._body(with_witness=True)
        return self._body(with_witness=False)

    def txid(self) -> str:
        """txid 不含 witness：对非 witness 序列化做双 SHA-256 后反字节序。"""
        return sha256d(self._body(with_witness=False))[::-1].hex()


def btc_to_satoshi(value) -> int:
    return round(float(value) * 100_000_000)
