"""本机 regtest 的 JSON-RPC 客户端（仅标准库）。

真值来自 Bitcoin Core：地址合法性、mempool 接受、交易上链都由节点判定，
不用设备侧或 harness 自己的代码自证。

用法：
    from harness import btc_rpc
    btc_rpc.call("getblockcount")
"""
from __future__ import annotations

import base64
import json
import os
import pathlib
import urllib.request

_REPO_ROOT = pathlib.Path(__file__).resolve().parents[5]

DATADIR = pathlib.Path(os.environ.get("BTC_REGTEST_DATADIR", _REPO_ROOT / "tmp" / "regtest"))
PORT = int(os.environ.get("BTC_RPC_PORT", "18443"))


class RpcError(RuntimeError):
    """节点返回了 JSON-RPC error。"""


def _auth_header() -> str:
    cookie = DATADIR / "regtest" / ".cookie"
    if not cookie.exists():
        raise RuntimeError(
            f"找不到 RPC cookie：{cookie}。先跑 tool/e2e/regtest/up.sh。")
    token = base64.b64encode(cookie.read_text().strip().encode()).decode()
    return f"Basic {token}"


def call(method: str, *params, wallet: str | None = None):
    """调用一个 RPC 方法。`wallet` 非空时走该钱包的端点。"""
    url = f"http://127.0.0.1:{PORT}/"
    if wallet:
        url += f"wallet/{wallet}"
    payload = json.dumps(
        {"jsonrpc": "1.0", "id": "open-ledger-e2e", "method": method, "params": list(params)}
    ).encode()
    request = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json", "Authorization": _auth_header()},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = json.loads(response.read())
    except urllib.error.HTTPError as error:  # type: ignore[attr-defined]
        # 节点把 RPC 错误放在 500 的响应体里，必须读出来才能看到原因。
        try:
            body = json.loads(error.read())
        except (ValueError, OSError):
            raise RpcError(f"{method}: HTTP {error.code}") from error
    except urllib.error.URLError as error:  # type: ignore[attr-defined]
        raise RuntimeError(
            f"regtest RPC 不可达（{url}）：{error}。先跑 tool/e2e/regtest/up.sh。") from error
    if body.get("error"):
        raise RpcError(f"{method}: {body['error']}")
    return body["result"]


def ensure_running() -> int:
    """返回区块高度；节点未运行则抛出带操作提示的错误。"""
    return call("getblockcount")
