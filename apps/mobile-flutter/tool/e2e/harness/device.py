"""设备侧准备：清数据 / 冷启动 / 驱动钱包创建与解锁（用例共用）。

固定测试钱包用 BIP-39 官方测试向量（全 abandon + about）——零余额、公开、
地址可预测，适合做确定性 E2E。
"""
from __future__ import annotations

from .env import PACKAGE, adb, detect_serial

TEST_MNEMONIC = (
    "abandon abandon abandon abandon abandon abandon "
    "abandon abandon abandon abandon abandon about"
)
TEST_PIN = "135790"


class Device:
    def __init__(self, serial: str) -> None:
        self.serial = serial

    @classmethod
    def connect(cls, serial: str | None = None) -> "Device":
        return cls(detect_serial(serial))

    # ── adb 层 ────────────────────────────────────────────────────────

    def clear_data(self) -> None:
        """清空 App 数据 → 下次冷启动落到 Welcome（视为无钱包）。

        优先 `pm clear`；本设备（部分 ROM）会以 SecurityException 拒绝 shell
        执行 CLEAR_APP_USER_DATA，此时回退到 debug 包可用的 `run-as` 直接删除
        持久化文件。
        """
        out = adb(self.serial, "shell", "pm", "clear", PACKAGE, capture=True)
        if "Exception" not in out and "Failed" not in out:
            return
        # run-as 仅对 debuggable 包可用；先停进程避免退出时回写，再删全部
        # SharedPreferences XML（secure storage / 旧明文迁移源都在这里）。
        self.stop_app()
        for name in (
            "FlutterSecureStorage.xml",
            "FlutterSecureKeyStorage.xml",
            "FlutterSharedPreferences.xml",
        ):
            adb(self.serial, "shell", "run-as", PACKAGE,
                "rm", "-f", f"shared_prefs/{name}")

    def stop_app(self) -> None:
        adb(self.serial, "shell", "am", "force-stop", PACKAGE)

    def start_app(self) -> None:
        adb(self.serial, "shell", "monkey", "-p", PACKAGE,
            "-c", "android.intent.category.LAUNCHER", "1")

    def is_running(self) -> bool:
        return bool(adb(self.serial, "shell", "pidof", PACKAGE, capture=True).strip())

    def ble_permissions_ok(self) -> bool:
        """BLE 外设需要的三个运行时权限是否已授予。

        本机 ROM 拒绝 shell 执行 `pm grant` / `appops set`，唯一可行方式是
        安装时带上 `-g`：`adb install -r -g <apk>`（或在系统设置里手动授予）。
        """
        out = adb(self.serial, "shell", "dumpsys", "package", PACKAGE, capture=True)
        return all(
            f"{perm}: granted=true" in out
            for perm in (
                "android.permission.BLUETOOTH_ADVERTISE",
                "android.permission.BLUETOOTH_CONNECT",
                "android.permission.BLUETOOTH_SCAN",
            )
        )

    def input_text(self, text: str) -> None:
        """把文本送进当前焦点输入框（走系统 IME）。空格需转义为 %s。"""
        adb(self.serial, "shell", "input", "text", text.replace(" ", "%s"))
