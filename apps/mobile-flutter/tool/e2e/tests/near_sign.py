#!/usr/bin/env python3
"""E2E：NEAR 地址 + Borsh 交易签名 —— 真机 + BLE host。

流程：清数据建固定钱包 → 开 BLE 广播 → OPEN_APP(NEAR) → `80 06` 版本 →
`80 04` 公钥（与独立 SLIP-10 派生比对）→ 分块发 `80 02` Borsh 转账 →
设备弹确认页 → 点 Approve → host 收 `64B + 9000` → **独立验签
`sha256(tx)`**。
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

DEPOSIT = 1  # yoctoNEAR


def borsh_string(value: str) -> bytes:
    raw = value.encode()
    return len(raw).to_bytes(4, "little") + raw


def transfer_tx(signer: str, receiver: str, public_key: bytes) -> bytes:
    """单笔 Transfer 的最小 Borsh Transaction（与签名对象逐字节一致）。"""
    out = bytearray()
    out += borsh_string(signer)
    out += bytes([0]) + public_key  # public_key: ed25519
    out += (1).to_bytes(8, "little")  # nonce
    out += borsh_string(receiver)
    out += bytes(32)  # block_hash
    out += (1).to_bytes(4, "little")  # actions 数量
    out += bytes([3])  # Action::Transfer
    out += DEPOSIT.to_bytes(16, "little")
    return bytes(out)


async def run() -> int:
    expected_pub = edsig.derive_public_key(TEST_MNEMONIC, apdu.NEAR_PATH)
    implicit_account = expected_pub.hex()
    tx = transfer_tx(implicit_account, implicit_account, expected_pub)
    digest = hashlib.sha256(tx).digest()
    apdus = apdu.near_sign_transaction(tx)
    print(f"独立派生 NEAR 隐式账户: {implicit_account}")
    print(f"Borsh 交易 {len(tx)}B，digest {digest.hex()[:32]}…（{len(apdus)} 个 APDU 块）")

    async with DeviceSession.start(fresh=True, chain_id="ethereum") as sess:
        with sess.ble_connected() as ble:
            print(f"BLE 已连接，设备 MTU={ble.get_mtu()}")

            data, sw = parse_response(ble.exchange(apdu.open_app("NEAR")))
            if sw != SW_SUCCESS:
                print(f"[FAIL] OPEN_APP(NEAR) SW={sw:04x}")
                return 1

            data, sw = parse_response(ble.exchange(apdu.near_get_version()))
            if sw != SW_SUCCESS or len(data) != 3:
                print(f"[FAIL] NEAR GET_VERSION data={data.hex()} SW={sw:04x}")
                return 1
            print(f"  ✓ 80 06 版本 {data[0]}.{data[1]}.{data[2]}")

            data, sw = parse_response(ble.exchange(apdu.near_get_public_key()))
            if sw != SW_SUCCESS:
                print(f"[FAIL] NEAR GET_PUBLIC_KEY SW={sw:04x}")
                return 1
            if data != expected_pub:
                print(f"[FAIL] 公钥不匹配：设备 {data.hex()} vs 独立 {expected_pub.hex()}")
                return 1
            print("  ✓ 80 04 公钥与独立 SLIP-10 派生一致")

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
            print("  ✓ 设备弹出 NEAR 签名确认页")

            await sess.app.settle(0.8)
            hit = await sess.app.tap_key("sign-approve")
            if not hit.startswith("TAPPED"):
                print(f"[FAIL] 点不到 Approve：{hit!r}")
                return 1

            data, sw = parse_response(ble.recv(timeout=20))
            if sw != SW_SUCCESS:
                print(f"[FAIL] 签名响应 SW={sw:04x}")
                return 1
            if len(data) != 64:
                print(f"[FAIL] 签名长度 {len(data)}，期望 64")
                return 1
            print(f"  签名 {data.hex()[:32]}…")

            edsig.verify(expected_pub, digest, data)
            print("  ✓ 独立验签通过（sha256(tx)）")

    print("[OK] near_sign 通过")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
