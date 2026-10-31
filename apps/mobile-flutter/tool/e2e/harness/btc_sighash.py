"""BIP-143（segwit v0）与 BIP-341（taproot key-path）签名摘要。

设备只吃 32 字节 sighash，所以「设备签的到底是什么」必须由主机按真链规则
自己算出来，再交给节点验证——这是 T-027 / T-028 的核心。
"""
from __future__ import annotations

import hashlib

from .btc_tx import Tx, varint, sha256d

SIGHASH_ALL = 0x01


def _tagged_hash(tag: str, message: bytes) -> bytes:
    tag_hash = hashlib.sha256(tag.encode()).digest()
    return hashlib.sha256(tag_hash + tag_hash + message).digest()


def sighash_taproot(
    tx: Tx,
    input_index: int,
    prevouts: list[tuple[int, bytes]],
    hash_type: int = 0x00,
) -> bytes:
    """BIP-341 key-path（无 annex、非 ANYONECANPAY）。

    `prevouts` 与 `tx.inputs` 一一对应：(金额, scriptPubKey)。
    """
    prevout_bytes = b"".join(txin.outpoint() for txin in tx.inputs)
    amounts = b"".join(value.to_bytes(8, "little") for value, _ in prevouts)
    scripts = b"".join(
        varint(len(script)) + script for _, script in prevouts
    )
    sequences = b"".join(
        txin.sequence.to_bytes(4, "little") for txin in tx.inputs
    )
    outputs = b"".join(txout.serialize() for txout in tx.outputs)

    body = (
        bytes([hash_type])
        + tx.version.to_bytes(4, "little")
        + tx.locktime.to_bytes(4, "little")
        + hashlib.sha256(prevout_bytes).digest()
        + hashlib.sha256(amounts).digest()
        + hashlib.sha256(scripts).digest()
        + hashlib.sha256(sequences).digest()
        + hashlib.sha256(outputs).digest()
        + b"\x00"  # spend_type：无 annex、key-path
        + input_index.to_bytes(4, "little")
    )
    return _tagged_hash("TapSighash", b"\x00" + body)


def sighash_p2wpkh(
    tx: Tx,
    input_index: int,
    script_code: bytes,
    amount: int,
    sighash_type: int = SIGHASH_ALL,
) -> bytes:
    """P2WPKH 的 BIP-143 摘要。"""
    hash_prevouts = sha256d(b"".join(txin.outpoint() for txin in tx.inputs))
    hash_sequence = sha256d(
        b"".join(txin.sequence.to_bytes(4, "little") for txin in tx.inputs)
    )
    hash_outputs = sha256d(b"".join(txout.serialize() for txout in tx.outputs))

    txin = tx.inputs[input_index]
    preimage = (
        tx.version.to_bytes(4, "little")
        + hash_prevouts
        + hash_sequence
        + txin.outpoint()
        + varint(len(script_code))
        + script_code
        + amount.to_bytes(8, "little")
        + txin.sequence.to_bytes(4, "little")
        + hash_outputs
        + tx.locktime.to_bytes(4, "little")
        + sighash_type.to_bytes(4, "little")
    )
    return sha256d(preimage)
