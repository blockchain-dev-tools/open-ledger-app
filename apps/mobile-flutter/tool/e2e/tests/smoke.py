#!/usr/bin/env python3
"""冒烟用例：attach → RPC → evaluate 通路可用 + 页面导航可驱动。

零副作用：不重置钱包、不改设备数据。冷启动后落到 Welcome（无钱包）或 Unlock
（有钱包）都算通过；若落在 Welcome，额外点一次「导入」验证导航真的被驱动。
"""
from __future__ import annotations

import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harness.app import FlutterApp  # noqa: E402
from harness.attach import AttachSession  # noqa: E402
from harness.env import APP_DIR, PACKAGE  # noqa: E402

KICKOFF = {"WelcomeScreen", "UnlockScreen"}


async def run() -> int:
    with AttachSession.start(cwd=APP_DIR, package=PACKAGE) as session:
        print(f"DDS: {session.vm_service_uri}")
        app = await FlutterApp.connect(session.vm_service_uri)
        try:
            screens = await app.screen()
            print(f"当前屏: {screens}")
            if not screens or not (set(screens) & KICKOFF):
                print(f"[FAIL] 冷启动未落在 {KICKOFF}，实际 {screens}")
                return 1

            if "WelcomeScreen" in screens:
                print("在 Welcome：点 entry-import 验证导航 ...")
                result = await app.tap_key("entry-import")
                print(f"  tap -> {result}")
                await asyncio.sleep(1.0)
                after = await app.screen()
                print(f"  跳转后: {after}")
                if "ImportMnemonicScreen" not in after:
                    print("[FAIL] 点击未跳到 ImportMnemonicScreen")
                    return 1
                print("  ✓ 导航被驱动")
            else:
                print("在 Unlock（无 Welcome 可点，跳过导航断言）")

            keys = await app.keys()
            print(f"带 Key 节点: {keys}")
        finally:
            await app.aclose()
    print("[OK] 冒烟通过：通路可用")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
