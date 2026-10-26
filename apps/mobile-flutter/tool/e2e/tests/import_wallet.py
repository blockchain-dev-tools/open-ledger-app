#!/usr/bin/env python3
"""导入助记词用例（T-009）：BIP-39 前缀联想 + 24 词导入。

覆盖可通过 VM Service 驱动的两条路径：
  1. 输入未完成的前缀 "aban" → 出现候选 "abandon" → 点击补全为完整词 + 空格；
  2. 继续输入到 24 词 → 计数 "24 / 24"、校验通过 → Import 进入 SetPinScreen。

相机扫码需要真实相机与系统权限弹窗，无法由本 harness 驱动；手动步骤见
`docs/testing/e2e-checklist.md` 的 Wallet lifecycle 一节。

每次运行先清 App 数据。24 词短语使用 BIP-39 官方零熵向量
（23 × abandon + art）——零余额、公开，绝不可接收资产。
"""
from __future__ import annotations

import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harness.app import FlutterApp  # noqa: E402
from harness.attach import AttachSession  # noqa: E402
from harness.device import Device  # noqa: E402
from harness.env import APP_DIR, PACKAGE, adb  # noqa: E402

# BIP-39 256-bit zero-entropy vector: 23 × "abandon" + "art".
# The suggestion tap already leaves "abandon " in the field, so type the rest.
REST_WORDS = " ".join(["abandon"] * 22 + ["art"])


async def _exists(app: FlutterApp, key: str) -> bool:
    """按 ValueKey 判断控件是否存在（不受 `keys()` 的字符预算影响）。"""
    geom = await app.find("key", key)
    return bool(geom) and not geom.startswith("NOT_FOUND")


async def run() -> int:
    dev = Device.connect()
    dev.clear_data()

    with AttachSession.start(cwd=APP_DIR, package=PACKAGE) as session:
        app = await FlutterApp.connect(session.vm_service_uri)
        try:
            screens = await app.wait_for_screen({"WelcomeScreen"}, timeout=15)
            if "WelcomeScreen" not in screens:
                print(f"[FAIL] 清数据后未落到 Welcome：{screens}")
                return 1

            await app.tap_key("entry-import")
            screens = await app.wait_for_screen({"ImportMnemonicScreen"})
            if "ImportMnemonicScreen" not in screens:
                print(f"[FAIL] 未进入导入屏：{screens}")
                return 1
            await app.settle(0.8)

            # ── 1. 前缀 → 候选 → 点击补全 ─────────────────────────────
            await app.tap_key("mnemonic-input")
            await app.settle(0.6)
            dev.input_text("aban")
            await app.settle(1.2)

            if not await _exists(app, "mnemonic-suggestion-abandon"):
                print("[FAIL] 输入 aban 后没有出现 abandon 候选")
                return 1

            hit = await app.tap_key("mnemonic-suggestion-abandon")
            if not hit.startswith("TAPPED"):
                print(f"[FAIL] 点击候选失败：{hit}")
                return 1
            await app.settle(0.8)

            if await _exists(app, "mnemonic-suggestion-abandon"):
                print("[FAIL] 补全后候选仍在（应变成完整词并补空格）")
                return 1
            print("  ✓ 前缀 → 候选 → 点击补全")

            # ── 2. 继续输入到 24 词 ───────────────────────────────────
            dev.input_text(REST_WORDS)
            await app.settle(1.5)
            adb(dev.serial, "shell", "input", "keyevent", "111")  # 收起键盘
            await app.settle(0.8)

            texts = await app.texts()
            if "24 / 24 words" not in texts:
                print(f"[FAIL] 词数计数错误，末尾文本：{texts[-8:]}")
                return 1
            if "Valid recovery phrase" not in texts:
                print(f"[FAIL] 24 词未被判为有效，末尾文本：{texts[-8:]}")
                return 1
            print("  ✓ 24 词：计数 24 / 24、校验通过")

            # ── 3. Import → PIN 设置 ──────────────────────────────────
            hit = await app.tap_key("import-mnemonic-submit")
            if not hit.startswith("TAPPED"):
                print(f"[FAIL] 未点到 Import：{hit}")
                return 1
            screens = await app.wait_for_screen({"SetPinScreen"}, timeout=8)
            if "SetPinScreen" not in screens:
                print(f"[FAIL] 24 词导入未进入 PIN 设置：{screens}")
                return 1
            print("  ✓ 24 词导入进入 PIN 设置")
        finally:
            await app.aclose()

    print("[OK] 联想补全与 24 词导入通过（相机扫码需按 checklist 手动验证）")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
