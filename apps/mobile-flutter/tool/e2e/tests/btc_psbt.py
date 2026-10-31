#!/usr/bin/env python3
"""E2E：`E1 04 SIGN_PSBT` 在真机上的完整多轮交互（P2WPKH + P2TR）。

这是「设备真的能签出标准主机能用的签名」的验收：主机只交出 PSBTv2 的
Merkle 化摘要，设备通过 `0xE000` 反向索取每一个字段（预映像、叶子证明、
续收元素），审阅后逐个 YIELD 签名；主机再用自己算的摘要独立验签，最后把
交易广播到本机 regtest 并进块。

  T1  协议：多轮 `0xE000` 全部被正确回答，设备不依赖主机的任何「自证」
  T2  归属：YIELD 的公钥与独立派生的接收地址公钥一致
  T3  签名：P2WPKH 用 BIP-143（DER），P2TR 用 BIP-341（Schnorr，64B）独立验签
  T4  上链：拼出的交易被 `testmempoolaccept` 接受、广播后进块、UTXO 被花费
  T5  审阅：确认页的金额 / 找零 / 手续费 / 费率 / RBF / locktime / 输入数
      全部由设备自己解析 PSBT 得出

前置：
    tool/e2e/regtest/up.sh          # 本机 bitcoind（资金来自挖矿）
    bash tool/e2e/run.sh btc_psbt

注意：`E1 04` 只从策略的 coin type 推网络（`1` → testnet 文案），所以 regtest
的地址在设备文案里显示成 `tb1…`；脚本本身与网络无关，交易仍按 regtest 验证。
"""
from __future__ import annotations

import asyncio
import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harness import apdu, btc_rpc, btc_sighash, btcsig, psbt_host  # noqa: E402
from harness.apdu import SW_SUCCESS, parse_response  # noqa: E402
from harness.btc_sighash import sighash_p2wpkh, sighash_taproot  # noqa: E402
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

FEE = 2000
CHANGE = 300_000
# 非零 locktime + 可 RBF 的 sequence：确认页要显示这两项。
SEQUENCE = 0xFFFFFFFD
LOCKTIME = 1

CASES = [
    {
        "name": "P2WPKH",
        "template": "wpkh(@0/**)",
        "account": "m/84'/1'/0'",
        "format": btcsig.P2_BECH32,
    },
    {
        "name": "P2TR",
        "template": "tr(@0/**)",
        "account": "m/86'/1'/0'",
        "format": btcsig.P2_BECH32M,
    },
]


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def hash160(pubkey: bytes) -> bytes:
    return hashlib.new("ripemd160", hashlib.sha256(pubkey).digest()).digest()


def mine_blocks(count: int = 1) -> None:
    address = btc_rpc.call("getnewaddress", "", "bech32", wallet="miner")
    btc_rpc.call("generatetoaddress", count, address, wallet="miner")


def fund(address: str, amount_btc: float) -> tuple[str, int, int]:
    txid = btc_rpc.call("sendtoaddress", address, amount_btc, wallet="miner")
    mine_blocks()
    raw = btc_rpc.call("getrawtransaction", txid, True)
    outputs = [
        output for output in raw["vout"]
        if output["scriptPubKey"].get("address") == address
    ]
    expect(bool(outputs), f"资助交易里没有 {address} 的输出")
    return txid, outputs[0]["n"], btc_to_satoshi(outputs[0]["value"])


def script_pubkey(address: str) -> bytes:
    return bytes.fromhex(btc_rpc.call("getaddressinfo", address)["scriptPubKey"])


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


async def run_case(sess, ble, case: dict) -> None:
    name = case["name"]
    account = case["account"]
    receive_path = f"{account}/0/0"
    change_path = f"{account}/1/0"
    taproot = name == "P2TR"

    receive_address, receive_pubkey = btcsig.address(
        TEST_MNEMONIC, receive_path, case["format"], hrp="bcrt")
    change_address, change_pubkey = btcsig.address(
        TEST_MNEMONIC, change_path, case["format"], hrp="bcrt")
    if taproot:
        receive_script = bytes([0x51, 0x20]) + btcsig.taproot_output_key(
            TEST_MNEMONIC, receive_path)
        change_script = bytes([0x51, 0x20]) + btcsig.taproot_output_key(
            TEST_MNEMONIC, change_path)
    else:
        receive_script = p2wpkh_script(hash160(receive_pubkey))
        change_script = p2wpkh_script(hash160(change_pubkey))
    expect(receive_script == script_pubkey(receive_address),
           f"{name} 接收地址的 scriptPubKey 与独立派生不一致")

    key_info, _ = btcsig.account(TEST_MNEMONIC, account, network="testnet")
    print(f"  [{name}] 接收 {receive_address}")
    print(f"  [{name}] 找零 {change_address}")

    txid, vout, value = fund(receive_address, 1.0)
    print(f"  [{name}] 资助 {value} sat：{txid[:16]}…:{vout}")

    payment_script = script_pubkey(
        btc_rpc.call("getnewaddress", "", "bech32", wallet="miner"))
    tx = Tx(
        inputs=[TxIn(txid, vout, sequence=SEQUENCE)],
        outputs=[
            TxOut(value - CHANGE - FEE, payment_script),
            TxOut(CHANGE, change_script),
        ],
        locktime=LOCKTIME,
    )

    host = psbt_host.PsbtHost()
    header = psbt_host.build_psbt(
        host,
        template=case["template"],
        key_info=key_info,
        tx=tx,
        prevouts=[(value, receive_script)],
        input_paths={0: (receive_path, receive_pubkey)},
        output_paths={1: (change_path, change_pubkey)},
    )
    print(f"  [{name}] PSBTv2 头 {len(header)}B，预映像 {host.preimage_count} 份")

    rounds, data, sw = await psbt_host.sign_with_device(
        sess, ble, host, header,
        expect_texts=(
            f"Fee: {FEE} sat",
            "Fee rate: ",
            "RBF: yes",
            f"Locktime: {LOCKTIME}",
            "Inputs: 1",
            f"Amount: {value - CHANGE - FEE} sat",
            f"Change: {CHANGE} sat",
        ),
    )
    expect(sw == SW_SUCCESS,
           f"{name} 签名以 SW=0x{sw:04x} 结束（{data.hex()}），共 {rounds} 轮")
    print(f"  [{name}] ✓ T1 {rounds} 轮 0xE000 交互完成，最终 9000")

    expect(len(host.yields) == 1, f"{name} YIELD 数量 {len(host.yields)} ≠ 1")
    index, pubkey, signature = psbt_host.parse_yield(host.yields[0])
    expect(index == 0, f"{name} YIELD 的输入下标 {index} ≠ 0")

    if taproot:
        expect(pubkey == receive_pubkey[1:],
               f"{name} YIELD 公钥 {pubkey.hex()} ≠ 独立派生 x-only 公钥")
        expect(len(signature) == 64,
               f"{name} Schnorr 签名长度 {len(signature)} ≠ 64")
        digest = sighash_taproot(tx, 0, [(value, receive_script)])
        output_key = btcsig.verify_schnorr(
            TEST_MNEMONIC, receive_path, digest, signature)
        expect(bytes.fromhex(output_key) == receive_script[2:],
               f"{name} 签名对应的输出公钥与地址不一致")
        tx.inputs[0].witness = [signature]
        print(f"  [{name}] ✓ T2/T3 公钥与独立派生一致，BIP-341 签名验签通过")
    else:
        expect(pubkey == receive_pubkey,
               f"{name} YIELD 公钥 {pubkey.hex()} ≠ 独立派生公钥")
        expect(signature[-1] == 0x01,
               f"{name} 签名尾部 sighash 字节 0x{signature[-1]:02x} ≠ 0x01")
        digest = sighash_p2wpkh(
            tx, 0, p2pkh_script_code(hash160(receive_pubkey)), value)
        expect(btcsig.verify_ecdsa(pubkey, digest, signature[:-1]),
               f"{name} DER 签名对主机自算的 BIP-143 摘要验签失败")
        tx.inputs[0].witness = [signature, pubkey]
        print(f"  [{name}] ✓ T2/T3 公钥与独立派生一致，BIP-143 签名验签通过")

    spent_txid = broadcast_and_mine(tx)
    expect(btc_rpc.call("gettxout", txid, vout) is None,
           f"{name} 资助输出仍未被花费，交易没有真正生效")
    print(f"  [{name}] ✓ T4 交易进块：{spent_txid[:16]}…，UTXO 已花费")


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

    serial = os.environ.get("ANDROID_SERIAL") or None
    async with DeviceSession.start(
            fresh=True, chain_id="bitcoin", serial=serial) as sess:
        with sess.ble_connected() as ble:
            print(f"BLE 已连接，MTU={ble.get_mtu()}")
            data, sw = parse_response(ble.exchange(apdu.open_app("Bitcoin")))
            expect(sw == SW_SUCCESS, f"OPEN_APP(Bitcoin) SW=0x{sw:04x}")

            for case in CASES:
                await run_case(sess, ble, case)
            print("  ✓ T5 审阅页的金额 / 找零 / 手续费 / 费率 / RBF / locktime 来自设备解析")

    print("\n[OK] btc_psbt 通过")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
