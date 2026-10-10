#!/usr/bin/env python3
"""BLE APDU Test Client — connects to Open Ledger App and sends APDU commands."""

import asyncio
import struct
import sys
from bleak import BleakScanner, BleakClient

SERVICE_UUID = "13d63400-2c97-0004-0000-4c6564676572"
WRITE_UUID = "13d63400-2c97-0004-0002-4c6564676572"
WRITE_CMD_UUID = "13d63400-2c97-0004-0003-4c6564676572"
NOTIFY_UUID = "13d63400-2c97-0004-0001-4c6564676572"

CHANNEL_HI = 0x01
CHANNEL_LO = 0x01
TAG = 0x05


def frame_apdu(apdu_bytes: bytes) -> list[bytes]:
    """Split APDU into BLE frames with Ledger channel prefix."""
    frames = []
    offset = 0
    seq = 0
    mtu = 20
    total = len(apdu_bytes)

    while offset < total:
        is_first = seq == 0
        header_len = 7 if is_first else 5
        payload_max = mtu - header_len
        remaining = total - offset
        payload_len = min(payload_max, remaining)

        frame = bytearray(header_len + payload_len)
        i = 0
        frame[i] = CHANNEL_HI; i += 1
        frame[i] = CHANNEL_LO; i += 1
        frame[i] = TAG; i += 1
        frame[i] = (seq >> 8) & 0xFF; i += 1
        frame[i] = seq & 0xFF; i += 1
        if is_first:
            frame[i] = (total >> 8) & 0xFF; i += 1
            frame[i] = total & 0xFF; i += 1

        frame[i : i + payload_len] = apdu_bytes[offset : offset + payload_len]
        frames.append(bytes(frame))

        offset += payload_len
        seq += 1

    return frames


def build_apdu(cla: int, ins: int, p1: int, p2: int, data: bytes = b"") -> bytes:
    """Build APDU bytes: CLA + INS + P1 + P2 + Lc + data."""
    lc = len(data)
    return bytes([cla, ins, p1, p2, lc]) + data


# Preset APDU commands
PRESETS = {
    "get_version": build_apdu(0xE0, 0x01, 0x00, 0x00),
    "get_app_and_version": build_apdu(0xB0, 0x01, 0x00, 0x00),
    "open_eth": build_apdu(0xE0, 0xD8, 0x00, 0x00, b"Ethereum"),
    "get_eth_addr": build_apdu(
        0xE0, 0x02, 0x00, 0x00,
        # BIP32 path: m/44'/60'/0'/0/0
        bytes([5])  # depth = 5
        + struct.pack(">I", 0x8000002C)  # 44'
        + struct.pack(">I", 0x8000003C)  # 60'
        + struct.pack(">I", 0x80000000)  # 0'
        + struct.pack(">I", 0x00000000)  # 0
        + struct.pack(">I", 0x00000000)  # 0
    ),
    "open_sol": build_apdu(0xE0, 0xD8, 0x00, 0x00, b"Solana"),
    "open_btc": build_apdu(0xE0, 0xD8, 0x00, 0x00, b"Bitcoin"),
}


def hex_str(data: bytes) -> str:
    return " ".join(f"{b:02X}" for b in data)


def parse_apdu_response(data: bytes) -> str:
    """Try to parse an APDU response and show SW + human-readable info."""
    if len(data) < 2:
        return f"too short ({len(data)} bytes)"

    sw1 = data[-2]
    sw2 = data[-1]
    sw = (sw1 << 8) | sw2
    payload = data[:-2] if len(data) > 2 else b""

    sw_names = {
        0x9000: "OK",
        0x6985: "DENY",
        0x6A80: "WRONG_DATA",
        0x6A86: "WRONG_P1P2",
        0x6D00: "INS_NOT_SUPPORTED",
        0x6E00: "CLA_NOT_SUPPORTED",
        0x6F00: "INTERNAL_ERROR",
    }
    sw_name = sw_names.get(sw, "?")

    info = f"SW=0x{sw:04X} ({sw_name})"

    if sw == 0x9000 and len(payload) > 0:
        # Try to decode as ASCII
        try:
            text = payload.decode("ascii")
            if text.isprintable() and len(text) < 100:
                info += f"  ASCII: {text}"
        except UnicodeDecodeError:
            pass

        # For ETH address response: [0x41][65B pubkey][0x28][40B addr]
        if len(payload) >= 2 and payload[0] == 0x41:
            pubkey = payload[1:66]
            addr_len = payload[66]
            addr = payload[67 : 67 + addr_len]
            info += f"\n  pubkey({len(pubkey)}B): {hex_str(pubkey[:8])}..."
            info += f"\n  addr({addr_len}B): {addr.decode('ascii', errors='replace')}"

    return info


class BleApduClient:
    def __init__(self, address: str):
        self.address = address
        self.client = BleakClient(address)
        self.response_queue: asyncio.Queue = asyncio.Queue()

    def _on_notify(self, _characteristic, data: bytearray):
        """Handle incoming notification (APDU response)."""
        print(f"\n  ◀ NOTIFY ({len(data)}B): {hex_str(bytes(data))}")
        self.response_queue.put_nowait(bytes(data))

    async def connect(self):
        await self.client.connect()
        print(f"  ✓ Connected to {self.address}")

        # Subscribe to notifications
        await self.client.start_notify(NOTIFY_UUID, self._on_notify)
        print(f"  ✓ Subscribed to notifications")

    async def disconnect(self):
        await self.client.disconnect()

    async def send_apdu(self, apdu_bytes: bytes) -> bytes | None:
        """Send APDU command and wait for response (with timeout)."""
        frames = frame_apdu(apdu_bytes)
        print(f"\n  ▶ APDU: {hex_str(apdu_bytes)}")

        # Write all frames to the Write Without Response characteristic
        for i, frame in enumerate(frames):
            await self.client.write_gatt_char(WRITE_CMD_UUID, frame, response=False)
            print(f"    frame {i}: {hex_str(frame)}")

        # Wait for response notification (timeout 5s)
        response = asyncio.Queue()
        self.response_queue = response

        try:
            data = await asyncio.wait_for(response.get(), timeout=5.0)
            print(f"  ✓ Response: {parse_apdu_response(data)}")
            return data
        except asyncio.TimeoutError:
            print("  ✗ Timeout waiting for response")
            return None

    async def send_preset(self, name: str):
        """Send a preset APDU command."""
        if name not in PRESETS:
            print(f"Unknown preset: {name}")
            print(f"Available: {', '.join(PRESETS.keys())}")
            return

        await self.send_apdu(PRESETS[name])

    async def interactive(self):
        """Interactive APDU command loop."""
        print("\nCommands:")
        for k, v in PRESETS.items():
            print(f"  {k}: {hex_str(v)}")
        print("  hex AA BB CC... : send raw hex bytes")
        print("  quit : exit")
        print()

        while True:
            try:
                cmd = input("> ").strip()
                if not cmd:
                    continue
                if cmd == "quit":
                    break
                if cmd in PRESETS:
                    await self.send_preset(cmd)
                else:
                    # Parse hex bytes
                    try:
                        parts = cmd.replace(" ", "").replace(",", "")
                        raw = bytes.fromhex(parts)
                        await self.send_apdu(raw)
                    except ValueError as e:
                        print(f"  Invalid: {e}")
            except (EOFError, KeyboardInterrupt):
                break


async def scan():
    """Scan for Open Ledger App device."""
    print("Scanning for Open Ledger App (5s)...")
    devices = await BleakScanner.discover(timeout=5.0, return_adv=True)

    target = None
    for addr, (device, adv_data) in devices.items():
        name = device.name or adv_data.local_name or "(unknown)"
        svc_uuids = adv_data.service_uuids or []
        svc_str = ",".join(str(u) for u in svc_uuids)
        print(f"  {addr}  {name}  [{svc_str}]")

        if SERVICE_UUID in svc_str:
            target = addr
            print(f"\n  ★ Found Open Ledger App: {name} ({addr})")

    return target


async def main():
    if len(sys.argv) > 1 and sys.argv[1] == "scan":
        await scan()
        return

    # Scan for device
    address = await scan()
    if not address:
        print("No Open Ledger App device found. Make sure BLE advertising is ON.")
        return

    client = BleApduClient(address)
    try:
        await client.connect()

        # Send preset commands
        print("\n─── GET_APP_AND_VERSION ───")
        await client.send_preset("get_app_and_version")

        print("\n─── GET_ETH_ADDRESS ───")
        await client.send_preset("get_eth_addr")

        # Interactive mode
        await client.interactive()

    finally:
        await client.disconnect()
        print("\nDisconnected.")


if __name__ == "__main__":
    asyncio.run(main())
