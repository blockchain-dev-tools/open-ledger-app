#!/usr/bin/env python3
"""E2E：BTC 在本机 regtest 真链上的端到端验证（T-027 / ADR-020）。

判定标准是**交易被节点接受并进块**，不是 host 自己验签：

  T1  regtest 地址与独立派生一致，且 Core 认为它是本网络地址
  T2  单输入花费：设备签名 → testmempoolaccept → sendrawtransaction → 进块
  T3  双输入花费：一次审批两个签名，两个 witness 都有效
  T4  拒绝：收到 0x6985，链上无该交易
  T5  超时：确认页倒计时结束后回终态 SW，不产出签名
  T6  非法 P2：网络位/格式位非法分别回 0x6A86 / 0x6A80
  T7  网络隔离：同一密钥在 0 / 1 / 2 三个网络下给出 bc1 / tb1 / bcrt1

前置：
    tool/e2e/regtest/up.sh          # 起本机 bitcoind（资金来自挖矿）
    flutter build apk --debug …     # harness 走 VM Service，需要 debug 包

运行：
    bash tool/e2e/run.sh btc_regtest
"""
from __future__ import annotations

import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harness import apdu, btc_rpc, btc_sig, btcsig  # noqa: E402
from harness.apdu import (  # noqa: E402
    SW_SUCCESS,
    parse_response,
)
from harness.btc_sighash import sighash_p2wpkh  # noqa: E402
from harness.btc_tx import (  # noqa: E402
    Tx,
    TxIn,
    TxOut,
    btc_to_satoshi,
    p2pkh_script_code,
)
from harness.device import TEST_MNEMONIC  # noqa: E402
from harness.session import DeviceSession  # noqa: E402

SW_USER_REJECTED = 0x6985
SW_TIMEOUT = 0x6400
SW_WRONG_P1_P2 = 0x6A86
SW_WRONG_DATA = 0x6A80

REG_PATH = "m/84'/1'/0'/0/0"
FEE = 2000
# 确认页倒计时 60s；留一点余量。
TIMEOUT_WAIT_SECONDS = 75


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def mine_blocks(count: int = 1) -> None:
    address = btc_rpc.call("getnewaddress", "", "bech32", wallet="miner")
    btc_rpc.call("generatetoaddress", count, address, wallet="miner")


def address_is_valid_here(address: str) -> bool:
    """该地址是否是本 regtest 网络的有效地址（跨网络地址 Core 会直接报错）。"""
    try:
        btc_rpc.call("getaddressinfo", address)
        return True
    except btc_rpc.RpcError:
        return False


def script_pubkey(address: str) -> bytes:
    return bytes.fromhex(btc_rpc.call("getaddressinfo", address)["scriptPubKey"])


def device_address(
    ble,
    *,
    network: int = apdu.BTC_NET_REGTEST,
    address_format: int = 0x02,
    path: str = REG_PATH,
) -> str:
    data, sw = parse_response(
        ble.exchange(
            apdu.btc_get_public_key(
                path, address_format=address_format, network=network
            )
        )
    )
    expect(sw == SW_SUCCESS, f"GET_WALLET_PUBLIC_KEY SW=0x{sw:04x}")
    return data.decode("ascii")


def fund(address: str, amount_btc: float) -> tuple[str, int, int]:
    """给地址打钱并确认，返回 (txid, vout, satoshi)。"""
    txid = btc_rpc.call("sendtoaddress", address, amount_btc, wallet="miner")
    mine_blocks()
    raw = btc_rpc.call("getrawtransaction", txid, True)
    outputs = [o for o in raw["vout"] if o["scriptPubKey"].get("address") == address]
    expect(bool(outputs), f"funding 交易里没有 {address} 的输出")
    output = outputs[0]
    return txid, output["n"], btc_to_satoshi(output["value"])


def build_spend(
    utxos: list[tuple[str, int, int]],
    destination: str,
) -> Tx:
    total = sum(value for _, _, value in utxos)
    tx = Tx(
        inputs=[TxIn(txid, vout) for txid, vout, _ in utxos],
        outputs=[TxOut(total - FEE, script_pubkey(destination))],
    )
    return tx


async def approve_signature(sess, ble, sighashes: list[bytes]) -> list[bytes]:
    """发签名请求 → 确认页 → Approve → 返回每个输入的 65B compact 签名。"""
    ble.send(
        apdu.btc_sign(sighashes, path=REG_PATH, network=apdu.BTC_NET_REGTEST)
    )
    screens = await sess.app.wait_for_screen({"TransactionScreen"}, timeout=10)
    expect("TransactionScreen" in screens, f"未弹出签名确认页：{screens}")
    await sess.app.settle(0.8)
    hit = await sess.app.tap_key("sign-approve")
    expect(hit.startswith("TAPPED"), f"点不到 Approve：{hit!r}")
    data, sw = parse_response(ble.recv(timeout=20))
    expect(sw == SW_SUCCESS, f"签名响应 SW=0x{sw:04x}")
    expect(
        len(data) == len(sighashes) * 65,
        f"签名长度 {len(data)}，期望 {len(sighashes) * 65}",
    )
    return [data[i * 65:(i + 1) * 65] for i in range(len(sighashes))]


def broadcast_and_mine(tx: Tx) -> str:
    raw = tx.serialize().hex()
    verdict = btc_rpc.call("testmempoolaccept", [raw])[0]
    expect(
        verdict.get("allowed") is True,
        f"节点拒绝该交易：{verdict.get('reject-reason')}",
    )
    txid = btc_rpc.call("sendrawtransaction", raw)
    mine_blocks()
    return txid


async def run() -> int:
    try:
        height = btc_rpc.ensure_running()
    except RuntimeError as error:
        print(f"[FAIL] {error}")
        return 1
    print(f"regtest 高度 {height}")
    try:
        btc_rpc.call("createwallet", "miner")
    except btc_rpc.RpcError:
        pass  # 已存在

    expected_regtest, pubkey = btcsig.address(
        TEST_MNEMONIC, REG_PATH, 0x02, hrp="bcrt"
    )
    print(f"独立派生 regtest 地址: {expected_regtest}")

    serial = os.environ.get("ANDROID_SERIAL") or None
    async with DeviceSession.start(
            fresh=True, chain_id="bitcoin", serial=serial) as sess:
        with sess.ble_connected() as ble:
            print(f"BLE 已连接，MTU={ble.get_mtu()}")
            data, sw = parse_response(ble.exchange(apdu.open_app("Bitcoin")))
            expect(sw == SW_SUCCESS, f"OPEN_APP(Bitcoin) SW=0x{sw:04x}")

            # ── T7 网络隔离 ─────────────────────────────────────────
            mainnet = device_address(ble, network=apdu.BTC_NET_MAINNET)
            testnet = device_address(ble, network=apdu.BTC_NET_TESTNET)
            regtest = device_address(ble, network=apdu.BTC_NET_REGTEST)
            print(f"  bc1: {mainnet[:14]}…  tb1: {testnet[:14]}…  bcrt1: {regtest[:18]}…")
            expect(mainnet.startswith("bc1q"), f"主网地址异常：{mainnet}")
            expect(testnet.startswith("tb1q"), f"testnet 地址异常：{testnet}")
            expect(regtest.startswith("bcrt1q"), f"regtest 地址异常：{regtest}")
            expect(
                not address_is_valid_here(mainnet),
                "regtest 节点不应接受主网地址（网络隔离失效）",
            )
            print("  ✓ 三个网络的地址前缀互不相同，Core 拒绝跨网络地址")

            # ── T1 地址与独立派生一致 ───────────────────────────────
            expect(regtest == expected_regtest,
                   f"设备地址 {regtest} ≠ 独立派生 {expected_regtest}")
            info = btc_rpc.call("getaddressinfo", regtest)
            expect(info.get("iswitness") is True and info.get("witness_version") == 0,
                   f"地址不是 v0 witness：{info}")
            funded_pkh = bytes.fromhex(info["scriptPubKey"])[2:]
            expect(len(funded_pkh) == 20, "scriptPubKey 长度异常")
            expect(
                funded_pkh == bytes.fromhex(info["witness_program"]),
                "witness program 与 scriptPubKey 不一致",
            )
            print("  ✓ T1 设备地址与独立派生逐字节一致，Core 认可为 regtest 地址")

            # ── T2 单输入花费上链 ───────────────────────────────────
            txid, vout, value = fund(regtest, 1.0)
            print(f"  资助 {value} sat：{txid[:16]}…:{vout}")
            spend = build_spend([(txid, vout, value)], btc_rpc.call(
                "getnewaddress", "", "bech32", wallet="miner"))
            sighash = sighash_p2wpkh(
                spend, 0, p2pkh_script_code(funded_pkh), value)
            signature = (await approve_signature(sess, ble, [sighash]))[0]
            spend.inputs[0].witness = [btc_sig.compact_to_der(signature), pubkey]
            spent_txid = broadcast_and_mine(spend)
            expect(
                btc_rpc.call("gettxout", txid, vout) is None,
                "资助输出仍未被花费，交易没有真正生效",
            )
            print(f"  ✓ T2 单输入交易进块：{spent_txid[:16]}…，UTXO 已花费")

            # ── T3 双输入花费 ───────────────────────────────────────
            first = fund(regtest, 0.4)
            second = fund(regtest, 0.6)
            multi = build_spend(
                [first, second],
                btc_rpc.call("getnewaddress", "", "bech32", wallet="miner"),
            )
            sighashes = [
                sighash_p2wpkh(multi, index, p2pkh_script_code(funded_pkh), utxo[2])
                for index, utxo in enumerate([first, second])
            ]
            signatures = await approve_signature(sess, ble, sighashes)
            for index, signature in enumerate(signatures):
                multi.inputs[index].witness = [
                    btc_sig.compact_to_der(signature), pubkey]
            multi_txid = broadcast_and_mine(multi)
            expect(
                btc_rpc.call("gettxout", first[0], first[1]) is None
                and btc_rpc.call("gettxout", second[0], second[1]) is None,
                "双输入交易的资助输出仍存在",
            )
            print(f"  ✓ T3 双输入交易进块：{multi_txid[:16]}…，两个 UTXO 均已花费")

            # ── T4 拒绝不产出签名 ───────────────────────────────────
            reject_funding = fund(regtest, 0.5)
            reject_tx = build_spend(
                [reject_funding],
                btc_rpc.call("getnewaddress", "", "bech32", wallet="miner"),
            )
            reject_sighash = sighash_p2wpkh(
                reject_tx, 0, p2pkh_script_code(funded_pkh), reject_funding[2])
            ble.send(apdu.btc_sign(
                [reject_sighash],
                path=REG_PATH,
                network=apdu.BTC_NET_REGTEST,
            ))
            screens = await sess.app.wait_for_screen(
                {"TransactionScreen"}, timeout=10)
            expect("TransactionScreen" in screens, f"未弹出确认页：{screens}")
            await sess.app.settle(0.8)
            hit = await sess.app.tap_key("sign-reject")
            expect(hit.startswith("TAPPED"), f"点不到 Reject：{hit!r}")
            data, sw = parse_response(ble.recv(timeout=15))
            expect(sw == SW_USER_REJECTED, f"拒绝后 SW=0x{sw:04x}")
            expect(not data, f"拒绝响应不应带数据：{data.hex()}")
            print("  ✓ T4 拒绝返回 0x6985，无签名")

            # ── T6 非法 P2 ──────────────────────────────────────────
            data, sw = parse_response(ble.exchange(
                apdu.btc_get_public_key(REG_PATH, address_format=0x05,
                                        network=apdu.BTC_NET_REGTEST)))
            expect(sw == SW_WRONG_DATA,
                   f"非法格式应回 0x6A80，实际 0x{sw:04x}")
            data, sw = parse_response(ble.exchange(
                apdu.btc_get_public_key(REG_PATH, address_format=0x02,
                                        network=0x40)))
            expect(sw == SW_WRONG_P1_P2,
                   f"非法网络应回 0x6A86，实际 0x{sw:04x}")
            print("  ✓ T6 非法格式 0x6A80 / 非法网络 0x6A86")

            # ── T5 超时（约 65s）───────────────────────────────────
            if os.environ.get("BTC_REGTEST_SKIP_TIMEOUT") == "1":
                print("  - T5 已按 BTC_REGTEST_SKIP_TIMEOUT 跳过")
            else:
                timeout_funding = fund(regtest, 0.3)
                timeout_tx = build_spend(
                    [timeout_funding],
                    btc_rpc.call("getnewaddress", "", "bech32", wallet="miner"),
                )
                timeout_sighash = sighash_p2wpkh(
                    timeout_tx, 0, p2pkh_script_code(funded_pkh), timeout_funding[2])
                ble.send(apdu.btc_sign(
                    [timeout_sighash],
                    path=REG_PATH,
                    network=apdu.BTC_NET_REGTEST,
                ))
                screens = await sess.app.wait_for_screen(
                    {"TransactionScreen"}, timeout=10)
                expect("TransactionScreen" in screens, f"未弹出确认页：{screens}")
                print(f"  等待 {TIMEOUT_WAIT_SECONDS}s 让确认页超时…")
                data, sw = parse_response(
                    ble.recv(timeout=TIMEOUT_WAIT_SECONDS + 10))
                expect(sw in (SW_USER_REJECTED, SW_TIMEOUT),
                       f"超时后 SW=0x{sw:04x}")
                expect(not data, f"超时响应不应带数据：{data.hex()}")
                print(f"  ✓ T5 超时返回 0x{sw:04x}，无签名")

    print("\n[OK] btc_regtest 通过")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
