#!/usr/bin/env python3
"""E2E：ETH GET_PUBLIC_KEY P1=0x01 地址确认（T-016）。

覆盖两条终止路径：

  1. 点 Reject → host 立即收到 0x6985；
  2. 不操作，等确认屏 60s 倒计时到期 → host 仍收到终态 SW，
     而不是"什么都不回、只能等 host 自己超时"。

运行（macOS 走 CoreBluetooth，首次需给终端蓝牙权限）：

    ANDROID_SERIAL=<serial> python3 tool/e2e/tests/address_confirm.py

注意：`fresh=True` 会清空 App 数据并重建固定测试钱包，只用于专用测试机。
"""
from __future__ import annotations

import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harness.apdu import parse_response  # noqa: E402
from harness.ble_transport import open_gatt  # noqa: E402
from harness.session import DeviceSession  # noqa: E402

CLA_OS = 0xE0
INS_GET_PUBLIC_KEY = 0x02
P1_CONFIRM = 0x01
P2_NO_CHAIN_CODE = 0x00

SW_USER_REJECTED = 0x6985
SW_TIMEOUT = 0x6400

# 不发 Lc/data：设备默认用 m/44'/60'/0'/0/0。
CONFIRM_ADDRESS = bytes([CLA_OS, INS_GET_PUBLIC_KEY, P1_CONFIRM, P2_NO_CHAIN_CODE])


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


async def open_confirm_screen(ble, app) -> None:
    """发 P1=0x01，等地址确认页出现。"""
    ble.send(CONFIRM_ADDRESS)
    screens = await app.wait_for_screen({"AddressConfirmScreen"}, timeout=10)
    expect("AddressConfirmScreen" in screens, f"未弹出地址确认页：{screens}")


async def run() -> int:
    serial = os.environ.get("ANDROID_SERIAL") or None
    async with DeviceSession.start(
            fresh=True, chain_id="ethereum", serial=serial) as sess:
        app = sess.app
        ble = open_gatt()
        try:
            address = ble.scan(25)
            print(f"  ✓ 发现设备 {address}")
            ble.connect()
            ble.start_notify()
            print(f"  ✓ 已连接，MTU={ble.get_mtu()}")

            # ── 1) 用户拒绝 ─────────────────────────────────────────
            print("\n[1/2] 用户点 Reject → 立即回 0x6985")
            await open_confirm_screen(ble, app)
            print("  ✓ 设备弹出地址确认页")

            hit = await app.tap_key("address-confirm-reject")
            expect(hit.startswith("TAPPED"), f"点不到 Reject：{hit!r}")

            data, sw = parse_response(ble.recv(timeout=15))
            expect(sw == SW_USER_REJECTED,
                   f"拒绝后 SW=0x{sw:04x}，期望 0x6985")
            expect(not data, f"拒绝响应不应带数据：{data.hex()}")

            screens = await app.wait_for_screen({"MainScreen"}, timeout=5)
            expect("MainScreen" in screens, f"拒绝后未回到主屏：{screens}")
            print("  ✓ host 收到 0x6985，确认页已关闭")

            # ── 2) 用户不操作，等倒计时 ─────────────────────────────
            print("\n[2/2] 不操作，等确认屏 60s 倒计时到期 → 终态 SW")
            await app.settle(1.0)
            await open_confirm_screen(ble, app)
            print("  ✓ 设备再次弹出地址确认页（等 60s）")

            data, sw = parse_response(ble.recv(timeout=75))
            expect(sw in (SW_USER_REJECTED, SW_TIMEOUT),
                   f"倒计时结束后 SW=0x{sw:04x}，期望 0x6985 或 0x6400")
            expect(not data, f"超时响应不应带数据：{data.hex()}")
            source = ("屏幕倒计时" if sw == SW_USER_REJECTED else "状态层兜底")
            print(f"  ✓ host 收到 0x{sw:04x}（{source}），不再是静默")

            screens = await app.wait_for_screen({"MainScreen"}, timeout=5)
            expect("MainScreen" in screens, f"超时后未回到主屏：{screens}")
            print("  ✓ 确认页已关闭")
        finally:
            ble.close()

    print("\n[OK] address_confirm 通过")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
