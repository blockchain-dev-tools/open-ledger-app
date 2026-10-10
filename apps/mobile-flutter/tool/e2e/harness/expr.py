"""Dart 单行表达式模板（VM Service `evaluate` 用）。

VM Service 驱动的两条约束：
- 表达式**必须单行** —— 多行块 IIFE 会报 `Can't find '}' to match '{'`；
- 返回值一律**短字符串/数字** —— VM Service 对长字符串的 `valueAsString` 会截断。

定位支持三种选择器：`key`（ValueKey，含 `Key('x')`）、`type`（runtimeType 名）、
`text`（`Text.data` 精确匹配）。

`tap` 会做两件防御：
- 目标中心若落在其外层 `Scrollable` 视口之外（SafeArea/键盘把内容裁掉），
  返回 `OFFSCREEN@…` 而不点击 —— 调用方先 `scroll_to` 再点；
- `GestureBinding` 不由 `material.dart` 导出，故经 `dynamic` 分派到
  `WidgetsBinding.instance.handlePointerEvent`。
"""
from __future__ import annotations

import json


def dart_string_literal(value: str) -> str:
    """把 Python 字符串转成 Dart 双引号字面量（ASCII 场景足够）。"""
    return json.dumps(value)


def _walk_for(by: str, value: str) -> str:
    """生成「深度遍历 Element 树、命中目标」的 Dart 片段（单行，写入局部 `hit`）。"""
    lit = dart_string_literal(value)
    if by == "key":
        cond = "final k = e.widget.key; if (k is ValueKey && k.value == " + lit + ") { hit = e; }"
    elif by == "type":
        cond = "if (e.widget.runtimeType.toString() == " + lit + ") { hit = e; }"
    elif by == "text":
        cond = "final w = e.widget; if (w is Text && w.data == " + lit + ") { hit = e; }"
    else:
        raise ValueError(f"未知选择器: {by}")
    return ("Element? hit; void walk(Element e) { " + cond + " "
            "e.visitChildren(walk); } walk(WidgetsBinding.instance.rootElement!);")


def _geom_expr(by: str, value: str) -> str:
    return (
        "(() { " + _walk_for(by, value) + " "
        "if (hit == null) return 'NOT_FOUND'; "
        "final ro = hit!.renderObject; "
        "if (ro is! RenderBox) return 'NOT_RENDERBOX:' + ro.runtimeType.toString(); "
        "if (!ro.hasSize) return 'NO_SIZE'; "
        "final c = ro.localToGlobal(ro.size.center(Offset.zero)); "
        "return 'size=' + ro.size.toString() + ' center=' + c.toString(); })()"
    )


def _tap_expr(by: str, value: str, pointer: int) -> str:
    return (
        "(() { " + _walk_for(by, value) + " "
        "if (hit == null) return 'NOT_FOUND'; "
        "final ro = hit!.renderObject; "
        "if (ro is! RenderBox) return 'NOT_RENDERBOX:' + ro.runtimeType.toString(); "
        "if (!ro.hasSize) return 'NO_SIZE'; "
        "final c = ro.localToGlobal(ro.size.center(Offset.zero)); "
        "final st = hit!.findAncestorStateOfType<ScrollableState>(); "
        "if (st != null) { final vr = st.context.findRenderObject(); "
        "if (vr is RenderBox) { final vp = vr.localToGlobal(Offset.zero) & vr.size; "
        "if (!vp.contains(c)) return 'OFFSCREEN@' + c.toString(); } } "
        "final g = WidgetsBinding.instance as dynamic; "
        "g.handlePointerEvent(PointerDownEvent(position: c, pointer: " + str(pointer) + ")); "
        "g.handlePointerEvent(PointerUpEvent(position: c, pointer: " + str(pointer) + ")); "
        "return 'TAPPED@' + c.toString(); })()"
    )


def _scroll_expr(by: str, value: str) -> str:
    return (
        "(() { " + _walk_for(by, value) + " "
        "if (hit == null) return 'NOT_FOUND'; "
        "try { Scrollable.ensureVisible(hit!, duration: Duration.zero); } "
        "catch (e) { return 'NO_SCROLLABLE'; } "
        "return 'SCROLLED'; })()"
    )


def screen() -> str:
    """返回当前页面里 runtimeType 以 `Screen` 结尾的 widget 类型（逗号分隔）。"""
    return (
        "(() { final out = <String>[]; void walk(Element e) { "
        "final t = e.widget.runtimeType.toString(); "
        "if (t.endsWith('Screen') && !out.contains(t)) out.add(t); "
        "e.visitChildren(walk); } "
        "walk(WidgetsBinding.instance.rootElement!); return out.join(','); })()"
    )


def keys(max_chars: int = 100) -> str:
    """返回当前页面前若干 String 型 ValueKey 值（逗号分隔，带长度护栏）。"""
    return (
        "(() { final out = <String>[]; var n = 0; void walk(Element e) { "
        "if (n > " + str(max_chars) + ") return; "
        "final k = e.widget.key; "
        "if (k is ValueKey) { final v = k.value; "
        "if (v is String && !out.contains(v)) { out.add(v); n += v.length + 1; } } "
        "e.visitChildren(walk); } "
        "walk(WidgetsBinding.instance.rootElement!); return out.join(','); })()"
    )


# ── 对外：三种选择器 × {geom, tap} + scroll_to ──────────────────────────
def geom(by: str, value: str) -> str:
    return _geom_expr(by, value)


def tap(by: str, value: str, pointer: int = 9001) -> str:
    return _tap_expr(by, value, pointer)


def scroll_to(by: str, value: str) -> str:
    return _scroll_expr(by, value)

def _collect_texts_snippet() -> str:
    return ("final out = <String>[]; void walk(Element e) { final w = e.widget; "
            "if (w is Text && w.data != null) out.add(w.data!); "
            "e.visitChildren(walk); } walk(WidgetsBinding.instance.rootElement!);")


def text_count() -> str:
    """当前树中 Text 节点数量（用于逐条取文本，绕开 valueAsString 截断）。"""
    return "(() { " + _collect_texts_snippet() + " return out.length.toString(); })()"


def text_at(index: int, max_chars: int = 100) -> str:
    """取第 index 个 Text 的 data（超长截断，返回短串）。"""
    return ("(() { " + _collect_texts_snippet() + " "
            "if (" + str(index) + " >= out.length) return 'OOB'; "
            "var s = out[" + str(index) + "]; "
            "if (s.length > " + str(max_chars) + ") s = s.substring(0, " + str(max_chars) + "); "
            "return s; })()")
