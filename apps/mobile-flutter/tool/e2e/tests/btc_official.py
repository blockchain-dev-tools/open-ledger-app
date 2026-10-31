#!/usr/bin/env python3
"""M5 互操作：用官方 `@ledgerhq/hw-app-btc` 驱动真机签一笔 regtest 交易。

判据不是「我们自己验签通过」，而是：

  T1  官方库自己发出的 `E1 05` / `E1 00` / `E1 04` 全部被设备正确应答
  T2  官方库内部的 `ClientCommandInterpreter` 能回答设备的 `0xE000`
      （Merkle 证明、预映像、续收都由官方实现处理）
  T3  官方库最终拼出的交易被 regtest 节点接受并进块，且 UTXO 被花费

PSBT 由本仓的主机代码构造（与 `btc_psbt.py` 同一套 map），设备侧协议交互
完全交给官方库；我们只提供一个 TCP→BLE 的传输适配器。

前置：
    tool/e2e/regtest/up.sh
    pnpm install            # 仓库根，已含 @ledgerhq/hw-app-btc
"""
from __future__ import annotations

import asyncio
import hashlib
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harness import apdu, btc_rpc, btcsig, psbt_host  # noqa: E402
from harness.apdu import SW_SUCCESS, parse_response  # noqa: E402
from harness.apdu_bridge import ApduBridge  # noqa: E402
from harness.btc_tx import Tx, TxIn, TxOut, btc_to_satoshi, p2wpkh_script  # noqa: E402
from harness.device import TEST_MNEMONIC  # noqa: E402
from harness.session import DeviceSession  # noqa: E402

FEE = 2000
CHANGE = 300_000
ACCOUNT_PATH = "m/84'/1'/0'"
RECEIVE_PATH = f"{ACCOUNT_PATH}/0/0"
CHANGE_PATH = f"{ACCOUNT_PATH}/1/0"
TEMPLATE = "wpkh(@0/**)"

SCRIPT = (Path(__file__).resolve().parents[1]
          / "js" / "official_btc_sign.mjs")
REPO_ROOT = Path(__file__).resolve().parents[4]


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def hash160(pubkey: bytes) -> bytes:
    return hashlib.new("ripemd160", hashlib.sha256(pubkey).digest()).digest()


def mine_blocks(count: int = 1) -> None:
    address = btc_rpc.call("getnewaddress", "", "bech32", wallet="miner")
    btc_rpc.call("generatetoaddress", count, address, wallet="miner")


def script_pubkey(address: str) -> bytes:
    return bytes.fromhex(btc_rpc.call("getaddressinfo", address)["scriptPubKey"])


def fund(address: str, amount_btc: float) -> tuple[str, int, int]:
    txid = btc_rpc.call("sendtoaddress", address, amount_btc, wallet="miner")
    mine_blocks()
    raw = btc_rpc.call("getrawtransaction", txid, True)
    outputs = [o for o in raw["vout"] if o["scriptPubKey"].get("address") == address]
    expect(bool(outputs), f"资助交易里没有 {address} 的输出")
    return txid, outputs[0]["n"], btc_to_satoshi(outputs[0]["value"])


async def run_official(port: int, psbt: bytes) -> dict:
    process = await asyncio.create_subprocess_exec(
        "node", str(SCRIPT), str(port), psbt.hex(), ACCOUNT_PATH, "bech32",
        cwd=str(REPO_ROOT),
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=180)
    text = stdout.decode(errors="replace").strip()
    if process.returncode != 0 or not text:
        raise RuntimeError(
            f"官方客户端失败（exit {process.returncode}）：{text}\n"
            f"{stderr.decode(errors='replace')[-2000:]}")
    return json.loads(text.splitlines()[-1])


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
        pass

    receive_address, receive_pubkey = btcsig.address(
        TEST_MNEMONIC, RECEIVE_PATH, btcsig.P2_BECH32, hrp="bcrt")
    change_address, change_pubkey = btcsig.address(
        TEST_MNEMONIC, CHANGE_PATH, btcsig.P2_BECH32, hrp="bcrt")
    receive_script = p2wpkh_script(hash160(receive_pubkey))
    change_script = p2wpkh_script(hash160(change_pubkey))
    expect(receive_script == script_pubkey(receive_address),
           "接收地址的 scriptPubKey 与独立派生不一致")

    txid, vout, value = fund(receive_address, 1.0)
    print(f"资助 {value} sat：{txid[:16]}…:{vout}")

    payment_script = script_pubkey(
        btc_rpc.call("getnewaddress", "", "bech32", wallet="miner"))
    tx = Tx(
        inputs=[TxIn(txid, vout, sequence=0xFFFFFFFD)],
        outputs=[
            TxOut(value - CHANGE - FEE, payment_script),
            TxOut(CHANGE, change_script),
        ],
        locktime=0,
    )
    key_info, _ = btcsig.account(TEST_MNEMONIC, ACCOUNT_PATH, network="testnet")
    psbt = psbt_host.build_psbt(
        psbt_host.PsbtHost(),
        template=TEMPLATE,
        key_info=key_info,
        tx=tx,
        prevouts=[(value, receive_script)],
        input_paths={0: (RECEIVE_PATH, receive_pubkey)},
        output_paths={1: (CHANGE_PATH, change_pubkey)},
        as_bytes=True,
    )
    print(f"PSBTv2 {len(psbt)}B")

    serial = os.environ.get("ANDROID_SERIAL") or None
    async with DeviceSession.start(
            fresh=True, chain_id="bitcoin", serial=serial) as sess:
        with sess.ble_connected() as ble:
            print(f"BLE 已连接，MTU={ble.get_mtu()}")
            data, sw = parse_response(ble.exchange(apdu.open_app("Bitcoin")))
            expect(sw == SW_SUCCESS, f"OPEN_APP(Bitcoin) SW=0x{sw:04x}")

            bridge = ApduBridge(ble)
            port = await bridge.start()
            try:
                task = asyncio.create_task(run_official(port, psbt))
                screen = asyncio.create_task(
                    sess.app.wait_for_screen({"TransactionScreen"}, timeout=90))
                done, _ = await asyncio.wait(
                    {task, screen}, return_when=asyncio.FIRST_COMPLETED)
                if task in done:
                    screen.cancel()
                    result = task.result()  # 真正的失败原因在这里抛出
                else:
                    await sess.app.settle(0.8)
                    for needle in (
                        f"Fee: {FEE} sat",
                        f"Amount: {value - CHANGE - FEE} sat",
                        f"Change: {CHANGE} sat",
                        "Inputs: 1",
                    ):
                        expect(await sess.app.has_text(needle),
                               f"官方流程的确认页缺少 {needle!r}")
                    hit = await sess.app.tap_key("sign-approve")
                    expect(hit.startswith("TAPPED"), f"点不到 Approve：{hit!r}")
                    result = await task
            finally:
                await bridge.stop()

    signed_tx = result.get("tx")
    expect(bool(signed_tx), f"官方库没有返回已完成的交易：{result}")
    print(f"  ✓ T1/T2 官方库完成全部 APDU 交互，返回 {len(signed_tx) // 2}B 交易")

    verdict = btc_rpc.call("testmempoolaccept", [signed_tx])[0]
    expect(verdict.get("allowed") is True,
           f"节点拒绝官方库签出的交易：{verdict.get('reject-reason')}")
    broadcast = btc_rpc.call("sendrawtransaction", signed_tx)
    mine_blocks()
    expect(btc_rpc.call("gettxout", txid, vout) is None,
           "资助输出仍未被花费，交易没有真正生效")
    print(f"  ✓ T3 交易进块：{broadcast[:16]}…，UTXO 已花费")

    print("[OK] btc_official 通过")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
