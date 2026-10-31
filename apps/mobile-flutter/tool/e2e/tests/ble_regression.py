#!/usr/bin/env python3
"""BLE 回归套件——任何 BLE/APDU 改动后都应该跑一遍。

不针对单个 ticket，覆盖整条链路：

  1. 空口发现 → 连接 → 订阅 notify → 协商 MTU
  2. ETH：GET_VERSION / GET_APP_CONFIGURATION
  3. ETH：GET_PUBLIC_KEY（数据超过 MTU，走多分片重组）+ 独立派生比对地址
  4. 错误路径：未知 INS → 6D00，未知 CLA → 6E00
  5. OPEN_APP 切到 Solana / Tron，各自 GET_VERSION 与 GET_ADDRESS
  6. QUIT_APP 回 dashboard：GET_APP_AND_VERSION 报告 format=0，`E0 01` 拒绝
  7. 断连重连后协议仍可用
  8. 蓝牙关/开：App 自愈（T-011）→ UI 回到 Broadcasting → 重新连接并跑 APDU

运行方式（本机即可，macOS 走 CoreBluetooth、Linux 走 BlueZ）：

    python3 tool/e2e/tests/ble_regression.py

首次运行会自动编译 `tool/e2e/ble-central`（Rust + btleplug）。macOS 首次会请求
终端使用蓝牙的权限（系统设置 → 隐私与安全性 → 蓝牙）。

环境变量：
    ANDROID_SERIAL   目标设备（多台在线时必填）

前提：debug 包已安装且授予 BLE 权限（`adb install -r -g`），测试机可被
`svc bluetooth` 改状态。
"""
from __future__ import annotations

import asyncio
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harness import apdu, ethsig  # noqa: E402
from harness.apdu import SW_SUCCESS, encode_path, parse_response  # noqa: E402
from harness.ble_transport import open_gatt  # noqa: E402
from harness.device import TEST_MNEMONIC  # noqa: E402
from harness.env import adb  # noqa: E402
from harness.session import DeviceSession  # noqa: E402

LEDGER_SERVICE_UUID = "13d63400-2c97-0004-0000-4c6564676572"
PACKAGE = "app.openledger.mobile"

CLA_OS = 0xE0
CLA_GLOBAL = 0xB0
INS_GET_VERSION = 0x01
INS_OPEN_APP = 0xD8
INS_QUIT_APP = 0xA7
INS_SOL_ADDR = 0x05
INS_TRON_ADDR = 0x02
INS_TRON_VERSION = 0x06

SW_INS_NOT_SUPPORTED = 0x6D00
SW_CLA_NOT_SUPPORTED = 0x6E00

SOL_PATH = "m/44'/501'/0'/0'"
TRON_PATH = "m/44'/195'/0'/0/0"


# ── 断言小工具 ──────────────────────────────────────────────────────────

def expect(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def expect_sw(ble, payload: bytes, expected_sw: int, label: str,
              timeout: float = 15.0) -> bytes:
    response = ble.exchange(payload, timeout=timeout)
    data, sw = parse_response(response)
    expect(sw == expected_sw,
           f"{label}: SW={sw:04x}，期望 {expected_sw:04x}（resp={response.hex()}）")
    print(f"  ✓ {label} → SW={sw:04x}")
    return data


def parse_app_and_version(data: bytes) -> tuple[int, str, str]:
    """`[format][name_len][name][ver_len][ver][flags_len][flags]`。"""
    expect(len(data) >= 4, f"GET_APP_AND_VERSION 响应过短: {data.hex()}")
    fmt = data[0]
    pos = 1
    name_len = data[pos]
    pos += 1
    name = data[pos:pos + name_len].decode("utf-8", "replace")
    pos += name_len
    ver_len = data[pos]
    pos += 1
    version = data[pos:pos + ver_len].decode("utf-8", "replace")
    return fmt, name, version


def parse_eth_address(data: bytes) -> tuple[bytes, str]:
    """`[0x41][pubkey 65][addr_len][addr ascii][chain code?]`。"""
    expect(len(data) > 67 and data[0] == 0x41,
           f"ETH GET_PUBLIC_KEY 响应格式异常: {data.hex()[:40]}…")
    pubkey = data[1:66]
    addr_len = data[66]
    address = data[67:67 + addr_len].decode("ascii")
    return pubkey, address


# ── 设备侧小工具 ────────────────────────────────────────────────────────

def bluetooth_on(dev) -> bool:
    out = adb(dev.serial, "shell", "dumpsys", "bluetooth_manager", capture=True)
    for line in out.splitlines():
        stripped = line.strip()
        if stripped.startswith("enabled:"):
            return stripped.split(":", 1)[1].strip() == "true"
        if stripped.startswith("state:"):
            return stripped.split(":", 1)[1].strip().upper().startswith("ON")
    fallback = adb(dev.serial, "shell", "settings", "get", "global",
                   "bluetooth_on", capture=True)
    return fallback.strip().endswith("1")


def gatt_service_registered(dev) -> bool:
    out = adb(dev.serial, "shell", "dumpsys", "bluetooth_manager", capture=True)
    return LEDGER_SERVICE_UUID in out.lower()


def app_pid(dev) -> str:
    return adb(dev.serial, "shell", "pidof", PACKAGE, capture=True).strip()


def wait_until(predicate, timeout: float, interval: float = 1.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(interval)
    return predicate()


def set_bluetooth(dev, enabled: bool) -> None:
    adb(dev.serial, "shell", "svc", "bluetooth",
        "enable" if enabled else "disable")
    if not wait_until(lambda: bluetooth_on(dev) == enabled, timeout=20):
        raise RuntimeError(
            f"系统蓝牙未能切换到 {'开' if enabled else '关'}；"
            "若 ROM 拒绝 shell 改蓝牙状态，请手动用快捷开关执行本用例。")


async def tap_robust(dev, app, by: str, value: str) -> None:
    """点按选择器定位的控件，VM Service 注入失败时退回 adb 点击。

    蓝牙开关后 VM Service 的指针注入偶尔返回空（表达式求值结果不是字符串），
    但同一时刻读几何信息仍然正常；用几何中心换算成物理像素交给 `input tap`。
    """
    hit = ""
    for _ in range(3):
        hit = await app.tap(by, value)
        if hit.startswith("TAPPED"):
            return
        await app.settle(1.0)

    geometry = await app.find(by, value)
    match = re.search(r"center=Offset\(([-\d.]+), ([-\d.]+)\)", geometry)
    if not match:
        raise RuntimeError(f"点不到 {by}={value}：{hit!r} / geom={geometry!r}")
    ratio = device_pixel_ratio(dev)
    x = int(round(float(match.group(1)) * ratio))
    y = int(round(float(match.group(2)) * ratio))
    adb(dev.serial, "shell", "input", "tap", str(x), str(y))
    await app.settle(1.0)


def device_pixel_ratio(dev) -> float:
    out = adb(dev.serial, "shell", "wm", "density", capture=True)
    match = re.search(r"(\d+)", out)
    return int(match.group(1)) / 160.0 if match else 1.0


async def ble_sheet_text(dev, app) -> str:
    """打开 BLE sheet，读控制态与日志后关掉。"""
    await tap_robust(dev, app, "type", "BleFab")
    await app.settle(1.2)
    control = await app.texts()

    await tap_robust(dev, app, "key", "ble-sheet-logs")
    await app.settle(0.8)
    logs = await app.texts()

    adb(dev.serial, "shell", "input", "keyevent", "4")
    await app.settle(0.5)
    return "\n".join(control + logs)


# ── 用例各阶段 ──────────────────────────────────────────────────────────

def stage_link(ble) -> None:
    print("\n[1/8] 空口发现 / 连接 / MTU")
    address = ble.scan(25)
    print(f"  ✓ 发现设备 {address}（匹配方式 {ble.matched_by}）")
    ble.connect()
    ble.start_notify()
    mtu = ble.get_mtu()
    expect(mtu >= 20, f"MTU 异常: {mtu}")
    print(f"  ✓ 已连接，MTU={mtu}")


def stage_eth_basics(ble) -> None:
    print("\n[2/8] ETH：GET_VERSION / GET_APP_CONFIGURATION")
    data = expect_sw(ble, bytes([CLA_OS, INS_GET_VERSION, 0, 0]),
                     SW_SUCCESS, "E0 01 GET_VERSION")
    expect(len(data) > 0, "GET_VERSION 返回空 data")
    data = expect_sw(ble, bytes([CLA_OS, 0x06, 0, 0]),
                     SW_SUCCESS, "E0 06 GET_APP_CONFIGURATION")
    expect(len(data) >= 4, f"GET_APP_CONFIGURATION 响应过短: {data.hex()}")

    fmt, name, version = parse_app_and_version(
        expect_sw(ble, bytes([CLA_GLOBAL, INS_GET_VERSION, 0, 0]),
                  SW_SUCCESS, "B0 01 GET_APP_AND_VERSION"))
    expect(fmt == 0x01, f"已开 App 时 format 应为 0x01，实际 0x{fmt:02x}")
    expect(name.lower() == "ethereum", f"当前 App 应为 Ethereum，实际 {name!r}")
    print(f"  ✓ GET_APP_AND_VERSION → {name} {version}")


def stage_eth_public_key(ble) -> None:
    print("\n[3/8] ETH：GET_PUBLIC_KEY（多分片 + 独立派生比对）")
    request = apdu.get_public_key()
    expect(len(request) > 20,
           f"该用例本意是跨 MTU 分片，APDU 只有 {len(request)} 字节")
    data = expect_sw(ble, request, SW_SUCCESS, "E0 02 GET_PUBLIC_KEY")
    pubkey, address = parse_eth_address(data)
    expected_address, expected_pubkey = ethsig.derive_address(TEST_MNEMONIC)
    expect(pubkey == expected_pubkey, "设备返回的公钥与独立派生不一致")
    expect("0x" + address.lower() == expected_address.lower(),
           f"设备地址 {address} 与独立派生 {expected_address} 不一致")
    print(f"  ✓ 公钥与地址均与独立派生一致（{expected_address}）")


def stage_error_paths(ble) -> None:
    print("\n[4/8] 错误路径")
    expect_sw(ble, bytes([CLA_OS, 0x0F, 0, 0]),
              SW_INS_NOT_SUPPORTED, "未知 INS（E0 0F）")
    expect_sw(ble, bytes([0x99, 0x01, 0, 0]),
              SW_CLA_NOT_SUPPORTED, "未知 CLA（99 01）")


def stage_app_switching(ble) -> None:
    print("\n[5/8] OPEN_APP：Solana / Tron")
    expect_sw(ble, apdu.open_app("Solana"), SW_SUCCESS, "OPEN_APP Solana")
    data = expect_sw(ble, apdu.sol_get_app_configuration(),
                     SW_SUCCESS, "E0 04 SOL GET_APP_CONFIGURATION")
    # [allow_blind_sign][pubkey_display][major][minor][patch]
    expect(len(data) == 5, f"Solana 配置响应长度异常: {data.hex()}")
    expect(data[:2] == bytes([0x00, 0x01]),
           f"Solana 配置响应标志位异常: {data.hex()}")
    data = expect_sw(ble,
                     apdu.apdu(CLA_OS, INS_SOL_ADDR, 0, 0, encode_path(SOL_PATH)),
                     SW_SUCCESS, "E0 05 SOL GET_ADDR")
    expect(len(data) == 32, f"Solana 公钥应为 32 字节，实际 {len(data)}")

    expect_sw(ble, apdu.open_app("Tron"), SW_SUCCESS, "OPEN_APP Tron")
    expect_sw(ble, bytes([CLA_OS, INS_TRON_VERSION, 0, 0]),
              SW_SUCCESS, "E0 06 TRON VERSION")
    data = expect_sw(ble,
                     apdu.apdu(CLA_OS, INS_TRON_ADDR, 0, 0, encode_path(TRON_PATH)),
                     SW_SUCCESS, "E0 02 TRON GET_ADDRESS")
    expect(len(data) > 0, "Tron 地址响应为空")

    expect_sw(ble, apdu.open_app("Ethereum"), SW_SUCCESS, "OPEN_APP Ethereum")


def stage_dashboard(ble) -> None:
    print("\n[6/8] QUIT_APP → dashboard")
    expect_sw(ble, bytes([CLA_OS, INS_QUIT_APP, 0, 0]), SW_SUCCESS, "E0 A7 QUIT_APP")
    expect_sw(ble, bytes([CLA_OS, INS_GET_VERSION, 0, 0]),
              SW_INS_NOT_SUPPORTED, "dashboard 下 E0 01 被拒")
    data = expect_sw(ble, bytes([CLA_GLOBAL, INS_GET_VERSION, 0, 0]),
                     SW_SUCCESS, "B0 01 GET_APP_AND_VERSION")
    fmt, name, version = parse_app_and_version(data)
    expect(fmt == 0x00, f"dashboard 时 format 应为 0x00，实际 0x{fmt:02x}")
    print(f"  ✓ dashboard 报告 {name} {version}")
    expect_sw(ble, apdu.open_app("Ethereum"), SW_SUCCESS, "恢复 OPEN_APP Ethereum")


def stage_reconnect(ble):
    print("\n[7/8] 断连重连")
    ble.close()
    time.sleep(1.0)
    fresh = open_gatt()
    try:
        address = fresh.scan(25)
        print(f"  ✓ 重新发现 {address}")
        fresh.connect()
        fresh.start_notify()
        mtu = fresh.get_mtu()
        expect(mtu >= 20, f"重连后 MTU 异常: {mtu}")
        expect_sw(fresh, bytes([CLA_OS, INS_GET_VERSION, 0, 0]),
                  SW_SUCCESS, "重连后 E0 01 GET_VERSION")
    except Exception:
        fresh.close()
        raise
    return fresh


async def stage_bluetooth_toggle(dev, app, ble):
    print("\n[8/8] 蓝牙关/开自愈（T-011）")
    pid_before = app_pid(dev)
    expect(bool(pid_before), "App 未在运行，无法校验自愈")

    set_bluetooth(dev, False)
    set_bluetooth(dev, True)
    if not wait_until(lambda: gatt_service_registered(dev), timeout=45):
        raise RuntimeError("蓝牙恢复后 45s 内 Ledger GATT service 没有重新注册")
    expect(app_pid(dev) == pid_before,
           f"进程被重启（{pid_before} → {app_pid(dev)}），恢复不是自愈")
    print("  ✓ 进程未重启，GATT service 已重新注册")

    sheet = await ble_sheet_text(dev, app)
    expect("broadcasting" in sheet.lower(), f"App 未回到 Broadcasting：{sheet[-400:]}")
    expect("Advertising → advertising" in sheet, "App 日志里没有新的 advertising 事件")
    expect("Already advertising or connected." not in sheet,
           "仍出现旧的假绿日志，早退逻辑未修复")
    print("  ✓ UI 回到 Broadcasting，日志出现新的 advertising")

    ble.close()
    fresh = open_gatt()
    try:
        fresh.scan(25)
        fresh.connect()
        fresh.start_notify()
        expect_sw(fresh, bytes([CLA_OS, INS_GET_VERSION, 0, 0]),
                  SW_SUCCESS, "恢复后 E0 01 GET_VERSION")
    except Exception:
        fresh.close()
        raise
    print("  ✓ 恢复后的链路可连接、可收发 APDU")
    return fresh


# ── 主流程 ──────────────────────────────────────────────────────────────

async def run() -> int:
    serial = os.environ.get("ANDROID_SERIAL") or None
    async with DeviceSession.start(fresh=True, chain_id="ethereum",
                                   serial=serial) as session:
        dev, app = session.dev, session.app
        expect(bluetooth_on(dev), "用例开始时系统蓝牙是关的，请先打开再跑")

        ble = open_gatt()
        try:
            stage_link(ble)
            stage_eth_basics(ble)
            stage_eth_public_key(ble)
            stage_error_paths(ble)
            stage_app_switching(ble)
            stage_dashboard(ble)
            ble = stage_reconnect(ble)
            ble = await stage_bluetooth_toggle(dev, app, ble)
        finally:
            ble.close()

    print("\n[OK] BLE 回归套件通过")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
