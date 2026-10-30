#!/usr/bin/env python3
"""E2E：Solana 地址 + Ed25519 签名（阶段 4）——真机 + BLE host。

流程：清数据建固定钱包 → 开 Solana 广播 → OPEN_APP(Solana) →
`E0 04` 版本 → `E0 05` 裸 32B 公钥（与独立 SLIP-10 派生比对）→
发系统转账消息 → 设备弹确认页 → 点 Approve →
host 收 `64B + 9000` → **用 @noble/curves 独立验签**。

Solana 地址编码在 Python 侧独立完成（`harness/base58x.py`），
Ed25519 派生/验签在 Node 侧（`js/edverify.mjs`），与设备 Rust 是两套代码。
"""
from __future__ import annotations

import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harness import apdu, base58x, edsig  # noqa: E402
from harness.apdu import SW_SUCCESS, parse_response  # noqa: E402
from harness.device import TEST_MNEMONIC  # noqa: E402
from harness.session import DeviceSession  # noqa: E402

LAMPORTS = 1_500_000_000


def transfer_message(lamports: int) -> bytes:
    """一个 System Program Transfer 的 legacy 消息（单签名）。"""
    msg = bytearray([1, 0, 1, 3])          # sigs / ro-signed / ro-unsigned / keys
    msg += bytes([0x01]) * 32              # fee payer
    msg += bytes([0x02]) * 32              # recipient
    msg += bytes([0x00]) * 32              # system program
    msg += bytes([0x09]) * 32              # blockhash
    msg += bytes([1, 2, 2, 0, 1, 12])      # ix count / program / accounts / data len
    msg += bytes([2, 0, 0, 0])             # Transfer discriminator
    msg += lamports.to_bytes(8, "little")
    return bytes(msg)


async def run() -> int:
    expected_pub = edsig.derive_public_key(TEST_MNEMONIC, apdu.SOL_PATH)
    expected_addr = base58x.encode(expected_pub)
    print(f"独立派生 Solana 地址: {expected_addr}")

    message = transfer_message(LAMPORTS)

    async with DeviceSession.start(fresh=True, chain_id="solana") as sess:
        with sess.ble_connected() as ble:
            print(f"BLE 已连接，设备 MTU={ble.get_mtu()}")

            data, sw = parse_response(ble.exchange(apdu.open_app("Solana")))
            if sw != SW_SUCCESS:
                print(f"[FAIL] OPEN_APP(Solana) SW={sw:04x}")
                return 1

            data, sw = parse_response(ble.exchange(apdu.sol_get_app_configuration()))
            # 官方 app-solana 的 GET_APP_CONFIGURATION：5 字节
            # [allow_blind_sign][pubkey_display][major][minor][patch]。
            if sw != SW_SUCCESS or data != bytes([0x00, 0x01, 0x00, 0x01, 0x00]):
                print(f"[FAIL] SOL GET_APP_CONFIGURATION data={data.hex()} SW={sw:04x}")
                return 1
            print("  ✓ E0 04 配置响应为官方 5 字节布局")

            data, sw = parse_response(ble.exchange(apdu.sol_get_address()))
            if sw != SW_SUCCESS:
                print(f"[FAIL] SOL GET_ADDR SW={sw:04x}")
                return 1
            if len(data) != 32:
                print(f"[FAIL] 地址响应应为裸 32 字节，实际 {len(data)}: {data.hex()}")
                return 1
            device_addr = base58x.encode(data)
            print(f"设备地址: {device_addr}")
            if data != expected_pub:
                print(f"[FAIL] 公钥不匹配：设备 {data.hex()} vs 独立 {expected_pub.hex()}")
                return 1
            print("  ✓ E0 05 裸公钥与独立 SLIP-10 派生一致")

            ble.send(apdu.sol_sign(message))
            screens = await sess.app.wait_for_screen({"TransactionScreen"}, timeout=10)
            if "TransactionScreen" not in screens:
                print(f"[FAIL] 未弹出签名确认页：{screens}")
                return 1
            print("  ✓ 设备弹出 Solana 签名确认页")

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

            edsig.verify(expected_pub, message, data)
            print("  ✓ 独立验签通过（消息未额外加哈希）")

    print("[OK] sol_sign 通过")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
