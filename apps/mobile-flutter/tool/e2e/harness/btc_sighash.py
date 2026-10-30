"""BIP-143（segwit v0）签名摘要，仅 P2WPKH 单签路径。

设备只吃 32 字节 sighash，所以「设备签的到底是什么」必须由主机按真链规则
自己算出来，再交给节点验证——这是 T-027 的核心。
"""
from __future__ import annotations

from .btc_tx import Tx, varint, sha256d

SIGHASH_ALL = 0x01


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
