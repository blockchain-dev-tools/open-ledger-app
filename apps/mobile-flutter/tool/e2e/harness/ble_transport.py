"""GATT central for the BLE regression suite.

The radio work is done by `tool/e2e/ble-central` (Rust + btleplug), which maps to
CoreBluetooth on macOS and BlueZ on Linux. `RustGatt` builds it on demand and
speaks one JSON command per line over stdio; fragmentation and reassembly stay
here so the wire format has a single Python implementation
(`harness/ble_framing.py`).

macOS note: the first run asks for Bluetooth permission for the terminal
("System Settings → Privacy & Security → Bluetooth"). Without it the scan simply
finds nothing.
"""
from __future__ import annotations

import json
import os
import pathlib
import queue
import subprocess
import threading
import time
from typing import Any

from .ble_framing import DEFAULT_MTU, TAG_GET_MTU, Reassembler, fragment

TOOL_DIR = pathlib.Path(__file__).resolve().parents[1] / "ble-central"
BINARY = TOOL_DIR / "target" / "release" / "ble-central"


class BleTransportError(RuntimeError):
    pass


_built = False


def _build_if_needed() -> pathlib.Path:
    """Compile the Rust helper once per process.

    Cargo's own up-to-date check is cheap when nothing changed (a few hundred
    milliseconds), so there is no mtime heuristic to get wrong after an edit
    that does not alter the artifact.
    """
    global _built
    if _built and BINARY.exists():
        return BINARY

    print("[ble] 检查/编译 BLE central（首次或有更新时）…", flush=True)
    result = subprocess.run(
        ["cargo", "build", "--release", "--quiet", "--manifest-path",
         str(TOOL_DIR / "Cargo.toml")],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise BleTransportError(
            "编译 BLE central 失败：\n" + (result.stderr or result.stdout)[-2000:])
    if not BINARY.exists():
        raise BleTransportError(f"编译完成但找不到二进制：{BINARY}")
    _built = True
    return BINARY


class RustGatt:
    """Drives `ble-central` over stdio; one synchronous command per call."""

    def __init__(self) -> None:
        binary = _build_if_needed()
        self._proc = subprocess.Popen(
            [str(binary)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, bufsize=1,
        )
        self._lines: queue.Queue[str | None] = queue.Queue()
        self._stderr: list[str] = []
        threading.Thread(target=self._pump_stdout, daemon=True).start()
        threading.Thread(target=self._pump_stderr, daemon=True).start()
        self.matched_by: str | None = None
        self._reasm = Reassembler()

    # ── process plumbing ────────────────────────────────────────────

    def _pump_stdout(self) -> None:
        assert self._proc is not None and self._proc.stdout is not None
        for line in self._proc.stdout:
            self._lines.put(line)
        self._lines.put(None)

    def _pump_stderr(self) -> None:
        assert self._proc is not None and self._proc.stderr is not None
        for line in self._proc.stderr:
            self._stderr.append(line.rstrip())

    def _call(self, payload: dict[str, Any], timeout: float) -> dict[str, Any]:
        if self._proc is None or self._proc.poll() is not None:
            raise BleTransportError(
                "BLE central 已退出：" + " / ".join(self._stderr[-3:]))
        assert self._proc.stdin is not None
        self._proc.stdin.write(json.dumps(payload) + "\n")
        self._proc.stdin.flush()
        try:
            line = self._lines.get(timeout=timeout)
        except queue.Empty as exc:
            raise BleTransportError(
                f"BLE central 无响应（{payload.get('cmd')}，{timeout}s）") from exc
        if line is None:
            raise BleTransportError(
                "BLE central 已退出：" + " / ".join(self._stderr[-3:]))
        result = json.loads(line)
        if not result.get("ok"):
            raise BleTransportError(str(result.get("error")))
        return result

    # ── suite-facing surface ────────────────────────────────────────

    def scan(self, timeout: float) -> str:
        result = self._call({"cmd": "scan", "timeout": timeout}, timeout + 30)
        self.matched_by = result.get("matched_by")
        return str(result.get("address", ""))

    def connect(self) -> None:
        self._call({"cmd": "connect"}, 60)

    def start_notify(self) -> None:
        # `connect` subscribes; kept for API parity with the BlueZ transport.
        self._call({"cmd": "notify"}, 30)

    def get_mtu(self, timeout: float = 5.0) -> int:
        self._call({"cmd": "drain"}, 10)
        self._reasm = Reassembler()
        self._write(bytes([TAG_GET_MTU]))
        payload = self._recv_frame(timeout)
        if len(payload) != 2:
            return DEFAULT_MTU
        return (payload[0] << 8) | payload[1]

    def prepare_recv(self) -> None:
        """开始一次新的请求/响应（与 BlueZ central 的方法名保持一致）。"""
        self._call({"cmd": "drain"}, 10)
        self._reasm = Reassembler()

    def send_raw(self, apdu: bytes, mtu: int = DEFAULT_MTU) -> None:
        """把一段 APDU 按 tag-first 分块写下去（调用方自己管理接收状态）。"""
        for chunk in fragment(apdu, mtu):
            self._write(chunk)

    def send(self, apdu: bytes) -> None:
        """发一条 APDU 但不等待响应（需先驱动 UI 再收响应的用例）。"""
        self.prepare_recv()
        self.send_raw(apdu)

    def recv(self, timeout: float = 15.0) -> bytes:
        """等待并消费一个完整响应。"""
        return self._recv_frame(timeout)

    def exchange(self, apdu: bytes, timeout: float = 15.0) -> bytes:
        self.send(apdu)
        return self.recv(timeout)

    def close(self) -> None:
        if self._proc is None:
            return
        try:
            self._call({"cmd": "quit"}, 10)
        except BleTransportError:
            pass
        finally:
            for pipe in (self._proc.stdin, self._proc.stdout, self._proc.stderr):
                try:
                    pipe and pipe.close()
                except Exception:
                    pass
            try:
                self._proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._proc.terminate()
            self._proc = None

    # ── helpers ─────────────────────────────────────────────────────

    def _write(self, chunk: bytes) -> None:
        self._call({"cmd": "write", "hex": chunk.hex()}, 30)

    def _recv_frame(self, timeout: float) -> bytes:
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise BleTransportError(f"等待响应超时（{timeout}s）")
            result = self._call({"cmd": "recv", "timeout": remaining}, remaining + 15)
            chunk = bytes.fromhex(str(result.get("hex", "")))
            done = self._reasm.feed(chunk)
            if done is not None:
                return done


def open_gatt() -> RustGatt:
    """Radio for the suite: the Rust helper (CoreBluetooth / BlueZ)."""
    if os.environ.get("E2E_BLE_HOST"):
        raise BleTransportError(
            "远端 BlueZ 模式已移除；请直接在本机运行（macOS 用 CoreBluetooth，"
            "Linux 用 BlueZ）。")
    return RustGatt()
