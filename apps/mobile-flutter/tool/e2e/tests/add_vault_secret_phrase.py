#!/usr/bin/env python3
"""新增金库（暗语模式）用例：管理金库 → 新建金库 → 使用暗语 → PIN。

先清数据用固定测试助记词建主钱包，再从金库管理器里的「新建金库」进入
暗语（Enigma）流程，验证暗语派生的钱包被**追加**为第二个金库，而不是
覆盖主钱包：

  1. Manage Vaults → New Vault → ImportMnemonicScreen（标题栏 "New Vault"，
     顶部模式 tab：Import phrase / Secret phrase）；
  2. 暗语 + 密钥 → Generate → 24 词语 → Continue → SetPinScreen；
  3. 单相位 PIN 复用会话凭据 → 回到 Accounts，切换器里出现 "Vault 2"。

固定测试钱包与 PIN 来自 harness（BIP-39 官方测试向量，零余额、公开）。
暗语派生的助记词与主钱包不同（否则 addVault 会以 "already in tier" 拒绝）。
"""
from __future__ import annotations

import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harness.app import FlutterApp  # noqa: E402
from harness.attach import AttachSession  # noqa: E402
from harness.device import TEST_PIN, Device  # noqa: E402
from harness.env import APP_DIR, PACKAGE  # noqa: E402
from harness.wallet import ensure_unlocked  # noqa: E402

# ASCII-only inputs: adb `input text` has no reliable CJK support. The riddle
# must contain BIP-39 words to contribute entropy (the seam is English by
# default), so a plain English sentence is used.
RIDDLE = "second vault add abandon ability able"
SECRET = "vault-two-key"


async def _tap(app: FlutterApp, key: str, what: str) -> None:
    """点一个带 Key 的控件，失败即抛。"""
    hit = await app.tap_key(key)
    if not hit.startswith("TAPPED"):
        raise RuntimeError(f"未点到 {what}（{key}）：{hit}")


async def run() -> int:
    dev = Device.connect()
    dev.clear_data()

    with AttachSession.start(cwd=APP_DIR, package=PACKAGE) as session:
        app = await FlutterApp.connect(session.vm_service_uri)
        try:
            screens = await ensure_unlocked(dev, app)
            if "MainScreen" not in screens:
                print(f"[FAIL] 未进入主屏：{screens}")
                return 1
            await app.settle(1.0)

            # ── 1. 金库管理器 → 新建金库 ───────────────────────────────
            await _tap(app, "vault-switcher-title", "金库切换器标题")
            await app.settle(0.8)
            hit = await app.tap_text("Manage Vaults")
            if not hit.startswith("TAPPED"):
                print(f"[FAIL] 未点到 Manage Vaults：{hit}")
                return 1
            await app.settle(0.8)

            await _tap(app, "new-vault-row", "New Vault")
            screens = await app.wait_for_screen({"ImportMnemonicScreen"}, timeout=8)
            if "ImportMnemonicScreen" not in screens:
                print(f"[FAIL] 未进入新金库导入屏：{screens}")
                return 1
            await app.settle(0.8)

            if not await app.has_text("New Vault"):
                print("[FAIL] 新金库流程没有显示 New Vault 标题")
                return 1
            # 暗语是同一页面上的模式 tab，不跳新页面：点完仍停在导入屏。
            await _tap(app, "add-vault-tab-secret", "Secret phrase tab")
            await app.settle(0.8)
            screens = await app.screen()
            if "ImportMnemonicScreen" not in screens:
                print(f"[FAIL] 暗语 tab 切走了页面：{screens}")
                return 1

            # ── 2. 暗语 → 24 词 → PIN ─────────────────────────────────
            await _tap(app, "enigma-riddle", "暗语输入框")
            await app.settle(0.6)
            dev.input_text(RIDDLE)
            await app.settle(0.8)

            await _tap(app, "enigma-secret", "密钥输入框")
            await app.settle(0.6)
            dev.input_text(SECRET)
            await app.settle(0.8)

            await _tap(app, "enigma-generate", "Generate")
            screens = await app.wait_for_screen({"EnigmaMnemonicScreen"}, timeout=10)
            if "EnigmaMnemonicScreen" not in screens:
                print(f"[FAIL] 暗语未生成 24 词：{screens}")
                return 1
            await app.settle(1.0)

            await _tap(app, "enigma-mnemonic-continue", "Continue")
            screens = await app.wait_for_screen({"SetPinScreen"}, timeout=8)
            if "SetPinScreen" not in screens:
                print(f"[FAIL] 未进入 PIN 输入：{screens}")
                return 1
            await app.settle(0.8)

            # 新增金库是单相位 PIN（复用当前会话凭据），不进入确认相位。
            for d in TEST_PIN:
                await app.tap_key(f"pin-btn-{d}")
                await app.settle(0.15)
            screens = await app.wait_for_screen({"MainScreen"}, timeout=12)
            if "MainScreen" not in screens:
                print(f"[FAIL] 新增金库后未回到主屏：{screens}")
                return 1
            print("  ✓ 暗语金库已追加并返回主屏")

            # ── 3. 金库列表里出现第二个金库 ────────────────────────────
            await app.settle(0.8)
            await _tap(app, "vault-switcher-title", "金库切换器标题")
            await app.settle(0.8)
            if not await app.has_text("Vault 2"):
                print(f"[FAIL] 金库列表里没有第二个金库，文本：{await app.texts()}")
                return 1
            print("  ✓ 金库列表里出现 Vault 2")
        finally:
            await app.aclose()

    print("[OK] 暗语模式新增金库通过")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
