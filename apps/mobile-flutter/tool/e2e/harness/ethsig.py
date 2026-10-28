"""独立的 ETH 验签：委托给 `js/ethverify.mjs`（node + @noble/@scure，离线）。

刻意不复用设备侧实现，保证「独立恢复地址并比对」是真独立。
"""
from __future__ import annotations

import json
import pathlib
import subprocess

from .apdu import ETH_PATH

_ROOT = pathlib.Path(__file__).resolve().parents[5]          # 仓库根（node_modules 所在）
_SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "js" / "ethverify.mjs"


def _run(payload: dict) -> dict:
    proc = subprocess.run(
        ["node", str(_SCRIPT)],
        input=json.dumps(payload), text=True, capture_output=True,
        cwd=str(_ROOT), check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"ethverify 失败: {proc.stderr.strip()}")
    return json.loads(proc.stdout)


def derive_address(mnemonic: str, path: str = ETH_PATH) -> tuple[str, bytes]:
    """从助记词独立派生 (地址, 65B 公钥)。"""
    out = _run({"op": "derive", "mnemonic": mnemonic, "path": path})
    return out["address"], bytes.fromhex(out["publicKey"])


def recover_address(kind: str, data: bytes, v: int, r: bytes, s: bytes) -> str:
    """从签名恢复地址。kind ∈ {'personal','raw'}（raw = keccak256(data) 直签）。"""
    out = _run({
        "op": "recover", "kind": kind, "data": data.hex(),
        "v": v, "r": r.hex(), "s": s.hex(),
    })
    return out["address"]


def tip712_digest(domain_hash: bytes, message_hash: bytes) -> bytes:
    """`keccak256(0x19 0x01 || domainHash || messageHash)`（Tron TIP-712）。"""
    out = _run({
        "op": "tip712",
        "domain": domain_hash.hex(),
        "message": message_hash.hex(),
    })
    return bytes.fromhex(out["digest"])


def ecdh_shared(mnemonic: str, path: str, peer_public_key: bytes) -> bytes:
    """独立计算 ECDH 共享点（65B 未压缩，`04 || X || Y`）。"""
    out = _run({
        "op": "ecdh", "mnemonic": mnemonic, "path": path,
        "peerPublicKey": peer_public_key.hex(),
    })
    return bytes.fromhex(out["shared"])
