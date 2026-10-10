"""环境常量与 adb 小工具。"""
from __future__ import annotations

import os
import subprocess
from typing import Optional

# apps/mobile-flutter —— flutter attach 必须在应用目录下运行
APP_DIR = os.path.abspath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..")
)

PACKAGE = "app.openledger.mobile"


def adb(serial: str, *args: str, capture: bool = False) -> str:
    """在指定设备上跑一条 adb 命令；capture=True 时返回 stdout。"""
    proc = subprocess.run(
        ["adb", "-s", serial, *args],
        check=False, text=True,
        stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
        stderr=subprocess.STDOUT if capture else subprocess.DEVNULL,
    )
    return proc.stdout or ""


def detect_serial(explicit: Optional[str] = None) -> str:
    """未显式指定时，从 adb 自动探测唯一的在线设备。"""
    if explicit:
        return explicit
    out = subprocess.run(
        ["adb", "devices"], capture_output=True, text=True, check=False
    ).stdout
    devices = [
        line.split()[0]
        for line in out.splitlines()[1:]
        if line.strip().endswith("device")
    ]
    if len(devices) != 1:
        raise RuntimeError(
            f"需要恰好一台在线设备，当前 {len(devices)} 台：{devices}（用 --serial 指定）"
        )
    return devices[0]
