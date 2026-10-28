#!/usr/bin/env python3
"""E2E：Bitcoin 地址 + 多输入签名（阶段 3）——真机 + BLE host。

流程：清数据建固定钱包 → OPEN_APP(Bitcoin) → GET_WALLET_PUBLIC_KEY
（与独立 P2WPKH 编码比对）→ 发两个 sighash 的签名 APDU → 设备弹确认页 →
点 Approve → host 收 `2 × 65B + 9000` → **逐个用直签摘要独立恢复地址**并比对。

BTC 地址编码在 Python 侧独立完成（`harness/btcaddr.py`，BIP-173），
派生在 Node 侧（`ethverify.mjs`），与设备 Rust 实现是两套代码。
"""
from __future__ import annotations

import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harness import apdu, btcaddr, ethsig  # noqa: E402
from harness.apdu import (  # noqa: E402
    SW_SUCCESS,
    parse_response,
    parse_signature,
)
from harness.device import TEST_MNEMONIC  # noqa: E402
from harness.session import DeviceSession  # noqa: E402

SIGHASHES = [bytes([0x11]) * 32, bytes([0x22]) * 32]


async def run() -> int:
    # `derive_address` 对任意路径都返回该私钥的 ETH 地址与 65B 公钥；
    # BTC 地址由公钥在 Python 侧独立编码，签名恢复则比对该路径的 ETH 地址。
    btc_path_eth, btc_pub = ethsig.derive_address(TEST_MNEMONIC, apdu.BTC_PATH)
    expected_btc = btcaddr.p2wpkh_address(btc_pub)
    print(f"独立派生 BTC 地址: {expected_btc}")
    print(f"BTC 路径同私钥 ETH 地址: {btc_path_eth}")

    async with DeviceSession.start(fresh=True, chain_id="ethereum") as sess:
        with sess.ble_connected() as ble:
            print(f"BLE 已连接，设备 MTU={ble.get_mtu()}")

            data, sw = parse_response(ble.exchange(apdu.open_app("Bitcoin")))
            if sw != SW_SUCCESS:
                print(f"[FAIL] OPEN_APP(Bitcoin) SW={sw:04x}")
                return 1

            data, sw = parse_response(ble.exchange(apdu.btc_get_public_key()))
            if sw != SW_SUCCESS:
                print(f"[FAIL] GET_WALLET_PUBLIC_KEY SW={sw:04x}")
                return 1
            address = data.decode("ascii", errors="replace")
            print(f"设备地址: {address}")
            if address != expected_btc:
                print(f"[FAIL] 地址不匹配：设备 {address} vs 独立 {expected_btc}")
                return 1
            print("  ✓ P2WPKH 地址与独立编码一致")

            ble.send(apdu.btc_sign(SIGHASHES))
            screens = await sess.app.wait_for_screen({"TransactionScreen"}, timeout=10)
            if "TransactionScreen" not in screens:
                print(f"[FAIL] 未弹出签名确认页：{screens}")
                return 1
            print("  ✓ 设备弹出 BTC 多输入确认页")

            # 等确认页转场结束再点，否则命中上一页的坐标系。
            await sess.app.settle(0.8)
            hit = await sess.app.tap_key("sign-approve")
            if not hit.startswith("TAPPED"):
                print(f"[FAIL] 点不到 Approve：{hit!r}")
                return 1
            data, sw = parse_response(ble.recv(timeout=20))
            if sw != SW_SUCCESS:
                print(f"[FAIL] 签名响应 SW={sw:04x}")
                return 1
            if len(data) != len(SIGHASHES) * 65:
                print(f"[FAIL] 签名长度 {len(data)}，期望 {len(SIGHASHES) * 65}")
                return 1

            for index, sighash in enumerate(SIGHASHES):
                v, r, s = parse_signature(data[index * 65:(index + 1) * 65])
                recovered = ethsig.recover_address("digest", sighash, v, r, s)
                print(f"  input {index}: v={v} r={r.hex()[:16]}… → {recovered}")
                if recovered.lower() != btc_path_eth.lower():
                    print(f"[FAIL] input {index} 恢复地址与设备私钥不一致")
                    return 1
            print(f"  ✓ {len(SIGHASHES)} 个输入的签名均可独立恢复且地址一致")

    print("[OK] btc_sign 通过")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
