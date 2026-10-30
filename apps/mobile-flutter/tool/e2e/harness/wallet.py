"""通过 UI 驱动把设备带到「已解锁 + 指定链广播中」的确定状态。

固定测试钱包用 BIP-39 官方测试向量（全 abandon + about）——零余额、公开、
地址可预测：
  ETH m/44'/60'/0'/0/0 → 0x9858EfFD232B4033E47d90003D41EC34EcaEda94
"""
from __future__ import annotations

from .device import TEST_MNEMONIC, TEST_PIN, Device
from .env import adb

KICKOFF = {"WelcomeScreen", "UnlockScreen", "MainScreen"}


async def unlock(app, pin: str = TEST_PIN) -> list[str]:
    """在 UnlockScreen 输入 PIN → MainScreen。"""
    await app.wait_for_screen({"UnlockScreen"})
    await app.settle(0.6)
    for d in pin:
        await app.tap_key(f"unlock-btn-{d}")
        await app.settle(0.12)
    return await app.wait_for_screen({"MainScreen"}, timeout=10)


async def create_wallet(
    dev: Device,
    app,
    mnemonic: str = TEST_MNEMONIC,
    pin: str = TEST_PIN,
) -> list[str]:
    """WelcomeScreen → 导入助记词 → 设 PIN → MainScreen。"""
    await app.wait_for_screen({"WelcomeScreen"})
    await app.settle(0.6)

    await app.tap_key("entry-import")
    await app.wait_for_screen({"ImportMnemonicScreen"})
    await app.settle(0.8)

    await app.tap_key("mnemonic-input")
    await app.settle(0.8)
    dev.input_text(mnemonic)
    await app.settle(1.2)
    # 收起软键盘，避免它压缩视口把 Import 按钮挤出屏幕
    adb(dev.serial, "shell", "input", "keyevent", "111")
    await app.settle(0.8)

    # Import（已校验通过才可用）。按稳定 ValueKey 点：按钮由 ImportButton 自绘，
    # runtimeType 不是 PrimaryButton，`tap_type("PrimaryButton")` 会 NOT_FOUND。
    hit = await app.tap_key("import-mnemonic-submit")
    if not hit.startswith("TAPPED"):
        raise RuntimeError(f"未点到 Import：{hit}")
    await app.wait_for_screen({"SetPinScreen"}, timeout=8)
    await app.settle(0.8)

    for _phase in range(2):  # 输入 → 确认
        for d in pin:
            await app.tap_key(f"pin-btn-{d}")
            await app.settle(0.15)
        await app.settle(1.0)
    return await app.wait_for_screen({"MainScreen"}, timeout=10)


async def ensure_unlocked(dev: Device, app, *, pin: str = TEST_PIN) -> list[str]:
    """把设备带到 MainScreen：已有钱包则解锁，没有则用固定助记词创建。

    清数据（Dev·clear_data）应在 attach 之前完成，这样冷启动才落到 Welcome。
    """
    screens = await app.wait_for_screen(KICKOFF, timeout=15)
    if "MainScreen" in screens:
        return screens
    if "UnlockScreen" in screens:
        return await unlock(app, pin)
    return await create_wallet(dev, app, pin=pin)


async def start_broadcast(dev: Device, app, chain_id: str = "ethereum") -> None:
    """在 Vault 屏打开 BLE sheet，点选链 tile 开始广播，然后关闭 sheet。

    点选后 sheet 会切到日志视图（那里没有关闭按钮），故用系统返回键关掉 modal；
    不关会盖住所弹出的签名确认页。

    解锁刚结束时 FAB 还在路由转场里，先 settle 一下再点，避免偶发的
    `ble-chain-*` NOT_FOUND。
    """
    await app.settle(1.0)
    await app.tap_type("BleFab")
    await app.settle(1.2)
    hit = await app.tap_key(f"ble-chain-{chain_id}")
    if not hit.startswith("TAPPED"):
        raise RuntimeError(f"未点到 {chain_id} 链 tile：{hit}")
    await app.settle(2.0)

    logs = await app.texts()
    if not any("broadcasting" in t.lower() for t in logs):
        raise RuntimeError(f"BLE 未进入 broadcasting，设备日志：{logs[-6:]}")

    adb(dev.serial, "shell", "input", "keyevent", "4")  # BACK 关闭 modal sheet
    await app.settle(0.6)
