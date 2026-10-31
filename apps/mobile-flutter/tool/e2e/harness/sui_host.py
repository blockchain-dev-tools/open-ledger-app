#!/usr/bin/env python3
"""Sui 官方协议的主机侧实现（E2E 用）。

包含两部分，都按 `LedgerHQ/app-sui` 的官方实现写，**不复用**设备侧的代码：

- `BlockHost`：Block Protocol 的块链构造与应答（`docs/block-protocol.md`）；
- BCS 交易构造器：原生 SUI / 代币转账与一个「不可识别」的 MoveCall 交易。

与 `psbt_host.py` 的定位相同：设备反向请求什么，这里就按哈希把块交回去。
"""
from __future__ import annotations

import hashlib
from dataclasses import dataclass, field

from . import apdu
from .apdu import SW_SUCCESS, parse_response

CHUNK_SIZE = 180
HASH_LEN = 32
ZERO_HASH = b"\x00" * HASH_LEN

# 主机 → 设备
HOST_START = 0x00
HOST_GET_CHUNK_SUCCESS = 0x01
# 设备 → 主机
REPLY_FINAL = 0x01
REPLY_GET_CHUNK = 0x02

SUI_DECIMALS = 9


def sui_address(public_key: bytes) -> bytes:
    """`blake2b(0x00 || ed25519_pubkey)`（Sui 的地址格式）。"""
    return hashlib.blake2b(b"\x00" + public_key, digest_size=32).digest()


@dataclass
class Frame:
    data: bytes
    hash: bytes | None = field(default=None)
    next_hash: bytes | None = field(default=None)


class BlockHost:
    """把参数切成块链，并按设备的 `GET_CHUNK` 顺序回放。"""

    def frames(self, params: list[bytes]) -> list[Frame]:
        first_hashes: list[bytes] = []
        per_param: list[list[Frame]] = []
        for param in params:
            chain: list[Frame] = []
            last = ZERO_HASH
            for offset in range(0, len(param), CHUNK_SIZE):
                chunk = param[offset:offset + CHUNK_SIZE]
                block = last + chunk
                last = hashlib.sha256(block).digest()
                chain.append(Frame(data=bytes([HOST_GET_CHUNK_SUCCESS]) + block, hash=last))
            chain.reverse()
            per_param.append(chain)
            first_hashes.append(chain[0].hash)

        frames: list[Frame] = [Frame(data=bytes([HOST_START]) + b"".join(first_hashes))]
        for chain in per_param:
            frames.extend(chain)
        for index in range(len(frames) - 1):
            frames[index].next_hash = frames[index + 1].hash
        return frames


def drive(
    ble,
    ins: int,
    params: list[bytes],
    *,
    review: bool = False,
    timeout: float = 20,
) -> tuple[bytes | None, int]:
    """跑完一条 Block Protocol 命令。

    `review=True` 时，最后一帧发出后设备会停在确认页（不立即回包），
    这里把控制权交回调用方：它会等待界面、点确认，再 `ble.recv()`。
    """
    frames = BlockHost().frames(params)
    for index, frame in enumerate(frames):
        last = index == len(frames) - 1
        ble.send(apdu.apdu(apdu.CLA_SUI, ins, 0x00, 0x00, frame.data))
        if last and review:
            return None, SW_SUCCESS
        data, sw = ble.recv(timeout=timeout)
        if sw != SW_SUCCESS:
            return None, sw
        instruction = data[0]
        if instruction == REPLY_GET_CHUNK:
            if frame.next_hash is not None and data[1:1 + HASH_LEN] != frame.next_hash:
                raise RuntimeError("设备请求了非预期的块哈希")
            continue
        if instruction == REPLY_FINAL:
            return data[1:], sw
        raise RuntimeError(f"未知的 LedgerToHost 指令 0x{instruction:02X}")
    return None, SW_SUCCESS


# ── BCS 交易构造 ────────────────────────────────────────────────────

def _argument_input(index: int) -> bytes:
    return bytes([0x01]) + index.to_bytes(2, "little")


def _argument_result(index: int) -> bytes:
    return bytes([0x02]) + index.to_bytes(2, "little")


ARG_GAS = b"\x00"


def _prelude(input_count: int, command_count: int) -> bytearray:
    # Intent(0,0,0) || TransactionData::V1 || TransactionKind::ProgrammableTransaction
    return bytearray(b"\x00\x00\x00\x00\x00" + bytes([input_count, command_count]))


def _gas_and_sender(
    tx: bytearray,
    sender: bytes,
    *,
    gas_payments: int = 0,
    gas_price: int = 1,
    gas_budget: int = 2_000_000,
) -> bytes:
    tx += sender
    tx.append(gas_payments)
    for index in range(gas_payments):
        tx += bytes([0x33 + index]) * 32
        tx += (9).to_bytes(8, "little")
        tx += bytes([0x44]) * 32
    tx += sender
    tx += gas_price.to_bytes(8, "little")
    tx += gas_budget.to_bytes(8, "little")
    tx.append(0x00)  # TransactionExpiration::None
    return bytes(tx)


def native_transfer_tx(
    sender: bytes,
    recipient: bytes,
    amount: int,
    *,
    gas_price: int = 1,
    gas_budget: int = 2_000_000,
    pad_inputs: int = 0,
) -> bytes:
    """`SplitCoins(GasCoin, [Input(0)])` + `TransferObjects([Result(0)], Input(1))`。"""
    tx = _prelude(2 + pad_inputs, 2)
    tx += b"\x00\x08" + amount.to_bytes(8, "little")
    tx += b"\x00\x20" + recipient
    for index in range(pad_inputs):
        tx += b"\x00\x20" + bytes([index + 1]) * 32
    tx += b"\x02" + ARG_GAS + b"\x01" + _argument_input(0)
    tx += b"\x01\x01" + _argument_result(0) + _argument_input(1)
    return _gas_and_sender(tx, sender, gas_price=gas_price, gas_budget=gas_budget)


def token_transfer_tx(
    sender: bytes,
    recipient: bytes,
    amount: int,
    *,
    gas_budget: int = 5_000_000,
) -> bytes:
    """代币转账：拆分源是 coin object（`Input(0)`），金额 `Input(1)`。"""
    tx = _prelude(3, 2)
    tx += b"\x01\x00" + b"\x11" * 32 + (7).to_bytes(8, "little") + b"\x22" * 32
    tx += b"\x00\x08" + amount.to_bytes(8, "little")
    tx += b"\x00\x20" + recipient
    tx += b"\x02" + _argument_input(0) + b"\x01" + _argument_input(1)
    tx += b"\x01\x01" + _argument_result(0) + _argument_input(2)
    return _gas_and_sender(tx, sender, gas_payments=1, gas_budget=gas_budget)


def unsupported_move_call_tx(sender: bytes) -> bytes:
    """`MoveCall` 交易：本期不解析，设备必须回 `0x6808`。"""
    tx = _prelude(0, 1)
    tx += b"\x00"  # Command::MoveCall
    tx += b"\x02" * 32  # package id
    tx += b"\x04coin"  # module
    tx += b"\x08transfer"  # function
    tx += b"\x00"  # type args
    tx += b"\x00"  # args
    return _gas_and_sender(tx, sender)


def encode_sign_param(tx: bytes) -> bytes:
    return len(tx).to_bytes(4, "little") + tx


__all__ = [
    "BlockHost",
    "Frame",
    "drive",
    "native_transfer_tx",
    "token_transfer_tx",
    "unsupported_move_call_tx",
    "sui_address",
    "encode_sign_param",
    "parse_response",
]
