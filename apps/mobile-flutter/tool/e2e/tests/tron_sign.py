#!/usr/bin/env python3
"""E2E：Tron 协议全覆盖（T-021 / T-022 / T-023）——真机 + BLE host。

覆盖：
  1. `E0 02` P1=1 地址确认页 → 批准后回公钥 + 地址；
  2. `E0 05 SIGN_TXN_HASH`：sha256 摘要直签，`v` 必须是 0/1；
  3. `E0 04 SIGN` 单块（P1=0x10）：raw Transaction protobuf，设备自己 sha256；
  4. `E0 04 SIGN` 分块（P1=0x00 → 0x90）；
  5. `E0 08 SIGN_PERSONAL_MESSAGE`：TRON 前缀 + keccak256；
  6. `E0 04` TRC-10 代币名分片（0x00 → 0x80 → 0xA8）+ `permission_id`；
  7. 未知合约类型（WitnessCreateContract）→ 通用审阅 + 风险提示，仍可签名；
  8. 权限变更类型 → `[HIGH RISK]`；
  9. `E0 0A GET_ECDH_SECRET`：65B 未压缩共享点；
 10. `E0 0C SIGN_TIP_712_MESSAGE`：`keccak256(0x19 0x01 || domain || message)`。

所有签名/共享点都用 `js/ethverify.mjs`（@noble）独立复算，与设备 Rust 实现无关。
"""
from __future__ import annotations

import asyncio
import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harness import apdu, base58x, ethsig  # noqa: E402
from harness.apdu import SW_SUCCESS, parse_response  # noqa: E402
from harness.device import TEST_MNEMONIC  # noqa: E402
from harness.session import DeviceSession  # noqa: E402


# ── protobuf 构造 ────────────────────────────────────────────────────

def varint(value: int) -> bytes:
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def tag(field: int, wire: int) -> bytes:
    return varint((field << 3) | wire)


def len_field(field: int, payload: bytes) -> bytes:
    return tag(field, 2) + varint(len(payload)) + payload


def varint_field(field: int, value: int) -> bytes:
    return tag(field, 0) + varint(value)


def tron_addr(byte: int) -> bytes:
    return b"\x41" + bytes([byte]) * 20


def transaction(
    contract_type: int,
    type_name: str,
    value: bytes,
    fee_limit: int = 10_000_000,
    permission: int | None = None,
) -> bytes:
    any_param = (
        len_field(1, f"type.googleapis.com/protocol.{type_name}".encode())
        + len_field(2, value)
    )
    contract = varint_field(1, contract_type) + len_field(2, any_param)
    if permission is not None:
        contract += varint_field(5, permission)
    raw = len_field(11, contract) + varint_field(18, fee_limit)
    return len_field(1, raw)


def transfer_tx(amount: int) -> bytes:
    value = (
        len_field(1, tron_addr(0x01))
        + len_field(2, tron_addr(0x02))
        + varint_field(3, amount)
    )
    return transaction(1, "TransferContract", value)


def transfer_asset_tx(name: str, amount: int, permission: int | None = None) -> bytes:
    """TRC-10 `TransferAssetContract`：asset_name(1) / owner(2) / to(3) / amount(4)。"""
    value = (
        len_field(1, name.encode())
        + len_field(2, tron_addr(0x01))
        + len_field(3, tron_addr(0x04))
        + varint_field(4, amount)
    )
    return transaction(2, "TransferAssetContract", value, permission=permission)


def unknown_contract_tx() -> bytes:
    value = len_field(1, tron_addr(0x01))
    return transaction(5, "WitnessCreateContract", value)


def permission_update_tx() -> bytes:
    value = len_field(1, tron_addr(0x01)) + varint_field(2, 2)
    return transaction(46, "AccountPermissionUpdateContract", value)


# ── 断言辅助 ─────────────────────────────────────────────────────────

async def approve_and_receive(sess, ble, timeout: float = 20.0) -> bytes:
    screens = await sess.app.wait_for_screen({"TransactionScreen"}, timeout=10)
    if "TransactionScreen" not in screens:
        raise AssertionError(f"未弹出签名确认页：{screens}")
    await sess.app.settle(0.8)
    hit = await sess.app.tap_key("sign-approve")
    if not hit.startswith("TAPPED"):
        raise AssertionError(f"点不到 Approve：{hit!r}")
    data, sw = parse_response(ble.recv(timeout=timeout))
    if sw != SW_SUCCESS:
        raise AssertionError(f"签名响应 SW={sw:04x}")
    return data


async def run() -> int:
    eth_addr, expected_pub = ethsig.derive_address(TEST_MNEMONIC, apdu.TRON_PATH)
    expected_addr = base58x.encode_check(b"\x41" + bytes.fromhex(eth_addr[2:]))
    print(f"独立派生 Tron 地址: {expected_addr}")

    async with DeviceSession.start(fresh=True, chain_id="ethereum") as sess:
        with sess.ble_connected() as ble:
            print(f"BLE 已连接，设备 MTU={ble.get_mtu()}")

            data, sw = parse_response(ble.exchange(apdu.open_app("Tron")))
            if sw != SW_SUCCESS:
                print(f"[FAIL] OPEN_APP(Tron) SW={sw:04x}")
                return 1

            # ── 0x02 P1=1 地址确认 ───────────────────────────────────
            ble.send(apdu.apdu(apdu.CLA_OS, 0x02, 0x01, 0x00,
                               apdu.encode_path(apdu.TRON_PATH)))
            screens = await sess.app.wait_for_screen({"AddressConfirmScreen"}, timeout=10)
            if "AddressConfirmScreen" not in screens:
                print(f"[FAIL] P1=1 应弹出地址确认页：{screens}")
                return 1
            await sess.app.settle(0.5)
            # 地址本身用 RichText 分片渲染，harness 读不到；用派生路径证明展示的是本请求。
            if not await sess.app.has_text("m/44'/195'/0'/0/0"):
                print("[FAIL] 地址确认页未展示 Tron 派生路径")
                return 1
            hit = await sess.app.tap_key("address-confirm-approve")
            if not hit.startswith("TAPPED"):
                print(f"[FAIL] 点不到地址确认：{hit!r}")
                return 1
            data, sw = parse_response(ble.recv(timeout=20))
            if sw != SW_SUCCESS:
                print(f"[FAIL] 地址确认响应 SW={sw:04x}")
                return 1
            pub_len = data[0]
            pub = data[1:1 + pub_len]
            addr_len = data[1 + pub_len]
            address = data[2 + pub_len:2 + pub_len + addr_len].decode("ascii")
            if pub != expected_pub or address != expected_addr:
                print("[FAIL] 地址确认返回的公钥/地址不匹配")
                return 1
            print("  ✓ 0x02 P1=1 地址确认：页面展示正确，批准后回公钥+地址")

            # ── 0x05 SIGN_TXN_HASH ───────────────────────────────────
            digest = hashlib.sha256(b"tron e2e digest").digest()
            payload = apdu.encode_path(apdu.TRON_PATH) + digest
            ble.send(apdu.apdu(apdu.CLA_OS, 0x05, 0x00, 0x00, payload))
            data = await approve_and_receive(sess, ble)
            r, s = data[:32], data[32:64]
            v = data[64]
            if v not in (0, 1):
                print(f"[FAIL] 0x05 v 必须是 0/1，实际 {v}")
                return 1
            if ethsig.recover_address("digest", digest, v, r, s) != eth_addr:
                print("[FAIL] 0x05 签名恢复出的地址不匹配")
                return 1
            print("  ✓ 0x05 摘要直签，v=0/1，独立恢复一致")

            # ── 0x04 单块（P1=0x10）──────────────────────────────────
            raw = transfer_tx(1_500_000)
            ble.send(apdu.apdu(apdu.CLA_OS, 0x04, 0x10, 0x00,
                               apdu.encode_path(apdu.TRON_PATH) + raw))
            data = await approve_and_receive(sess, ble)
            if data[64] not in (0, 1):
                print(f"[FAIL] 0x04 v 必须是 0/1，实际 {data[64]}")
                return 1
            if ethsig.recover_address("digest", hashlib.sha256(raw).digest(),
                                      data[64], data[:32], data[32:64]) != eth_addr:
                print("[FAIL] 0x04 单块签名恢复出的地址不匹配")
                return 1
            print("  ✓ 0x04 单块：TransferContract + sha256(raw) 独立恢复一致")

            # ── 0x04 分块（P1=0x00 → 0x90）───────────────────────────
            split = len(raw) // 2 + 1
            first = apdu.encode_path(apdu.TRON_PATH) + raw[:split]
            data, sw = parse_response(ble.exchange(
                apdu.apdu(apdu.CLA_OS, 0x04, 0x00, 0x00, first)))
            if sw != SW_SUCCESS:
                print(f"[FAIL] 0x04 首块 SW={sw:04x}")
                return 1
            ble.send(apdu.apdu(apdu.CLA_OS, 0x04, 0x90, 0x00, raw[split:]))
            data = await approve_and_receive(sess, ble)
            if ethsig.recover_address("digest", hashlib.sha256(raw).digest(),
                                      data[64], data[:32], data[32:64]) != eth_addr:
                print("[FAIL] 0x04 分块签名恢复出的地址不匹配")
                return 1
            print("  ✓ 0x04 分块：两帧拼出的交易与单块签名一致")

            # ── 0x08 SIGN_PERSONAL_MESSAGE ───────────────────────────
            message = b"hello tron e2e"
            payload = (
                apdu.encode_path(apdu.TRON_PATH)
                + len(message).to_bytes(4, "big")
                + message
            )
            ble.send(apdu.apdu(apdu.CLA_OS, 0x08, 0x00, 0x00, payload))
            data = await approve_and_receive(sess, ble)
            preimage = b"\x19TRON Signed Message:\n" + str(len(message)).encode() + message
            if ethsig.recover_address("raw", preimage,
                                      data[64], data[:32], data[32:64]) != eth_addr:
                print("[FAIL] 0x08 个人消息签名恢复出的地址不匹配")
                return 1
            print("  ✓ 0x08 个人消息：TRON 前缀 + keccak256 独立恢复一致")

            # ── TRC-10 代币名分片 + permission_id ───────────────────
            asset = transfer_asset_tx("USDT10", 5_000_000, permission=2)
            split = len(asset) // 2 + 1
            first = apdu.encode_path(apdu.TRON_PATH) + asset[:split]
            data, sw = parse_response(ble.exchange(
                apdu.apdu(apdu.CLA_OS, 0x04, 0x00, 0x00, first)))
            if sw != SW_SUCCESS:
                print(f"[FAIL] TRC-10 首块 SW={sw:04x}")
                return 1
            # tx 本体最后一帧是 0x80（不是 0x90），之后才是代币名分片。
            data, sw = parse_response(ble.exchange(
                apdu.apdu(apdu.CLA_OS, 0x04, 0x80, 0x00, asset[split:])))
            if sw != SW_SUCCESS:
                print(f"[FAIL] TRC-10 续块 SW={sw:04x}")
                return 1
            ble.send(apdu.apdu(apdu.CLA_OS, 0x04, 0xA8, 0x00, b"USDT10"))
            screens = await sess.app.wait_for_screen({"TransactionScreen"}, timeout=10)
            if "TransactionScreen" not in screens:
                print(f"[FAIL] TRC-10 未弹页：{screens}")
                return 1
            await sess.app.settle(0.8)
            for needle in ("TransferAssetContract", "Asset: USDT10",
                           "Amount: 5000000", "Permission: P2"):
                if not await sess.app.has_text(needle):
                    print(f"[FAIL] TRC-10 审阅缺少 {needle!r}")
                    return 1
            hit = await sess.app.tap_key("sign-approve")
            if not hit.startswith("TAPPED"):
                print(f"[FAIL] 点不到 Approve：{hit!r}")
                return 1
            data, sw = parse_response(ble.recv(timeout=20))
            if sw != SW_SUCCESS:
                print(f"[FAIL] TRC-10 签名 SW={sw:04x}")
                return 1
            if ethsig.recover_address("digest", hashlib.sha256(asset).digest(),
                                      data[64], data[:32], data[32:64]) != eth_addr:
                print("[FAIL] TRC-10 签名恢复出的地址不匹配")
                return 1
            print("  ✓ 0x04 TRC-10：代币名分片后签名，展示 Asset/Permission")

            # ── 未知合约：通用审阅 + 风险提示，仍可签名（T-022）─────
            unknown = unknown_contract_tx()
            ble.send(apdu.apdu(apdu.CLA_OS, 0x04, 0x10, 0x00,
                               apdu.encode_path(apdu.TRON_PATH) + unknown))
            screens = await sess.app.wait_for_screen({"TransactionScreen"}, timeout=10)
            if "TransactionScreen" not in screens:
                print(f"[FAIL] 未知合约应弹出通用审阅页：{screens}")
                return 1
            await sess.app.settle(0.8)
            if not await sess.app.has_text("WitnessCreateContract"):
                print("[FAIL] 通用审阅缺少合约类型")
                return 1
            if not await sess.app.has_text("Unverified contract type"):
                print("[FAIL] 通用审阅缺少风险提示")
                return 1
            hit = await sess.app.tap_key("sign-approve")
            if not hit.startswith("TAPPED"):
                print(f"[FAIL] 点不到 Approve：{hit!r}")
                return 1
            data, sw = parse_response(ble.recv(timeout=20))
            if sw != SW_SUCCESS:
                print(f"[FAIL] 未知合约签名 SW={sw:04x}")
                return 1
            if ethsig.recover_address("digest", hashlib.sha256(unknown).digest(),
                                      data[64], data[:32], data[32:64]) != eth_addr:
                print("[FAIL] 未知合约签名恢复出的地址不匹配")
                return 1
            print("  ✓ 未知合约走通用审阅 + 风险提示，签名可独立恢复")

            # ── 高风险类型：Critical 提示 ───────────────────────────
            critical = permission_update_tx()
            ble.send(apdu.apdu(apdu.CLA_OS, 0x04, 0x10, 0x00,
                               apdu.encode_path(apdu.TRON_PATH) + critical))
            screens = await sess.app.wait_for_screen({"TransactionScreen"}, timeout=10)
            if "TransactionScreen" not in screens:
                print(f"[FAIL] 权限变更交易未弹页：{screens}")
                return 1
            await sess.app.settle(0.8)
            if not await sess.app.has_text("AccountPermissionUpdateContract"):
                print("[FAIL] 未展示合约类型")
                return 1
            if not await sess.app.has_text("[HIGH RISK]"):
                print("[FAIL] 未展示 Critical 风险")
                return 1
            await sess.app.tap_key("sign-approve")
            data, sw = parse_response(ble.recv(timeout=20))
            if sw != SW_SUCCESS:
                print(f"[FAIL] 权限变更签名 SW={sw:04x}")
                return 1
            print("  ✓ 权限变更类型展示 [HIGH RISK] 并可签名")

            # ── 0x0A GET_ECDH_SECRET ─────────────────────────────────
            # 对端公钥取自同一助记词的另一条 ETH 路径，独立计算共享点。
            _, peer_public = ethsig.derive_address(TEST_MNEMONIC, "m/44'/60'/0'/0/5")
            payload = apdu.encode_path(apdu.TRON_PATH) + peer_public
            data, sw = parse_response(ble.exchange(
                apdu.apdu(apdu.CLA_OS, 0x0A, 0x00, 0x01, payload)))
            if sw != SW_SUCCESS:
                print(f"[FAIL] 0x0A ECDH SW={sw:04x}")
                return 1
            if len(data) != 65 or data[0] != 0x04:
                print(f"[FAIL] 0x0A 应回 65B 未压缩点，实际 {data.hex()}")
                return 1
            expected_shared = ethsig.ecdh_shared(TEST_MNEMONIC, apdu.TRON_PATH, peer_public)
            if data != expected_shared:
                print("[FAIL] 0x0A 共享点与独立计算不一致")
                return 1
            print("  ✓ 0x0A ECDH：65B 共享点与独立点乘一致")

            # ── 0x0C SIGN_TIP_712_MESSAGE ────────────────────────────
            domain = hashlib.sha256(b"tron e2e domain").digest()
            struct_hash = hashlib.sha256(b"tron e2e message").digest()
            payload = apdu.encode_path(apdu.TRON_PATH) + domain + struct_hash
            ble.send(apdu.apdu(apdu.CLA_OS, 0x0C, 0x00, 0x00, payload))
            screens = await sess.app.wait_for_screen({"TransactionScreen"}, timeout=10)
            if "TransactionScreen" not in screens:
                print(f"[FAIL] TIP-712 未弹页：{screens}")
                return 1
            await sess.app.settle(0.8)
            if not await sess.app.has_text("Blind signing"):
                print("[FAIL] TIP-712 缺少盲签风险提示")
                return 1
            if not await sess.app.has_text(domain.hex()):
                print("[FAIL] TIP-712 未展示 domain hash")
                return 1
            await sess.app.tap_key("sign-approve")
            data, sw = parse_response(ble.recv(timeout=20))
            if sw != SW_SUCCESS:
                print(f"[FAIL] TIP-712 签名 SW={sw:04x}")
                return 1
            digest = ethsig.tip712_digest(domain, struct_hash)
            if ethsig.recover_address("digest", digest,
                                      data[64], data[:32], data[32:64]) != eth_addr:
                print("[FAIL] TIP-712 签名恢复出的地址不匹配")
                return 1
            print("  ✓ 0x0C TIP-712：0x1901 域分隔摘要独立恢复一致")

    print("[OK] tron_sign 通过")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
