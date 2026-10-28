#!/usr/bin/env python3
"""E2E：SIGN_EIP_712（V0 单步）——真机 + BLE host。

V0 的载荷是 `[path][domainHash(32)][structHash(32)]`，设备签名
`keccak256(0x19 0x01 || domainHash || structHash)`。

流程：清数据建固定钱包 → 开 Ethereum 广播 → host 连 GATT → OPEN_APP →
GET_PUBLIC_KEY（与独立派生比对）→ 发 EIP-712 APDU → 设备弹确认页 →
点 Approve → host 收签名 → **用同一 preimage 独立恢复地址并比对**。
"""
from __future__ import annotations

import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harness import apdu, ethsig  # noqa: E402
from harness.apdu import (
    SW_SUCCESS,
    parse_eth_address,
    parse_response,
    parse_signature,
)  # noqa: E402
from harness.device import TEST_MNEMONIC  # noqa: E402
from harness.session import DeviceSession  # noqa: E402

# 固定向量，仅用于验证「设备签的是 0x1901||domain||struct」。
DOMAIN_HASH = bytes.fromhex(
    "8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f"
)
STRUCT_HASH = bytes.fromhex(
    "d8f3d4c0a6b1e5c9f2a7b4d1e8c5a2f9b6d3e0c7a4f1b8e5c2d9a6f3b0e7c4d1"
)


async def run() -> int:
    expected_addr, _ = ethsig.derive_address(TEST_MNEMONIC)
    print(f"独立派生地址: {expected_addr}")

    async with DeviceSession.start(fresh=True, chain_id="ethereum") as sess:
        with sess.ble_connected() as ble:
            print(f"BLE 已连接，设备 MTU={ble.get_mtu()}")

            data, sw = parse_response(ble.exchange(apdu.open_app()))
            if sw != SW_SUCCESS:
                print(f"[FAIL] OPEN_APP SW={sw:04x}")
                return 1

            data, sw = parse_response(ble.exchange(apdu.get_public_key()))
            if sw != SW_SUCCESS:
                print(f"[FAIL] GET_PUBLIC_KEY SW={sw:04x}")
                return 1
            addr, _ = parse_eth_address(data)
            if addr.lower() != expected_addr.lower():
                print(f"[FAIL] 地址不匹配：设备 {addr} vs 独立 {expected_addr}")
                return 1
            print("  ✓ 地址与独立派生一致")

            ble.send(apdu.sign_eip712(DOMAIN_HASH, STRUCT_HASH))
            screens = await sess.app.wait_for_screen({"TransactionScreen"}, timeout=10)
            if "TransactionScreen" not in screens:
                print(f"[FAIL] 未弹出签名确认页：{screens}")
                return 1
            print("  ✓ 设备弹出 EIP-712 确认页")

            texts = await sess.app.texts()
            joined = " ".join(texts)
            if DOMAIN_HASH.hex()[:16] not in joined.lower():
                print(f"[WARN] 确认页未展示 domainHash 前缀：{joined[:200]}")

            await sess.app.tap_key("sign-approve")
            data, sw = parse_response(ble.recv(timeout=15))
            if sw != SW_SUCCESS:
                print(f"[FAIL] 签名响应 SW={sw:04x}")
                return 1
            v, r, s = parse_signature(data)
            print(f"  签名 v={v} r={r.hex()[:16]}… s={s.hex()[:16]}…")

            preimage = b"\x19\x01" + DOMAIN_HASH + STRUCT_HASH
            recovered = ethsig.recover_address("raw", preimage, v, r, s)
            print(f"  独立恢复地址: {recovered}")
            if recovered.lower() != expected_addr.lower():
                print("[FAIL] 恢复地址与设备地址不一致")
                return 1
            print("  ✓ 独立恢复地址与设备地址一致")

    print("[OK] sign_eip712 通过")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
