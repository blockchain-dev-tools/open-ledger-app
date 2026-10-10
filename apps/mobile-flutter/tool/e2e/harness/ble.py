"""BlueZ（dbus-python）GATT central：作为 host 与设备 BLE 外设通信。

设备使用 tag-first 分帧（见 docs/reference/ble.md 与
`infrastructure/ble/ble_peripheral_universal.dart`）：

- 入站首块：`[tag][seq_hi][seq_lo][total_hi][total_lo][payload]`
- 入站续块：`[tag][seq_hi][seq_lo][payload]`
- 出站（响应）同构；每片单独一条 notify。

tag `0x05` = APDU，`0x08` = GET_MTU（回复固定 7 字节，MTU 在 [5..6]）。

BlueZ 只把瞬时 AD 属性暴露给 `InterfacesAdded`/`PropertiesChanged`，扫描结束后
`GetManagedObjects()` 读到的是缺字段的陈旧状态（AGENTS.md #18），故扫描必须边扫边收。
"""
from __future__ import annotations

import threading
import time

import dbus
import dbus.mainloop.glib
from gi.repository import GLib

SERVICE_UUID = "13d63400-2c97-0004-0000-4c6564676572"
RESP_CHAR_UUID = "13d63400-2c97-0004-0001-4c6564676572"   # read + notify
CMD_CHAR_UUID = "13d63400-2c97-0004-0002-4c6564676572"    # write
CMD_WWR_UUID = "13d63400-2c97-0004-0003-4c6564676572"     # write without response

TAG_APDU = 0x05
TAG_GET_MTU = 0x08
DEFAULT_MTU = 20

# 设备本地名（Android 端默认）。BlueZ 的 Device1.ServiceUUIDs 只反映主广播包，
# 而本设备把 128 位 UUID 放在 scan response（addServicesInScanResponse），
# 于是扫描时按名字兜底匹配；连上后特征仍严格按 UUID 解析。
DEVICE_NAME_PREFIX = "OpenLedger"

BLUEZ = "org.bluez"


class BleError(RuntimeError):
    pass


# ── 分帧 ────────────────────────────────────────────────────────────────

def fragment(apdu: bytes, mtu: int = DEFAULT_MTU, tag: int = TAG_APDU) -> list[bytes]:
    """把一条 APDU 切成 tag-first 分块（首块 5B 头 / 续块 3B 头）。"""
    first_cap = mtu - 5
    cont_cap = mtu - 3
    chunks: list[bytes] = []
    offset = 0
    total = len(apdu)
    seq = 0
    while offset < total or seq == 0:
        if seq == 0:
            payload = apdu[offset:offset + first_cap]
            chunks.append(bytes([tag, (seq >> 8) & 0xFF, seq & 0xFF,
                                 (total >> 8) & 0xFF, total & 0xFF]) + payload)
            offset += len(payload)
        else:
            payload = apdu[offset:offset + cont_cap]
            chunks.append(bytes([tag, (seq >> 8) & 0xFF, seq & 0xFF]) + payload)
            offset += len(payload)
        seq += 1
    return chunks


class _Reassembler:
    """按 seq 组装 tag-first 分块，凑齐 total 后返回上层协议数据。"""

    def __init__(self) -> None:
        self._parts: dict[int, bytes] = {}
        self._total: int | None = None
        self._got = 0
        self.result: bytes | None = None

    def feed(self, chunk: bytes) -> bytes | None:
        if len(chunk) < 3:
            return None
        tag = chunk[0]
        seq = (chunk[1] << 8) | chunk[2]
        if seq == 0 and len(chunk) >= 5:
            self._total = (chunk[3] << 8) | chunk[4]
            payload = chunk[5:]
        else:
            payload = chunk[3:]
        if seq not in self._parts:
            self._parts[seq] = payload
            self._got += len(payload)
        if self._total is not None and self._got >= self._total:
            ordered = b"".join(self._parts[i] for i in sorted(self._parts))
            self.result = ordered[:self._total]
            self._reset()
            return self.result
        return None

    def _reset(self) -> None:
        self._parts.clear()
        self._total = None
        self._got = 0


# ── GATT central ────────────────────────────────────────────────────────

class GattCentral:
    def __init__(self, adapter: str = "hci0") -> None:
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        self.bus = dbus.SystemBus()
        self.adapter_path = f"/org/bluez/{adapter}"
        self.adapter = dbus.Interface(
            self.bus.get_object(BLUEZ, self.adapter_path), f"{BLUEZ}.Adapter1")
        self.om = dbus.Interface(
            self.bus.get_object(BLUEZ, "/"), "org.freedesktop.DBus.ObjectManager")

        self._loop = GLib.MainLoop()
        self._loop_thread: threading.Thread | None = None
        self._device_path: str | None = None
        self._addr: str | None = None
        self._scan_hit = threading.Event()

        self.matched_by: str | None = None
        self._resp_char: str | None = None
        self._cmd_char: str | None = None
        self._notify_chunks: list[bytes] = []
        self._reasm = _Reassembler()
        self._rx: bytes | None = None
        self._rx_event = threading.Event()
        self.mtu = DEFAULT_MTU          # 我方出站分块 MTU（保守）
        self.device_mtu = DEFAULT_MTU   # 设备上报的 MTU（仅记录）

    # ── 生命周期 ──────────────────────────────────────────────────────

    def start(self) -> None:
        self._loop_thread = threading.Thread(target=self._loop.run, daemon=True)
        self._loop_thread.start()

    def close(self) -> None:
        try:
            self.adapter.StopDiscovery()
        except Exception:
            pass
        if self._device_path:
            try:
                dbus.Interface(self.bus.get_object(BLUEZ, self._device_path),
                               f"{BLUEZ}.Device1").Disconnect()
            except Exception:
                pass
        try:
            self._loop.quit()
        except Exception:
            pass

    # ── 扫描 ──────────────────────────────────────────────────────────

    def _remove_cached(self) -> None:
        """清掉 BlueZ 缓存的设备，强制下一轮收到新鲜 AD（AGENTS.md #18）。"""
        for path, ifaces in self.om.GetManagedObjects().items():
            if f"{BLUEZ}.Device1" in ifaces:
                try:
                    self.adapter.RemoveDevice(path)
                except Exception:
                    pass

    def _record(self, props) -> None:
        if self._device_path is not None:
            return
        uuids = [str(u).lower() for u in props.get("ServiceUUIDs", [])]
        name = str(props.get("Name", "")) if "Name" in props else ""
        if SERVICE_UUID in uuids:
            self.matched_by = "service-uuid"
        elif name.startswith(DEVICE_NAME_PREFIX):
            self.matched_by = "device-name"
        else:
            return
        self._addr = str(props.get("Address", "")) or None

    def _on_interfaces_added(self, path, ifaces) -> None:
        props = ifaces.get(f"{BLUEZ}.Device1")
        if not props:
            return
        self._record(props)
        if self._device_path is None and self._addr:
            self._device_path = path
            self._scan_hit.set()

    def _on_props_changed(self, interface, changed, invalidated, path=None) -> None:
        if interface != f"{BLUEZ}.Device1":
            return
        self._record(changed)
        if self._device_path is None and self._addr:
            self._device_path = path
            self._scan_hit.set()

    def scan(self, timeout: float = 25.0) -> str:
        """扫描直到发现 Open Ledger App（按 service UUID 匹配），返回地址。"""
        self._remove_cached()
        self._scan_hit.clear()
        self.bus.add_signal_receiver(
            self._on_interfaces_added,
            dbus_interface="org.freedesktop.DBus.ObjectManager",
            signal_name="InterfacesAdded")
        self.bus.add_signal_receiver(
            self._on_props_changed,
            dbus_interface="org.freedesktop.DBus.Properties",
            signal_name="PropertiesChanged",
            arg0=f"{BLUEZ}.Device1", path_keyword="path")
        try:
            self.adapter.StopDiscovery()
        except Exception:
            pass
        self.adapter.SetDiscoveryFilter(
            {"Transport": "le", "DuplicateData": dbus.Boolean(True)})
        self.adapter.StartDiscovery()
        found = self._scan_hit.wait(timeout)
        try:
            self.adapter.StopDiscovery()
        except Exception:
            pass
        if not found or not self._device_path:
            raise BleError("扫描未发现 Open Ledger App 外设（service UUID 未出现在 AD 中）")
        return self._addr or ""

    # ── 连接 / 解析特征 ───────────────────────────────────────────────

    def connect(self, timeout: float = 25.0) -> None:
        if not self._device_path:
            raise BleError("尚未发现设备，先调用 scan()")
        props = dbus.Interface(self.bus.get_object(BLUEZ, self._device_path),
                               "org.freedesktop.DBus.Properties")
        dbus.Interface(self.bus.get_object(BLUEZ, self._device_path),
                       f"{BLUEZ}.Device1").Connect()
        deadline = time.time() + timeout
        while time.time() < deadline:
            if bool(props.Get(f"{BLUEZ}.Device1", "ServicesResolved")):
                break
            time.sleep(0.2)
        else:
            raise BleError("ServicesResolved 超时（连接后 GATT 未就绪）")
        self._resolve_chars()

    def _resolve_chars(self) -> None:
        objs = self.om.GetManagedObjects()
        svc_path = None
        for path, ifaces in objs.items():
            svc = ifaces.get(f"{BLUEZ}.GattService1")
            if svc and str(svc.get("UUID", "")).lower() == SERVICE_UUID:
                svc_path = path
        if not svc_path:
            raise BleError("未找到 Open Ledger App GATT service")
        for path, ifaces in objs.items():
            ch = ifaces.get(f"{BLUEZ}.GattCharacteristic1")
            if not ch or not path.startswith(svc_path):
                continue
            u = str(ch.get("UUID", "")).lower()
            if u == RESP_CHAR_UUID:
                self._resp_char = path
            elif u in (CMD_CHAR_UUID, CMD_WWR_UUID):
                self._cmd_char = path
        if not self._resp_char or not self._cmd_char:
            raise BleError(f"特征解析失败 resp={self._resp_char} cmd={self._cmd_char}")

    # ── 通知 ──────────────────────────────────────────────────────────

    def _on_notify(self, interface, changed, invalidated, path=None) -> None:
        if interface != f"{BLUEZ}.GattCharacteristic1" or path != self._resp_char:
            return
        if "Value" not in changed:
            return
        chunk = bytes(bytearray(changed["Value"]))
        self._notify_chunks.append(chunk)
        done = self._reasm.feed(chunk)
        if done is not None:
            self._rx = done
            self._rx_event.set()

    def start_notify(self) -> None:
        # PropertiesChanged 的**信号接口**是 org.freedesktop.DBus.Properties，
        # 目标接口（GattCharacteristic1）在 arg0——按 GattCharacteristic1 过滤
        # 永远收不到通知（与 scan() 里 Device1 的用法一致）。
        self.bus.add_signal_receiver(
            self._on_notify,
            dbus_interface="org.freedesktop.DBus.Properties",
            signal_name="PropertiesChanged",
            arg0=f"{BLUEZ}.GattCharacteristic1",
            path=self._resp_char,
            path_keyword="path")
        dbus.Interface(self.bus.get_object(BLUEZ, self._resp_char),
                       f"{BLUEZ}.GattCharacteristic1").StartNotify()

    # ── 写 ────────────────────────────────────────────────────────────

    def _write_chunk(self, data: bytes) -> None:
        ch = dbus.Interface(self.bus.get_object(BLUEZ, self._cmd_char),
                            f"{BLUEZ}.GattCharacteristic1")
        ch.WriteValue(dbus.ByteArray(bytes(data)), {"type": dbus.String("request")})

    def send_raw(self, data: bytes, mtu: int | None = None) -> None:
        """把一段字节按 tag-first 分块写下去（APDU 或 GET_MTU 请求）。"""
        for chunk in fragment(data, mtu or self.mtu):
            self._write_chunk(chunk)

    # ── 读响应 ────────────────────────────────────────────────────────

    def prepare_recv(self) -> None:
        """开始一次新的请求/响应：清空上一轮的响应状态。"""
        self._rx = None
        self._reasm = _Reassembler()
        self._notify_chunks.clear()
        self._rx_event.clear()

    def recv(self, timeout: float = 15.0) -> bytes:
        """等待并消费一个完整响应（消费后再等则等下一份）。"""
        if not self._rx_event.wait(timeout):
            raise BleError(f"等待响应超时（{timeout}s）")
        value = self._rx or b""
        self._rx = None
        self._rx_event.clear()
        return value

    def exchange(self, apdu: bytes, timeout: float = 15.0) -> bytes:
        """发一条 APDU，等一个完整响应，返回 `data + SW1SW2`。"""
        self.prepare_recv()
        self.send_raw(apdu)
        return self.recv(timeout)

    def get_mtu(self, timeout: float = 5.0) -> int:
        """向设备查一次 MTU（tag 0x08）。回复 payload 即 2 字节大端 MTU。"""
        self.prepare_recv()
        self._write_chunk(bytes([TAG_GET_MTU]))
        if not self._rx_event.wait(timeout):
            return self.mtu
        raw = self._rx or b""
        if len(raw) == 2:
            self.device_mtu = (raw[0] << 8) | raw[1]
        return self.device_mtu

    # 出站分块固定用保守 MTU（默认 20）——设备按 seq 重组，不依赖我方块大小；
    # 用保守值可避免超出 ATT MTU 的高风险大写入。
    def send(self, apdu: bytes) -> None:
        self.prepare_recv()
        self.send_raw(apdu)
