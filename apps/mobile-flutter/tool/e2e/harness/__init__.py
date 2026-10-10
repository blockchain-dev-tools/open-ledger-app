"""Open Ledger App 真机 UI 自动化驱动骨架（flutter attach + VM Service）。

通路：flutter attach（提供 compileExpression 编译服务）→ DDS URI → VM Service
JSON-RPC → evaluate 注入 PointerEvent / 读运行时状态。仅对 **debug 包** 有效。
"""
