#!/usr/bin/env python3
"""前台闲置自动锁 + 前后台锁的真机用例（T-004 / D-015）。

覆盖三件事：
  1. 滑动窗口：有操作时持续顺延，不会「进前台固定 N 分钟」就锁；
  2. 停止操作满 N 分钟 → 自动锁，回到 UnlockScreen；
  3. J8 生命周期接线：HOME 压后台满 N 分钟再回前台 → 立即锁。

慢用例：默认时长 5 分钟，全流程会跑 ~15 分钟（见 `decisions/D-015`）。
"""
from __future__ import annotations

import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harness.env import adb  # noqa: E402
from harness.session import DeviceSession  # noqa: E402
from harness.wallet import unlock  # noqa: E402

# 与 BleSession 的默认 5 分钟一致。
LOCK_AFTER_SECONDS = 5 * 60
WAIT_BUFFER_SECONDS = 15
SLIDE_INTERVAL_SECONDS = 40


async def _tap_activity(dev, app) -> None:
    """注入一次前台点击：打开 BLE sheet 再返回，能确认仍停在 MainScreen。"""
    hit = await app.tap_type("BleFab")
    assert hit.startswith("TAPPED"), hit
    await app.settle(0.6)
    adb(dev.serial, "shell", "input", "keyevent", "4")  # BACK 关闭 sheet
    await app.settle(0.6)


async def _wait_for_lock(app, timeout: float = 25.0) -> list[str]:
    return await app.wait_for_screen({"UnlockScreen"}, timeout=timeout)


async def run() -> int:
    async with DeviceSession.start(fresh=False, chain_id=None) as session:
        dev, app = session.dev, session.app
        assert "MainScreen" in await app.screen(), await app.screen()

        # ── 1. 滑动窗口：每 40s 一次操作，跨过两个完整窗口仍不锁 ──────
        for _ in range(3):
            await asyncio.sleep(SLIDE_INTERVAL_SECONDS)
            assert "MainScreen" in await app.screen(), "操作间隙被提前锁定"
            await _tap_activity(dev, app)
        assert "MainScreen" in await app.screen(), "有操作时不应锁定"
        print("  ✓ 滑动窗口：操作持续顺延，未提前锁定")

        # ── 2. 停止操作 → 满窗口后自动锁 ─────────────────────────────
        screens = await _wait_for_lock(
            app, timeout=LOCK_AFTER_SECONDS + WAIT_BUFFER_SECONDS)
        if "UnlockScreen" not in screens:
            print(f"[FAIL] 闲置未锁定，当前屏：{screens}")
            return 1
        print("  ✓ 闲置满窗口后自动锁定")

        # ── 3. J8：HOME 压后台满窗口，回前台立即锁 ────────────────────
        await unlock(app)
        assert "MainScreen" in await app.screen(), await app.screen()

        adb(dev.serial, "shell", "input", "keyevent", "3")  # HOME
        await asyncio.sleep(LOCK_AFTER_SECONDS + WAIT_BUFFER_SECONDS)
        dev.start_app()
        screens = await _wait_for_lock(app, timeout=20)
        if "UnlockScreen" not in screens:
            print(f"[FAIL] 回前台未锁定，当前屏：{screens}")
            return 1
        print("  ✓ 后台超时回前台立即锁定（J8 接线生效）")

    print("[OK] 前台闲置 / 后台自动锁均按预期")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
