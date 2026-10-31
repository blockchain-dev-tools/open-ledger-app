#!/usr/bin/env python3
"""E2E：Sui 官方协议（CLA 0x00 + Block Protocol + BCS 解析）。

流程：清数据建固定钱包 → 开 BLE 广播 → OPEN_APP(Sui) →

  T1  `00 00 GET_VERSION`（Block Protocol）→ `[1,5,11] || "sui"`
  T2  `00 02 GET_PUBKEY` → `[len][pubkey][len][address]`，地址与独立 blake2b 一致
  T3  `00 03 SIGN_TX` 原生 SUI 转账 → 确认页 → Approve → 64B 签名
      （用 `@noble` 独立验签，签名对象是整段交易字节）
  T4  不可识别的交易（MoveCall）→ 直接回 `0x6808`，不弹确认页
  T5  用户拒绝 → `0x6985`

判据不是「我们自己能签」，而是线格式与官方 `app-sui` 逐字节一致。
"""
from __future__ import annotations

import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harness import apdu, edsig, sui_host  # noqa: E402
from harness.apdu import SW_SUCCESS, parse_response  # noqa: E402
from harness.device import TEST_MNEMONIC  # noqa: E402
from harness.session import DeviceSession  # noqa: E402

SW_USER_DENIED = 0x6985
SW_NOT_SUPPORTED = 0x6808

RECIPIENT = bytes.fromhex("00" * 31 + "01")
AMOUNT = 1_000_000_000  # 1 SUI，单位 MIST


def split_key_reply(payload: bytes) -> tuple[bytes, bytes]:
    """`[len][pubkey][len][address]`。"""
    key_len = payload[0]
    public_key = payload[1:1 + key_len]
    offset = 1 + key_len
    address_len = payload[offset]
    address = payload[offset + 1:offset + 1 + address_len]
    return public_key, address


async def run() -> int:
    expected_pub = edsig.derive_public_key(TEST_MNEMONIC, apdu.SUI_PATH)
    expected_address = sui_host.sui_address(expected_pub)
    print(f"独立派生 Sui 地址: 0x{expected_address.hex()}")

    async with DeviceSession.start(fresh=True, chain_id="ethereum") as sess:
        with sess.ble_connected() as ble:
            print(f"BLE 已连接，设备 MTU={ble.get_mtu()}")

            _, sw = parse_response(ble.exchange(apdu.open_app("Sui")))
            if sw != SW_SUCCESS:
                print(f"[FAIL] OPEN_APP(Sui) SW={sw:04x}")
                return 1

            # ── T1 GET_VERSION ─────────────────────────────────────
            body, sw = sui_host.drive(ble, apdu.INS_SUI_GET_VERSION, [b"\x00"])
            if sw != SW_SUCCESS or body is None:
                print(f"[FAIL] GET_VERSION SW={sw:04x}")
                return 1
            if body[:3] != bytes([1, 5, 11]) or body[3:] != b"sui":
                print(f"[FAIL] 版本回包 {body!r}")
                return 1
            print("  ✓ 00 00 GET_VERSION → 1.5.11 sui")

            # ── T2 GET_PUBKEY ──────────────────────────────────────
            body, sw = sui_host.drive(
                ble,
                apdu.INS_SUI_GET_PUBLIC_KEY,
                [apdu.encode_path_le(apdu.SUI_PATH)],
            )
            if sw != SW_SUCCESS or body is None:
                print(f"[FAIL] GET_PUBKEY SW={sw:04x}")
                return 1
            public_key, address = split_key_reply(body)
            if public_key != expected_pub:
                print(f"[FAIL] 公钥 {public_key.hex()} != {expected_pub.hex()}")
                return 1
            if address != expected_address:
                print(f"[FAIL] 地址 0x{address.hex()} != 0x{expected_address.hex()}")
                return 1
            print("  ✓ 00 02 GET_PUBKEY 与独立派生一致")

            # ── T3 原生转账签名 ────────────────────────────────────
            tx = sui_host.native_transfer_tx(expected_address, RECIPIENT, AMOUNT)
            _, sw = sui_host.drive(
                ble,
                apdu.INS_SUI_SIGN_TX,
                [sui_host.encode_sign_param(tx), apdu.encode_path_le(apdu.SUI_PATH)],
                review=True,
            )
            if sw != SW_SUCCESS:
                print(f"[FAIL] SIGN_TX 起始 SW={sw:04x}")
                return 1

            screens = await sess.app.wait_for_screen({"TransactionScreen"}, timeout=10)
            if "TransactionScreen" not in screens:
                print(f"[FAIL] 未弹出签名确认页：{screens}")
                return 1
            await sess.app.settle(0.8)
            hit = await sess.app.tap_key("sign-approve")
            if not hit.startswith("TAPPED"):
                print(f"[FAIL] 点不到 Approve：{hit!r}")
                return 1

            data, sw = parse_response(ble.recv(timeout=20))
            if sw != SW_SUCCESS:
                print(f"[FAIL] 签名响应 SW={sw:04x}")
                return 1
            if len(data) != 1 + 64 or data[0] != 0x01:
                print(f"[FAIL] 签名回包 {data.hex()}")
                return 1
            edsig.verify(expected_pub, tx, data[1:])
            print("  ✓ 00 03 SIGN_TX 独立验签通过（签的是整段交易字节）")

            # ── T4 不可识别的交易必须被拒绝 ────────────────────────
            bad_tx = sui_host.unsupported_move_call_tx(expected_address)
            _, sw = sui_host.drive(
                ble,
                apdu.INS_SUI_SIGN_TX,
                [
                    sui_host.encode_sign_param(bad_tx),
                    apdu.encode_path_le(apdu.SUI_PATH),
                ],
            )
            if sw != SW_NOT_SUPPORTED:
                print(f"[FAIL] 不可识别交易 SW={sw:04x}，期望 0x6808")
                return 1
            print("  ✓ MoveCall 交易被拒绝（0x6808，无盲签）")

            # ── T5 用户拒绝 ────────────────────────────────────────
            tx2 = sui_host.native_transfer_tx(expected_address, RECIPIENT, AMOUNT)
            _, sw = sui_host.drive(
                ble,
                apdu.INS_SUI_SIGN_TX,
                [sui_host.encode_sign_param(tx2), apdu.encode_path_le(apdu.SUI_PATH)],
                review=True,
            )
            if sw != SW_SUCCESS:
                print(f"[FAIL] 第二次 SIGN_TX 起始 SW={sw:04x}")
                return 1
            screens = await sess.app.wait_for_screen({"TransactionScreen"}, timeout=10)
            if "TransactionScreen" not in screens:
                print(f"[FAIL] 未弹出签名确认页：{screens}")
                return 1
            await sess.app.settle(0.8)
            hit = await sess.app.tap_key("sign-reject")
            if not hit.startswith("TAPPED"):
                print(f"[FAIL] 点不到 Reject：{hit!r}")
                return 1
            _, sw = parse_response(ble.recv(timeout=20))
            if sw != SW_USER_DENIED:
                print(f"[FAIL] 拒绝后的 SW={sw:04x}，期望 0x6985")
                return 1
            print("  ✓ 用户拒绝 → 0x6985")

    print("[OK] sui_sign 通过")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
