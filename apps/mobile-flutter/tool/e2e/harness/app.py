"""已 attach 的 debug App 的驱动句柄（evaluate + 高层动词）。"""
from __future__ import annotations

import asyncio

from . import expr
from .rpc import Rpc


class FlutterApp:
    def __init__(self, rpc: Rpc, isolate_id: str, root_lib_id: str) -> None:
        self._rpc = rpc
        self._isolate = isolate_id
        self._root_lib = root_lib_id

    @classmethod
    async def connect(cls, vm_service_uri: str) -> "FlutterApp":
        rpc = await Rpc.connect(vm_service_uri)
        isolate = await rpc.isolate_id()
        root_lib = await rpc.root_library_id(isolate)
        return cls(rpc, isolate, root_lib)

    async def aclose(self) -> None:
        await self._rpc.aclose()

    async def eval_str(self, expression: str) -> str | None:
        """在根库作用域里求值，返回字符串结果。"""
        result = await self._rpc.evaluate(self._isolate, self._root_lib, expression)
        return Rpc.parse_string(result)

    async def settle(self, seconds: float = 0.5) -> None:
        """等待若干帧，让路由转场 / 布局稳定后再交互。"""
        await asyncio.sleep(seconds)

    # ── 读 ────────────────────────────────────────────────────────────

    async def screen(self) -> list[str]:
        """当前页面里 runtimeType 以 `Screen` 结尾的 widget 类型。"""
        raw = await self.eval_str(expr.screen())
        return [p for p in (raw or "").split(",") if p]

    async def keys(self) -> list[str]:
        """当前页面部分 String 型 ValueKey 值。"""
        raw = await self.eval_str(expr.keys())
        return [p for p in (raw or "").split(",") if p]

    async def texts(self, max_items: int = 200) -> list[str]:
        """当前树里所有 Text.data（按 DFS 顺序，逐条取以绕开截断）。"""
        count_raw = await self.eval_str(expr.text_count())
        try:
            count = int(count_raw or "0")
        except ValueError:
            return []
        out: list[str] = []
        for i in range(min(count, max_items)):
            value = await self.eval_str(expr.text_at(i))
            if value is not None and value != "OOB":
                out.append(value)
        return out

    async def wait_for_screen(self, names: set[str], timeout: float = 10.0) -> list[str]:
        """轮询直到当前屏出现 `names` 之一（或超时）。返回最后一次读到的屏幕列表。"""
        deadline = asyncio.get_event_loop().time() + timeout
        screens: list[str] = []
        while asyncio.get_event_loop().time() < deadline:
            screens = await self.screen()
            if set(screens) & names:
                return screens
            await asyncio.sleep(0.3)
        return screens

    # ── 驱动 ──────────────────────────────────────────────────────────

    async def find(self, by: str, value: str) -> str:
        """返回目标节点的 `size=... center=...`（窗口内绝对逻辑坐标）。"""
        return await self.eval_str(expr.geom(by, value)) or ""

    async def scroll_to(self, by: str, value: str) -> str:
        """把目标滚入其外层 Scrollable 的视口。"""
        return await self.eval_str(expr.scroll_to(by, value)) or ""

    async def tap(self, by: str, value: str) -> str:
        """按选择器（key / type / text）在节点中心注入一次点击。

        自动处理两种已知竞态：转场中求值返回空 → 静置后重试一次；
        目标落在视口外 → 先滚入视口再点。
        """
        r = await self.eval_str(expr.tap(by, value)) or ""
        if not r:  # 转场/首帧未就绪，evaluate 偶尔返回空
            await self.settle(0.4)
            r = await self.eval_str(expr.tap(by, value)) or ""
        if r.startswith("OFFSCREEN"):
            await self.scroll_to(by, value)
            await self.settle(0.4)
            r = await self.eval_str(expr.tap(by, value)) or ""
        return r

    async def tap_key(self, key: str) -> str:
        return await self.tap("key", key)

    async def tap_type(self, type_name: str) -> str:
        return await self.tap("type", type_name)

    async def tap_text(self, text: str) -> str:
        return await self.tap("text", text)
