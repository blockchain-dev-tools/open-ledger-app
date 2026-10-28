"""独立的 Ed25519 派生与验签：委托给 `js/edverify.mjs`（node + @noble，离线）。

刻意不复用设备侧 Rust 实现（ed25519-dalek + 自家 SLIP-10），保证「独立验证」成立。
"""
from __future__ import annotations

import json
import pathlib
import subprocess

_ROOT = pathlib.Path(__file__).resolve().parents[5]          # 仓库根（node_modules 所在）
_SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "js" / "edverify.mjs"


def _run(payload: dict) -> dict:
    proc = subprocess.run(
        ["node", str(_SCRIPT)],
        input=json.dumps(payload), text=True, capture_output=True,
        cwd=str(_ROOT), check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"edverify 失败: {proc.stderr.strip()}")
    return json.loads(proc.stdout)


def derive_public_key(mnemonic: str, path: str) -> bytes:
    """从助记词独立派生 32 字节 Ed25519 公钥。"""
    out = _run({"op": "derive", "mnemonic": mnemonic, "path": path})
    return bytes.fromhex(out["publicKey"])


def verify(public_key: bytes, message: bytes, signature: bytes) -> None:
    """验签失败时抛错。"""
    _run({
        "op": "verify",
        "publicKey": public_key.hex(),
        "message": message.hex(),
        "signature": signature.hex(),
    })
