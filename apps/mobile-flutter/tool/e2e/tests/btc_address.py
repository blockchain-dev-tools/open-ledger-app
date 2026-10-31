#!/usr/bin/env python3
"""E2E：Bitcoin 四种地址类型（`E1 40 GET_WALLET_PUBLIC_KEY`）。

`E1 40` 是本仓扩展（legacy 编号落在现行 App 的 CLA 上），真实主机不会发它；
这里只验证地址派生与编码：P2=0/1/2/4 分别对应 legacy / p2sh / p2wpkh / p2tr，
结果与独立实现（`js/btcverify.mjs` + Python 编码）逐字节比对。

签名走官方 `E1 04 SIGN_PSBT`，见 `tests/btc_psbt.py` 与 `tests/btc_regtest.py`。
"""
from __future__ import annotations

import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harness import apdu, btcsig  # noqa: E402
from harness.apdu import SW_SUCCESS, parse_response  # noqa: E402
from harness.device import TEST_MNEMONIC  # noqa: E402
from harness.session import DeviceSession  # noqa: E402

# (P2 地址格式, 路径, 前缀) —— 与官方 app-bitcoin 的 `P2_ADDR_FORMAT_*` 一致。
ADDRESS_CASES = [
    (btcsig.P2_LEGACY, "m/44'/0'/0'/0/0", "1"),
    (btcsig.P2_P2SH, "m/49'/0'/0'/0/0", "3"),
    (btcsig.P2_BECH32, "m/84'/0'/0'/0/0", "bc1q"),
    (btcsig.P2_BECH32M, "m/86'/0'/0'/0/0", "bc1p"),
]


async def run() -> int:
    async with DeviceSession.start(fresh=True, chain_id="ethereum") as sess:
        with sess.ble_connected() as ble:
            print(f"BLE 已连接，设备 MTU={ble.get_mtu()}")

            data, sw = parse_response(ble.exchange(apdu.open_app("Bitcoin")))
            if sw != SW_SUCCESS:
                print(f"[FAIL] OPEN_APP(Bitcoin) SW={sw:04x}")
                return 1

            for p2, path, prefix in ADDRESS_CASES:
                expected, _pubkey = btcsig.address(TEST_MNEMONIC, path, p2)
                data, sw = parse_response(
                    ble.exchange(
                        apdu.btc_get_public_key(path, address_format=p2)
                    )
                )
                if sw != SW_SUCCESS:
                    print(f"[FAIL] GET_WALLET_PUBLIC_KEY P2={p2:#04x} SW={sw:04x}")
                    return 1
                address = data.decode("ascii", errors="replace")
                print(f"  P2={p2:#04x} {path}: {address}")
                if not address.startswith(prefix):
                    print(f"[FAIL] 前缀不是 {prefix}: {address}")
                    return 1
                if address != expected:
                    print(f"[FAIL] 地址不匹配：设备 {address} vs 独立 {expected}")
                    return 1
            print("  ✓ 四种地址类型与独立实现全部一致")

    print("[OK] btc_address 通过")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
