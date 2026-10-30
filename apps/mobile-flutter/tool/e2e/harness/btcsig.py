"""独立的 BTC 四种地址 / Schnorr 验签入口：委托给 `js/btcverify.mjs`。

派生与 BIP-341 tweak 在 Node 侧（@noble/@scure），地址字符串编码在这里
（`btcaddr.encode_segwit` + `base58x.encode_check`）—— 与设备侧 Rust 实现
（k256 + open-ledger-crypto）是两套独立代码。
"""
from __future__ import annotations

import json
import pathlib
import subprocess

from . import base58x, btcaddr

_ROOT = pathlib.Path(__file__).resolve().parents[5]
_SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "js" / "btcverify.mjs"

# 官方 app-bitcoin 的 P2 地址格式。
P2_LEGACY = 0x00
P2_P2SH = 0x01
P2_BECH32 = 0x02
P2_BECH32M = 0x04

_TYPES = {
    P2_LEGACY: "p2pkh",
    P2_P2SH: "p2sh-p2wpkh",
    P2_BECH32: "p2wpkh",
    P2_BECH32M: "p2tr",
}


def _run(payload: dict) -> dict:
    proc = subprocess.run(
        ["node", str(_SCRIPT)],
        input=json.dumps(payload), text=True, capture_output=True,
        cwd=str(_ROOT), check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"btcverify 失败: {proc.stderr.strip()}")
    return json.loads(proc.stdout)


def address(mnemonic: str, path: str, p2_format: int) -> tuple[str, bytes]:
    """独立派生 (地址, 33B 压缩公钥)。`p2_format` 是官方 P2 枚举。"""
    address_type = _TYPES.get(p2_format)
    if address_type is None:
        raise ValueError(f"unsupported address format {p2_format}")
    out = _run({
        "op": "address", "mnemonic": mnemonic, "path": path, "type": address_type,
    })
    encoding = out["encoding"]
    if "witnessVersion" in encoding:
        encoded = btcaddr.encode_segwit(
            "bc",
            encoding["witnessVersion"],
            bytes.fromhex(encoding["program"]),
        )
    else:
        encoded = base58x.encode_check(
            bytes([encoding["prefix"]]) + bytes.fromhex(encoding["payload"])
        )
    return encoded, bytes.fromhex(out["publicKey"])


def verify_schnorr(
    mnemonic: str,
    path: str,
    sighash: bytes,
    signature: bytes,
    hash_type: int = 0,
) -> str:
    """用 Taproot 输出公钥验证签名；返回输出公钥（hex），验证失败即抛错。"""
    out = _run({
        "op": "schnorr-verify",
        "mnemonic": mnemonic,
        "path": path,
        "sighash": sighash.hex(),
        "hashType": hash_type,
        "signature": signature.hex(),
    })
    if not out.get("ok"):
        raise RuntimeError("Schnorr 验签失败")
    return out["outputKey"]
