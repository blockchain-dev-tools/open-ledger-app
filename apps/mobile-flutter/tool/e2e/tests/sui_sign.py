#!/usr/bin/env python3
"""E2E：Sui 地址 + Ed25519 签名（阶段 4）——真机 + BLE host。

流程：清数据建固定钱包 → 开 BLE 广播 → OPEN_APP(Sui) →
`07 02` 地址（与独立 `blake2b(0x00 || pubkey)` 比对）→
发签名 APDU → 设备弹确认页 → 点 Approve → host 收 `64B + 9000` →
**用 @noble/curves 独立验签**。
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

MESSAGE = b"sui transaction intent message for e2e"


def sui_address(public_key: bytes) -> str:
    digest = hashlib.blake2b(b"\x00" + public_key, digest_size=32).digest()
    return "0x" + digest.hex()


async def run() -> int:
    expected_pub = edsig.derive_public_key(TEST_MNEMONIC, apdu.SUI_PATH)
    expected_addr = sui_address(expected_pub)
    print(f"独立派生 Sui 地址: {expected_addr}")

    async with DeviceSession.start(fresh=True, chain_id="ethereum") as sess:
        with sess.ble_connected() as ble:
            print(f"BLE 已连接，设备 MTU={ble.get_mtu()}")

            # Sui 在账户页隐藏，但 OPEN_APP 仍可切到 Sui 的 CLA 表。
            data, sw = parse_response(ble.exchange(apdu.open_app("Sui")))
            if sw != SW_SUCCESS:
                print(f"[FAIL] OPEN_APP(Sui) SW={sw:04x}")
                return 1

            data, sw = parse_response(ble.exchange(apdu.sui_get_public_key()))
            if sw != SW_SUCCESS:
                print(f"[FAIL] SUI GET_PUBLIC_KEY SW={sw:04x}")
                return 1
            address = data.decode("ascii", errors="replace")
            print(f"设备地址: {address}")
            if address != expected_addr:
                print(f"[FAIL] 地址不匹配：设备 {address} vs 独立 {expected_addr}")
                return 1
            print("  ✓ 07 02 地址与独立 blake2b 派生一致")

            ble.send(apdu.sui_sign(MESSAGE))
            screens = await sess.app.wait_for_screen({"TransactionScreen"}, timeout=10)
            if "TransactionScreen" not in screens:
                print(f"[FAIL] 未弹出签名确认页：{screens}")
                return 1
            print("  ✓ 设备弹出 Sui 签名确认页")

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

            edsig.verify(expected_pub, MESSAGE, data)
            print("  ✓ 独立验签通过")

    print("[OK] sui_sign 通过")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
