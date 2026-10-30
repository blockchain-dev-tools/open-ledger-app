#!/usr/bin/env python3
"""E2E：Bitcoin 四种地址类型 + ECDSA / Taproot 签名。

流程：清数据建固定钱包 → OPEN_APP(Bitcoin) →
  1. `GET_WALLET_PUBLIC_KEY` 分别按 P2=0/1/2/4 取 legacy / p2sh / p2wpkh / p2tr
     地址，与 Node(`@noble`) + Python 编码的独立实现逐个比对；
  2. `m/84'` 两个 sighash 的 ECDSA 多输入签名 → 确认页 Approve → 逐个独立恢复地址；
  3. `m/86'` 一个 sighash 的 Taproot 签名 → 确认页 Approve → 用 BIP-340 独立验签。

独立实现：派生与 BIP-341 tweak 在 `js/btcverify.mjs`（@noble/@scure），地址
字符串编码在 `harness/btcaddr.py` / `harness/base58x.py`（纯标准库），与设备侧
Rust（k256 + open-ledger-crypto）是两套代码。
"""
from __future__ import annotations

import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harness import apdu, btcsig, ethsig  # noqa: E402
from harness.apdu import (  # noqa: E402
    SW_SUCCESS,
    parse_response,
    parse_signature,
)
from harness.device import TEST_MNEMONIC  # noqa: E402
from harness.session import DeviceSession  # noqa: E402

SIGHASHES = [bytes([0x11]) * 32, bytes([0x22]) * 32]

# (P2 地址格式, 路径, 前缀) —— 与官方 app-bitcoin 的 `P2_ADDR_FORMAT_*` 一致。
ADDRESS_CASES = [
    (btcsig.P2_LEGACY, "m/44'/0'/0'/0/0", "1"),
    (btcsig.P2_P2SH, "m/49'/0'/0'/0/0", "3"),
    (btcsig.P2_BECH32, "m/84'/0'/0'/0/0", "bc1q"),
    (btcsig.P2_BECH32M, "m/86'/0'/0'/0/0", "bc1p"),
]

TAPROOT_PATH = "m/86'/0'/0'/0/0"


async def run() -> int:
    btc_path_eth, _btc_pub = ethsig.derive_address(TEST_MNEMONIC, apdu.BTC_PATH)

    async with DeviceSession.start(fresh=True, chain_id="ethereum") as sess:
        with sess.ble_connected() as ble:
            print(f"BLE 已连接，设备 MTU={ble.get_mtu()}")

            data, sw = parse_response(ble.exchange(apdu.open_app("Bitcoin")))
            if sw != SW_SUCCESS:
                print(f"[FAIL] OPEN_APP(Bitcoin) SW={sw:04x}")
                return 1

            # ── 1. 四种地址类型 ──────────────────────────────────────
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

            # ── 2. ECDSA 多输入签名（m/84'）──────────────────────────
            ble.send(apdu.btc_sign(SIGHASHES))
            screens = await sess.app.wait_for_screen({"TransactionScreen"}, timeout=10)
            if "TransactionScreen" not in screens:
                print(f"[FAIL] 未弹出签名确认页：{screens}")
                return 1
            print("  ✓ 设备弹出 BTC 多输入确认页")

            # 等确认页转场结束再点，否则命中上一页的坐标系。
            await sess.app.settle(0.8)
            hit = await sess.app.tap_key("sign-approve")
            if not hit.startswith("TAPPED"):
                print(f"[FAIL] 点不到 Approve：{hit!r}")
                return 1
            data, sw = parse_response(ble.recv(timeout=20))
            if sw != SW_SUCCESS:
                print(f"[FAIL] 签名响应 SW={sw:04x}")
                return 1
            if len(data) != len(SIGHASHES) * 65:
                print(f"[FAIL] 签名长度 {len(data)}，期望 {len(SIGHASHES) * 65}")
                return 1

            for index, sighash in enumerate(SIGHASHES):
                v, r, s = parse_signature(data[index * 65:(index + 1) * 65])
                recovered = ethsig.recover_address("digest", sighash, v, r, s)
                print(f"  input {index}: v={v} r={r.hex()[:16]}… → {recovered}")
                if recovered.lower() != btc_path_eth.lower():
                    print(f"[FAIL] input {index} 恢复地址与设备私钥不一致")
                    return 1
            print(f"  ✓ {len(SIGHASHES)} 个输入的签名均可独立恢复且地址一致")

            # ── 3. Taproot 签名（m/86'，BIP-340）─────────────────────
            taproot_sighash = bytes([0x33]) * 32
            ble.send(
                apdu.btc_sign([taproot_sighash], path=TAPROOT_PATH)
            )
            screens = await sess.app.wait_for_screen({"TransactionScreen"}, timeout=10)
            if "TransactionScreen" not in screens:
                print(f"[FAIL] Taproot 未弹出签名确认页：{screens}")
                return 1
            await sess.app.settle(0.8)
            hit = await sess.app.tap_key("sign-approve")
            if not hit.startswith("TAPPED"):
                print(f"[FAIL] Taproot 点不到 Approve：{hit!r}")
                return 1
            data, sw = parse_response(ble.recv(timeout=20))
            if sw != SW_SUCCESS:
                print(f"[FAIL] Taproot 签名响应 SW={sw:04x}")
                return 1
            if len(data) != 64:
                print(f"[FAIL] Taproot 签名长度 {len(data)}，期望 64")
                return 1
            output_key = btcsig.verify_schnorr(
                TEST_MNEMONIC, TAPROOT_PATH, taproot_sighash, data
            )
            print(f"  ✓ Taproot 签名通过 BIP-340 独立验签（output key {output_key[:16]}…）")

    print("[OK] btc_sign 通过")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
