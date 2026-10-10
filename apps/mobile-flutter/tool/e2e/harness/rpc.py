"""VM Service JSON-RPC 客户端（WebSocket）。

约定（实测）：
- 响应体在响应的 `result` 键下；事件/通知无 `id`，直接忽略；
- `evaluate` 需要 `isolateId` + `targetId`（用 rootLib 的 id）+ `expression`；
- 字符串返回体带 `valueAsString` + `length`，长串会被截断。
"""
from __future__ import annotations

import json
from typing import Any

import websockets


def ws_url_from_vm_service(uri: str) -> str:
    """把 `http://host:port/token/` 的 VM Service / DDS URI 转成 WebSocket URL。"""
    if not uri.startswith("http://"):
        raise ValueError(f"不认识的 VM Service URI: {uri}")
    return uri.rstrip("/").replace("http://", "ws://", 1) + "/ws"


class TruncatedResult(RuntimeError):
    """VM Service 对长字符串的 `valueAsString` 会截断（见 tool/e2e/README.md）→ 断言应返回短值。"""


class Rpc:
    def __init__(self, ws: Any) -> None:
        self._ws = ws
        self._id = 0

    @classmethod
    async def connect(cls, vm_service_uri: str) -> "Rpc":
        ws = await websockets.connect(ws_url_from_vm_service(vm_service_uri), max_size=None)
        return cls(ws)

    async def aclose(self) -> None:
        await self._ws.close()

    async def call(self, method: str, params: dict[str, Any] | None = None) -> Any:
        self._id += 1
        req: dict[str, Any] = {"jsonrpc": "2.0", "id": self._id, "method": method}
        if params is not None:
            req["params"] = params
        await self._ws.send(json.dumps(req))
        while True:
            msg = json.loads(await self._ws.recv())
            if msg.get("id") != self._id:
                continue  # 事件/通知
            if "error" in msg:
                raise RuntimeError(f"{method} 失败: {msg['error']}")
            return msg["result"]

    async def isolate_id(self) -> str:
        vm = await self.call("getVM")
        isolates = vm.get("isolates") or []
        if not isolates:
            raise RuntimeError("没有可用的 isolate（App 是否为 debug 包并在运行？）")
        return isolates[0]["id"]

    async def root_library_id(self, isolate_id: str) -> str:
        iso = await self.call("getIsolate", {"isolateId": isolate_id})
        lib = iso.get("rootLib")
        if not lib:
            raise RuntimeError("isolate 没有 rootLib")
        return lib["id"]

    async def evaluate(self, isolate_id: str, target_id: str, expression: str) -> Any:
        return await self.call(
            "evaluate",
            {"isolateId": isolate_id, "targetId": target_id, "expression": expression},
        )

    @staticmethod
    def parse_string(result: Any) -> str | None:
        """把 evaluate 返回体解析成字符串；被截断时抛 TruncatedResult。"""
        if not isinstance(result, dict):
            return str(result)
        if result.get("type") == "Sentinel":
            raise RuntimeError(f"evaluate 返回 Sentinel: {result}")
        kind = result.get("kind")
        if kind == "Null":
            return None
        if kind == "Error":
            raise RuntimeError(f"表达式求值出错: {result.get('valueAsString')}")
        value = result.get("valueAsString")
        length = result.get("length")
        if isinstance(value, str) and isinstance(length, int) and length != len(value):
            raise TruncatedResult(f"返回体被截断（真实长度 {length}，收到 {len(value)}）：{value!r}")
        return value
