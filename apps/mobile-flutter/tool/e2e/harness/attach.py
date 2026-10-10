"""托管 `flutter attach` 子进程，并解析它输出的 DDS URI（见 tool/e2e/README.md）。

发现机制：`flutter attach` 扫 logcat 里 App 打印的 "Dart VM Service is listening"
启动行 → 所以要先挂 attach、再启动 App（`restart_app=True` 时由本类代劳）。
"""
from __future__ import annotations

import os
import re
import signal
import subprocess
import threading
import time
from typing import Optional

from .env import detect_serial

_VM_SERVICE_RE = re.compile(r"available at: (http://\S+)")
_WAITING_MARKER = "Waiting for a connection"


def _adb(serial: str, *args: str) -> None:
    subprocess.run(
        ["adb", "-s", serial, *args],
        check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


def _list_forwards(serial: str) -> set[str]:
    """当前已存在的 adb 端口转发（本地端，如 {'tcp:45285'}）。"""
    out = subprocess.run(
        ["adb", "-s", serial, "forward", "--list"],
        capture_output=True, text=True, check=False,
    ).stdout
    return {parts[1] for line in out.splitlines()
            if len(parts := line.split()) >= 3}


def _remove_forward(serial: str, local: str) -> None:
    subprocess.run(
        ["adb", "-s", serial, "forward", "--remove", local],
        check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


def _kill(proc: subprocess.Popen) -> None:
    if proc.poll() is not None:
        return
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        proc.wait(timeout=5.0)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except ProcessLookupError:
            pass


class AttachSession:
    """一个存活的 `flutter attach` + 它给出的 VM Service (DDS) URI。

    仅对 **debug 包** 有效：`evaluate` 依赖 flutter_tools 注册的 compileExpression
    服务，裸 debug APK 直连 VM Service 没有该服务（见 tool/e2e/README.md）。
    """

    def __init__(
        self,
        proc: subprocess.Popen,
        vm_service_uri: str,
        serial: str,
        forwards_before: set[str],
    ) -> None:
        self._proc = proc
        self.vm_service_uri = vm_service_uri
        self._serial = serial
        self._forwards_before = forwards_before

    @classmethod
    def start(
        cls,
        *,
        cwd: str,
        serial: Optional[str] = None,
        package: Optional[str] = None,
        flutter: str = "flutter",
        timeout: float = 180.0,
        restart_app: bool = True,
    ) -> "AttachSession":
        serial = detect_serial(serial)
        # 无 TTY：start_new_session 让 attach 脱离控制终端（等价 setsid），stdin 关掉
        cmd = [flutter, "attach", "-d", serial, "--no-version-check", "--suppress-analytics"]
        forwards_before = _list_forwards(serial)
        proc = subprocess.Popen(
            cmd, cwd=cwd, stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1, start_new_session=True,
        )
        uri: dict[str, Optional[str]] = {"value": None}
        got_uri = threading.Event()
        waiting = threading.Event()
        log: list[str] = []

        def reader() -> None:
            assert proc.stdout is not None
            for line in proc.stdout:
                log.append(line)
                if _WAITING_MARKER in line:
                    waiting.set()
                if uri["value"] is None:
                    m = _VM_SERVICE_RE.search(line)
                    if m:
                        uri["value"] = m.group(1)
                        got_uri.set()
            got_uri.set()  # 进程结束也要唤醒等待者

        threading.Thread(target=reader, daemon=True).start()

        if restart_app and package:
            # attach 靠扫 logcat 发现 App → 必须让 App 在 attach 开始监听之后再启动
            waiting.wait(timeout=20.0)
            _adb(serial, "shell", "am", "force-stop", package)
            time.sleep(0.5)
            _adb(serial, "shell", "monkey", "-p", package,
                 "-c", "android.intent.category.LAUNCHER", "1")

        if not got_uri.wait(timeout):
            _kill(proc)
            raise TimeoutError(
                "等待 flutter attach 的 VM Service URI 超时。\nattach 最近输出：\n"
                + "".join(log[-20:])
            )
        if uri["value"] is None:
            _kill(proc)
            raise RuntimeError(
                "flutter attach 结束但未给出 VM Service URI：\n" + "".join(log[-20:])
            )
        return cls(proc, uri["value"], serial, forwards_before)

    def stop(self) -> None:
        _kill(self._proc)
        # 只清本会话新建的端口转发（被 SIGTERM 的 attach 不总能自清）
        for local in _list_forwards(self._serial) - self._forwards_before:
            _remove_forward(self._serial, local)

    def __enter__(self) -> "AttachSession":
        return self

    def __exit__(self, *exc: object) -> None:
        self.stop()
