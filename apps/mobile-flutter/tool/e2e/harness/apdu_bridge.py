"""把现有 BLE 连接暴露成本机 TCP 上的 APDU 通道，供 Node 侧官方客户端库使用。

一行一个 JSON：
    请求 `{"apdu":"<hex>"}` → 响应 `{"response":"<hex data+SW>"}` / `{"error":"..."}`

只有 M5（官方 `@ledgerhq/hw-app-btc` 互操作）用得到它；其它用例仍然直接
调用 `ble.exchange()`，不经过这里。
"""
from __future__ import annotations

import asyncio
import json
import os


class ApduBridge:
    def __init__(self, ble):
        self.ble = ble
        self._server: asyncio.AbstractServer | None = None

    async def start(self) -> int:
        self._server = await asyncio.start_server(
            self._handle, "127.0.0.1", 0
        )
        return self._server.sockets[0].getsockname()[1]

    async def stop(self) -> None:
        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()
            self._server = None

    async def _handle(self, reader: asyncio.StreamReader,
                      writer: asyncio.StreamWriter) -> None:
        try:
            while True:
                line = await reader.readline()
                if not line:
                    return
                request = json.loads(line)
                try:
                    raw = await asyncio.to_thread(
                        self.ble.exchange, bytes.fromhex(request["apdu"]))
                    reply = {"response": raw.hex()}
                    if os.environ.get("APDU_TRACE") == "1":
                        print(f"  [apdu] {request['apdu']} → {raw.hex()[-4:]}")
                except Exception as error:  # noqa: BLE001 - 原样回给 Node
                    reply = {"error": str(error)}
                writer.write((json.dumps(reply) + "\n").encode())
                await writer.drain()
        finally:
            writer.close()
