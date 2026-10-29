#!/usr/bin/env python3
"""E2E：TON 地址 + v4r2 TransactionOrder 签名 —— 真机 + BLE host。

流程：清数据建固定钱包 → 开 BLE 广播 → OPEN_APP(TON) → `E0 03` 版本 →
`E0 05` 公钥（与独立 SLIP-10 派生比对）→ 分块发 `E0 06` 转账请求 →
设备弹确认页 → 点 Approve → host 收 `[64][sig][32][hash]` →
**用本文件独立实现的 cell 哈希重算 order hash 并验签**。
"""
from __future__ import annotations

import asyncio
import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harness import apdu, edsig  # noqa: E402
from harness.apdu import SW_SUCCESS, parse_response  # noqa: E402
from harness.device import TEST_MNEMONIC  # noqa: E402
from harness.session import DeviceSession  # noqa: E402

SUBWALLET_ID = 698_983_191
VALUE_NANO = 1_000_000_000  # 1 TON
TO_HASH = bytes([0xAB]) * 32
SEQNO = 1
TIMEOUT = 0x6000_0000
SEND_MODE = 3


class Bits:
    """位级写入器；`finish` 用 `1` 补位到字节边界（TON 规则）。"""

    def __init__(self) -> None:
        self.bytes = bytearray()
        self.bit_len = 0

    def push_bit(self, bit: int) -> None:
        if self.bit_len % 8 == 0:
            self.bytes.append(0)
        if bit:
            self.bytes[self.bit_len // 8] |= 1 << (7 - self.bit_len % 8)
        self.bit_len += 1

    def push_uint(self, value: int, bits: int) -> None:
        for shift in reversed(range(bits)):
            self.push_bit((value >> shift) & 1)

    def push_bytes(self, raw: bytes) -> None:
        for byte in raw:
            self.push_uint(byte, 8)

    def finish(self) -> tuple[int, bytes]:
        bit_len = self.bit_len
        if bit_len % 8:
            self.push_bit(1)
            while self.bit_len % 8:
                self.push_bit(0)
        return bit_len, bytes(self.bytes)


def cell_hash(bits: int, data: bytes, refs: list[tuple[int, bytes]]) -> bytes:
    """`d1 · d2 · data · (depth · hash) × refs`。"""
    d1 = len(refs) << 4
    d2 = (bits // 8) * 2 + (1 if bits % 8 else 0)
    buf = bytes([d1, d2]) + data
    for depth, ref_hash in refs:
        buf += depth.to_bytes(2, "big") + ref_hash
    return hashlib.sha256(buf).digest()


def value_bytes(amount: int) -> bytes:
    """VarUInteger 16 的最小大端字节。"""
    if amount == 0:
        return b""
    return amount.to_bytes((amount.bit_length() + 7) // 8, "big")


def order_hash() -> bytes:
    value = value_bytes(VALUE_NANO)
    message = Bits()
    message.push_bit(0)  # int_msg_info$0
    message.push_bit(1)  # ihr_disabled
    message.push_bit(0)  # bounce
    message.push_bit(0)  # bounced
    message.push_uint(0, 2)  # src: addr_none
    message.push_uint(2, 2)  # dest: addr_std$10
    message.push_bit(0)  # anycast
    message.push_uint(0, 8)  # workchain
    message.push_bytes(TO_HASH)
    message.push_uint(len(value), 4)
    message.push_bytes(value)
    message.push_bit(0)  # extra currencies
    message.push_uint(0, 4)  # ihr_fee
    message.push_uint(0, 4)  # fwd_fee
    message.push_uint(0, 64)  # created_lt
    message.push_uint(0, 32)  # created_at
    message.push_bit(0)  # no state-init
    message.push_bit(0)  # body inline
    message_hash = cell_hash(*message.finish(), [])

    order = Bits()
    order.push_uint(SUBWALLET_ID, 32)
    order.push_uint(TIMEOUT, 32)
    order.push_uint(SEQNO, 32)
    order.push_uint(0, 8)  # op
    order.push_uint(SEND_MODE, 8)
    return cell_hash(*order.finish(), [(0, message_hash)])


def transfer_request() -> bytes:
    """`TRANSACTION.md` 的普通转账请求（无 state-init / payload / hints）。"""
    value = value_bytes(VALUE_NANO)
    out = bytearray([0x00])
    out += SEQNO.to_bytes(4, "big")
    out += TIMEOUT.to_bytes(4, "big")
    out += bytes([len(value)]) + value
    out += bytes([0x00])  # workchain
    out += TO_HASH
    out += bytes([0x00])  # bounce = false
    out += bytes([SEND_MODE])
    out += bytes([0x00, 0x00, 0x00])  # has_state_init / has_payload / has_hints
    return bytes(out)


async def run() -> int:
    expected_pub = edsig.derive_public_key(TEST_MNEMONIC, apdu.TON_PATH)
    expected_hash = order_hash()
    tx = transfer_request()
    apdus = apdu.ton_sign_transaction(tx)
    print(f"独立派生 TON 公钥: {expected_pub.hex()}")
    print(f"独立计算的 order hash: {expected_hash.hex()}")
    print(f"转账请求 {len(tx)}B（{len(apdus)} 个 APDU 块）")

    async with DeviceSession.start(fresh=True, chain_id="ethereum") as sess:
        with sess.ble_connected() as ble:
            print(f"BLE 已连接，设备 MTU={ble.get_mtu()}")

            data, sw = parse_response(ble.exchange(apdu.open_app("TON")))
            if sw != SW_SUCCESS:
                print(f"[FAIL] OPEN_APP(TON) SW={sw:04x}")
                return 1

            data, sw = parse_response(ble.exchange(apdu.ton_get_version()))
            if sw != SW_SUCCESS or len(data) != 3:
                print(f"[FAIL] TON GET_VERSION data={data.hex()} SW={sw:04x}")
                return 1
            print(f"  ✓ E0 03 版本 {data[0]}.{data[1]}.{data[2]}")

            data, sw = parse_response(ble.exchange(apdu.ton_get_public_key()))
            if sw != SW_SUCCESS:
                print(f"[FAIL] TON GET_PUBLIC_KEY SW={sw:04x}")
                return 1
            if data != expected_pub:
                print(f"[FAIL] 公钥不匹配：设备 {data.hex()} vs 独立 {expected_pub.hex()}")
                return 1
            print("  ✓ E0 05 公钥与独立 SLIP-10 派生一致")

            ble.prepare_recv()
            for i, chunk in enumerate(apdus):
                ble.send_raw(chunk)
                if i < len(apdus) - 1:
                    _, sw = parse_response(ble.recv(timeout=10))
                    if sw != SW_SUCCESS:
                        print(f"[FAIL] 中间块 SW={sw:04x}")
                        return 1

            screens = await sess.app.wait_for_screen({"TransactionScreen"}, timeout=10)
            if "TransactionScreen" not in screens:
                print(f"[FAIL] 未弹出签名确认页：{screens}")
                return 1
            print("  ✓ 设备弹出 TON 签名确认页")

            await sess.app.settle(0.8)
            hit = await sess.app.tap_key("sign-approve")
            if not hit.startswith("TAPPED"):
                print(f"[FAIL] 点不到 Approve：{hit!r}")
                return 1

            data, sw = parse_response(ble.recv(timeout=20))
            if sw != SW_SUCCESS:
                print(f"[FAIL] 签名响应 SW={sw:04x}")
                return 1
            if len(data) != 1 + 64 + 1 + 32 or data[0] != 64 or data[65] != 32:
                print(f"[FAIL] 响应格式不符合 [64][sig][32][hash]: {data.hex()}")
                return 1
            signature = data[1:65]
            device_hash = data[66:]
            print(f"  设备 hash {device_hash.hex()}")
            if device_hash != expected_hash:
                print(f"[FAIL] order hash 不一致：独立 {expected_hash.hex()}")
                return 1
            print("  ✓ 设备 order hash 与独立 cell 哈希一致")

            edsig.verify(expected_pub, device_hash, signature)
            print("  ✓ 独立验签通过")

    print("[OK] ton_sign 通过")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
