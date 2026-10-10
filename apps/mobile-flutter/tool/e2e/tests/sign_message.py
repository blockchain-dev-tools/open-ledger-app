#!/usr/bin/env python3
"""E2E：SIGN_PERSONAL_MESSAGE（EIP-191）——真机 + BLE host。

流程：清数据建固定钱包 → 开 Ethereum 广播 → host 连 GATT →
OPEN_APP → GET_PUBLIC_KEY（与独立派生比对）→ 发签名 APDU →
设备弹确认页 → 点 Approve → host 收签名 → **独立恢复地址并与设备地址比对**。
"""
from __future__ import annotations

import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harness import apdu, ethsig  # noqa: E402
from harness.apdu import SW_SUCCESS, parse_eth_address, parse_response, parse_signature  # noqa: E402
from harness.device import TEST_MNEMONIC  # noqa: E402
from harness.session import DeviceSession  # noqa: E402

MESSAGE = b"Hello Open Ledger App"


async def run() -> int:
    expected_addr, expected_pub = ethsig.derive_address(TEST_MNEMONIC)
    print(f"独立派生地址: {expected_addr}")

    async with DeviceSession.start(fresh=True, chain_id="ethereum") as sess:
        with sess.ble_connected() as ble:
            print(f"BLE 已连接，设备 MTU={ble.get_mtu()}")

            # OPEN_APP(Ethereum)
            data, sw = parse_response(ble.exchange(apdu.open_app()))
            if sw != SW_SUCCESS:
                print(f"[FAIL] OPEN_APP SW={sw:04x}")
                return 1

            # GET_PUBLIC_KEY（P1=0x00 不触发确认 UI）
            data, sw = parse_response(ble.exchange(apdu.get_public_key()))
            if sw != SW_SUCCESS:
                print(f"[FAIL] GET_PUBLIC_KEY SW={sw:04x}")
                return 1
            addr, pub = parse_eth_address(data)
            print(f"设备地址: {addr}")
            if addr.lower() != expected_addr.lower():
                print(f"[FAIL] 地址不匹配：设备 {addr} vs 独立 {expected_addr}")
                return 1
            if pub.hex() != expected_pub.hex():
                print("[FAIL] 公钥不匹配")
                return 1
            print("  ✓ 地址/公钥与独立派生一致")

            # 发起消息签名 → 设备弹确认页
            ble.send(apdu.sign_personal_message(MESSAGE))
            screens = await sess.app.wait_for_screen({"TransactionScreen"}, timeout=10)
            if "TransactionScreen" not in screens:
                print(f"[FAIL] 未弹出签名确认页：{screens}")
                return 1
            print("  ✓ 设备弹出签名确认页")

            await sess.app.tap_key("sign-approve")
            data, sw = parse_response(ble.recv(timeout=15))
            if sw != SW_SUCCESS:
                print(f"[FAIL] 签名响应 SW={sw:04x}")
                return 1
            v, r, s = parse_signature(data)
            print(f"  签名 v={v} r={r.hex()[:16]}… s={s.hex()[:16]}…")

            recovered = ethsig.recover_address("personal", MESSAGE, v, r, s)
            print(f"  独立恢复地址: {recovered}")
            if recovered.lower() != expected_addr.lower():
                print("[FAIL] 恢复地址与设备地址不一致")
                return 1
            print("  ✓ 独立恢复地址与设备地址一致")

    print("[OK] sign_message 通过")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
