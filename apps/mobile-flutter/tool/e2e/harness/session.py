"""一次真机 E2E 会话：attach + 把设备带到「固定钱包已解锁 + 指定链广播中」。

用法：
    async with DeviceSession.start(fresh=True) as sess:
        with sess.ble_connected() as ble:
            ...
"""
from __future__ import annotations

import contextlib
from typing import Iterator

from .app import FlutterApp
from .attach import AttachSession
from .ble import GattCentral
from .device import Device
from .env import APP_DIR, PACKAGE
from .wallet import ensure_unlocked, start_broadcast


class DeviceSession:
    def __init__(self, dev: Device, app: FlutterApp) -> None:
        self.dev = dev
        self.app = app

    @classmethod
    @contextlib.asynccontextmanager
    async def start(
        cls,
        *,
        fresh: bool = True,
        chain_id: str | None = "ethereum",
        serial: str | None = None,
    ):
        """fresh=True 先清数据再冷启动（落到 Welcome 并创建固定钱包）。
        chain_id 非空则顺便打开 BLE sheet 选中该链开始广播。
        """
        dev = Device.connect(serial)
        if fresh:
            dev.clear_data()  # 必须在 attach 冷启动之前，否则 App 已读到旧状态
        with AttachSession.start(cwd=APP_DIR, package=PACKAGE, serial=serial) as attach:
            app = await FlutterApp.connect(attach.vm_service_uri)
            try:
                await ensure_unlocked(dev, app)
                if chain_id:
                    if not dev.ble_permissions_ok():
                        raise RuntimeError(
                            "BLE 运行时权限未授予。用 `adb install -r -g <apk>` 重装，或"
                            "在系统设置里手动授予「附近的设备」权限。")
                    await start_broadcast(dev, app, chain_id)
                yield cls(dev, app)
            finally:
                await app.aclose()

    @contextlib.contextmanager
    def ble_connected(self, scan_timeout: float = 25.0) -> Iterator[GattCentral]:
        """作为 host 扫描并连接设备的 GATT，订阅响应 notify。"""
        ble = GattCentral()
        ble.start()
        try:
            ble.scan(scan_timeout)
            ble.connect()
            ble.start_notify()
            yield ble
        finally:
            ble.close()
