#!/usr/bin/env python3
"""E2E：BTC 在本机 regtest 真链上的端到端验证（T-027 / T-028 / ADR-020）。

判定标准是**交易被节点接受并进块**，不是 host 自己验签：

  T1  regtest 地址与独立派生一致，且 Core 认为它是本网络地址
  T2  单输入花费：`E1 04 SIGN_PSBT` 多轮交互 → 审批 → YIELD → 上链
  T3  双输入花费：一次审批两个 YIELD，两个 witness 都有效
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
import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harness import apdu, btc_rpc, btcsig, psbt_host  # noqa: E402
from harness.apdu import SW_SUCCESS, parse_response  # noqa: E402
from harness.btc_sighash import sighash_p2wpkh  # noqa: E402
from harness.btc_tx import (  # noqa: E402
    Tx,
    TxIn,
    TxOut,
    btc_to_satoshi,
    p2pkh_script_code,
    p2wpkh_script,
)
from harness.device import TEST_MNEMONIC  # noqa: E402
from harness.session import DeviceSession  # noqa: E402

SW_USER_REJECTED = 0x6985
SW_TIMEOUT = 0x6400
SW_WRONG_P1_P2 = 0x6A86
SW_WRONG_DATA = 0x6A80

ACCOUNT_PATH = "m/84'/1'/0'"
REG_PATH = f"{ACCOUNT_PATH}/0/0"
TEMPLATE = "wpkh(@0/**)"
FEE = 2000
# 确认页倒计时 60s；留一点余量。
TIMEOUT_WAIT_SECONDS = 75


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def hash160(pubkey: bytes) -> bytes:
    return hashlib.new("ripemd160", hashlib.sha256(pubkey).digest()).digest()


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


async def sign_spend(
    sess,
    ble,
    utxos: list[tuple[str, int, int]],
    destination: str,
    receive_script: bytes,
    receive_pubkey: bytes,
    *,
    decision: str = "approve",
    timeout_wait: float = 0.0,
) -> tuple[Tx, psbt_host.PsbtHost, int]:
    """把「花掉这些 UTXO」写成 PSBT 并走完设备交互，返回 (交易骨架, host, SW)。"""
    total = sum(value for _, _, value in utxos)
    tx = Tx(
        inputs=[TxIn(txid, vout, sequence=0xFFFFFFFD) for txid, vout, _ in utxos],
        outputs=[TxOut(total - FEE, script_pubkey(destination))],
    )
    key_info, _ = btcsig.account(TEST_MNEMONIC, ACCOUNT_PATH, network="testnet")
    host = psbt_host.PsbtHost()
    header = psbt_host.build_psbt(
        host,
        template=TEMPLATE,
        key_info=key_info,
        tx=tx,
        prevouts=[(value, receive_script) for _, _, value in utxos],
        input_paths={index: (REG_PATH, receive_pubkey) for index in range(len(utxos))},
        output_paths={},
    )
    _, _, sw = await psbt_host.sign_with_device(
        sess, ble, host, header,
        decision=decision,
        timeout_wait=timeout_wait,
    )
    return tx, host, sw


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

    expected_regtest, receive_pubkey = btcsig.address(
        TEST_MNEMONIC, REG_PATH, 0x02, hrp="bcrt"
    )
    receive_script = p2wpkh_script(hash160(receive_pubkey))
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
            expect(receive_script == bytes.fromhex(info["scriptPubKey"]),
                   "独立派生的 scriptPubKey 与 Core 不一致")
            print("  ✓ T1 设备地址与独立派生逐字节一致，Core 认可为 regtest 地址")

            # ── T2 单输入花费上链（PSBT）────────────────────────────
            utxo = fund(regtest, 1.0)
            print(f"  资助 {utxo[2]} sat：{utxo[0][:16]}…:{utxo[1]}")
            spend, host, sw = await sign_spend(
                sess, ble, [utxo],
                btc_rpc.call("getnewaddress", "", "bech32", wallet="miner"),
                receive_script, receive_pubkey,
            )
            expect(sw == SW_SUCCESS, f"PSBT 签名 SW=0x{sw:04x}")
            expect(len(host.yields) == 1, f"YIELD 数量 {len(host.yields)} ≠ 1")
            index, pubkey, signature = psbt_host.parse_yield(host.yields[0])
            expect(index == 0 and pubkey == receive_pubkey, "YIELD 与输入不匹配")
            digest = sighash_p2wpkh(
                spend, 0, p2pkh_script_code(hash160(pubkey)), utxo[2])
            expect(btcsig.verify_ecdsa(pubkey, digest, signature[:-1]),
                   "签名对独立 BIP-143 摘要验签失败")
            spend.inputs[0].witness = [signature, pubkey]
            spent_txid = broadcast_and_mine(spend)
            expect(
                btc_rpc.call("gettxout", utxo[0], utxo[1]) is None,
                "资助输出仍未被花费，交易没有真正生效",
            )
            print(f"  ✓ T2 单输入交易进块：{spent_txid[:16]}…，UTXO 已花费")

            # ── T3 双输入花费 ───────────────────────────────────────
            first = fund(regtest, 0.4)
            second = fund(regtest, 0.6)
            multi, host, sw = await sign_spend(
                sess, ble, [first, second],
                btc_rpc.call("getnewaddress", "", "bech32", wallet="miner"),
                receive_script, receive_pubkey,
            )
            expect(sw == SW_SUCCESS, f"双输入 PSBT SW=0x{sw:04x}")
            expect(len(host.yields) == 2, f"YIELD 数量 {len(host.yields)} ≠ 2")
            values = [first[2], second[2]]
            for payload in host.yields:
                index, pubkey, signature = psbt_host.parse_yield(payload)
                expect(pubkey == receive_pubkey, "双输入 YIELD 公钥不一致")
                digest = sighash_p2wpkh(
                    multi, index, p2pkh_script_code(hash160(pubkey)), values[index])
                expect(btcsig.verify_ecdsa(pubkey, digest, signature[:-1]),
                       f"输入 {index} 的签名验签失败")
                multi.inputs[index].witness = [signature, pubkey]
            multi_txid = broadcast_and_mine(multi)
            expect(
                btc_rpc.call("gettxout", first[0], first[1]) is None
                and btc_rpc.call("gettxout", second[0], second[1]) is None,
                "双输入交易的资助输出仍存在",
            )
            print(f"  ✓ T3 双输入交易进块：{multi_txid[:16]}…，两个 UTXO 均已花费")

            # ── T4 拒绝不产出签名 ───────────────────────────────────
            reject_funding = fund(regtest, 0.5)
            _, host, sw = await sign_spend(
                sess, ble, [reject_funding],
                btc_rpc.call("getnewaddress", "", "bech32", wallet="miner"),
                receive_script, receive_pubkey,
                decision="reject",
            )
            expect(sw == SW_USER_REJECTED, f"拒绝后 SW=0x{sw:04x}")
            expect(not host.yields, f"拒绝后不应有 YIELD：{host.yields}")
            expect(btc_rpc.call("gettxout", reject_funding[0], reject_funding[1]),
                   "拒绝后不应花费该 UTXO")
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
                _, host, sw = await sign_spend(
                    sess, ble, [timeout_funding],
                    btc_rpc.call("getnewaddress", "", "bech32", wallet="miner"),
                    receive_script, receive_pubkey,
                    decision="timeout",
                    timeout_wait=TIMEOUT_WAIT_SECONDS,
                )
                expect(sw in (SW_USER_REJECTED, SW_TIMEOUT),
                       f"超时后 SW=0x{sw:04x}")
                expect(not host.yields, "超时后不应有 YIELD")
                expect(btc_rpc.call("gettxout", timeout_funding[0], timeout_funding[1]),
                       "超时后不应花费该 UTXO")
                print(f"  ✓ T5 超时返回 0x{sw:04x}，无签名")

    print("\n[OK] btc_regtest 通过")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
