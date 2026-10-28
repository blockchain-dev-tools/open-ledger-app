#!/usr/bin/env python3
"""E2E：Tron 地址与版本（阶段 4 / T-023）——真机 + BLE host。

流程：清数据建固定钱包 → 开 BLE 广播 → OPEN_APP(Tron) →
`E0 06` 配置位（allowData | allowContract | signByHash）→ `E0 02` 地址
（`[65B pub][len][ascii]`，与独立 base58check 编码比对）→ `E0 02` P2=1
附带 32B chain code → `E0 04` 空载荷回 `6A80`（签名见 tron_sign）。
"""
from __future__ import annotations

import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harness import apdu, base58x, ethsig  # noqa: E402
from harness.apdu import SW_SUCCESS, parse_response, parse_tron_address  # noqa: E402
from harness.device import TEST_MNEMONIC  # noqa: E402
from harness.session import DeviceSession  # noqa: E402


async def run() -> int:
    # ethsig 返回该私钥的 ETH 地址（keccak 后 20 字节）与 65B 公钥；
    # Tron 地址 = base58check(0x41 || 这 20 字节)，编码在 Python 侧独立完成。
    eth_addr, expected_pub = ethsig.derive_address(TEST_MNEMONIC, apdu.TRON_PATH)
    raw = b"\x41" + bytes.fromhex(eth_addr[2:])
    expected_addr = base58x.encode_check(raw)
    print(f"独立派生 Tron 地址: {expected_addr}")

    async with DeviceSession.start(fresh=True, chain_id="ethereum") as sess:
        with sess.ble_connected() as ble:
            print(f"BLE 已连接，设备 MTU={ble.get_mtu()}")

            data, sw = parse_response(ble.exchange(apdu.open_app("Tron")))
            if sw != SW_SUCCESS:
                print(f"[FAIL] OPEN_APP(Tron) SW={sw:04x}")
                return 1

            data, sw = parse_response(ble.exchange(apdu.tron_get_version()))
            if sw != SW_SUCCESS or data != bytes([0x0B, 0x00, 0x05, 0x00]):
                print(f"[FAIL] Tron CONFIG data={data.hex()} SW={sw:04x}")
                return 1
            print("  ✓ E0 06 配置位 = 0B（allowData / allowContract / signByHash）")

            data, sw = parse_response(ble.exchange(apdu.tron_get_address()))
            if sw != SW_SUCCESS:
                print(f"[FAIL] Tron GET_ADDRESS SW={sw:04x}")
                return 1
            pub, address = parse_tron_address(data)
            print(f"设备地址: {address}")
            if pub != expected_pub:
                print("[FAIL] 公钥不匹配")
                return 1
            if address != expected_addr:
                print(f"[FAIL] 地址不匹配：设备 {address} vs 独立 {expected_addr}")
                return 1
            print("  ✓ 65B 公钥与 base58check 地址均与独立派生一致")

            data, sw = parse_response(ble.exchange(apdu.apdu(
                apdu.CLA_OS, 0x02, 0x00, 0x01, apdu.encode_path(apdu.TRON_PATH))))
            if sw != SW_SUCCESS:
                print(f"[FAIL] Tron GET_ADDRESS(P2=1) SW={sw:04x}")
                return 1
            pub, address = parse_tron_address(data[:len(data) - 32])
            chain_code = data[len(data) - 32:]
            if address != expected_addr or pub != expected_pub:
                print("[FAIL] P2=1 地址/公钥不匹配")
                return 1
            if len(chain_code) != 32 or chain_code == b"\x00" * 32:
                print(f"[FAIL] chain code 异常：{chain_code.hex()}")
                return 1
            print(f"  ✓ P2=1 附带 32B chain code: {chain_code.hex()[:16]}…")

            data, sw = parse_response(ble.exchange(apdu.tron_sign_tx(b"")))
            if sw != 0x6A80:
                print(f"[FAIL] 空交易应回 6A80，实际 {sw:04x}")
                return 1
            print("  ✓ E0 04 空载荷回 6A80（签名见 tron_sign）")

    print("[OK] tron_address 通过")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
