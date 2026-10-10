#!/usr/bin/env python3
"""E2E：SIGN_ETH_TRANSACTION（legacy）——真机 + BLE host。

流程：清数据建固定钱包 → 开 Ethereum 广播 → host 连 GATT →
OPEN_APP → 发 legacy 交易签名 APDU → 设备弹确认页 → 点 Approve →
host 收签名 → **用交易 RLP 的 keccak256 独立恢复地址并与设备地址比对**。
"""
from __future__ import annotations

import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harness import apdu, ethsig, rlp  # noqa: E402
from harness.apdu import SW_SUCCESS, parse_response, parse_signature  # noqa: E402
from harness.device import TEST_MNEMONIC  # noqa: E402
from harness.session import DeviceSession  # noqa: E402


async def run() -> int:
    expected_addr, _ = ethsig.derive_address(TEST_MNEMONIC)
    tx_rlp = rlp.legacy_tx(value=1234, gas_price=2_000_000_000, gas_limit=21000)
    apdus = apdu.sign_eth_transaction(tx_rlp)
    print(f"独立派生地址: {expected_addr}")
    print(f"交易 RLP: {tx_rlp.hex()}（{len(apdus)} 个 APDU 块）")

    async with DeviceSession.start(fresh=True, chain_id="ethereum") as sess:
        with sess.ble_connected() as ble:
            print(f"BLE 已连接，设备 MTU={ble.get_mtu()}")

            data, sw = parse_response(ble.exchange(apdu.open_app()))
            if sw != SW_SUCCESS:
                print(f"[FAIL] OPEN_APP SW={sw:04x}")
                return 1

            # 分块发送；非末块立即回 9000（不弹 UI），末块等用户确认后回签名
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
            print("  ✓ 设备弹出签名确认页")

            await sess.app.tap_key("sign-approve")
            data, sw = parse_response(ble.recv(timeout=15))
            if sw != SW_SUCCESS:
                print(f"[FAIL] 签名响应 SW={sw:04x}")
                return 1
            v, r, s = parse_signature(data)
            print(f"  签名 v={v} r={r.hex()[:16]}… s={s.hex()[:16]}…")

            recovered = ethsig.recover_address("raw", tx_rlp, v, r, s)
            print(f"  独立恢复地址: {recovered}")
            if recovered.lower() != expected_addr.lower():
                print("[FAIL] 恢复地址与设备地址不一致")
                return 1
            print("  ✓ 独立恢复地址与设备地址一致")

    print("[OK] sign_transaction 通过")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
