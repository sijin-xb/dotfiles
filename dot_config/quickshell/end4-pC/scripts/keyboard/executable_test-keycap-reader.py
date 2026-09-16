#!/usr/bin/env python3
"""keycap-reader.py 的确定性测试。

真实按键没法在测试里合成（ydotool 需要额外装，uinput 需要 root），
所以直接伪造 input_event 字节喂给 Session / parse_buffer。

重点覆盖「键帽」和「文本」两条路径的分工 —— 这是这个功能最容易做错的地方：
可打印字符应该进文本（能读出单词），修饰键与组合键才应该当键帽。
"""

from __future__ import annotations

import importlib.util
import pathlib
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent

# 键码
ESC, BACKSPACE, TAB, ENTER = 1, 14, 15, 28
LCTRL, LSHIFT, LALT, LWIN, CAPS = 29, 42, 56, 125, 58
A, B, D, H, O, SPACE, SEMI, UP = 30, 48, 32, 35, 24, 57, 39, 103
BTN_LEFT = 272

FAILURES: list[str] = []


def load_reader():
    """按路径加载 keycap-reader.py（文件名带连字符，不能直接 import）。"""
    sys.path.insert(0, str(HERE))
    spec = importlib.util.spec_from_file_location("keycap_reader", HERE / "keycap-reader.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader = load_reader()
Session = reader.Session
parse_buffer = reader.parse_buffer
make_event = reader.make_event
KEY_PRESS = reader.KEY_PRESS
KEY_RELEASE = reader.KEY_RELEASE
KEY_REPEAT = reader.KEY_REPEAT


def check(name: str, got, want) -> None:
    if got == want:
        print(f"  ok    {name}")
    else:
        print(f"  FAIL  {name}: got {got!r}, want {want!r}")
        FAILURES.append(name)


def press(session: Session, code: int) -> bool:
    return session.handle(code, KEY_PRESS)


def release(session: Session, code: int) -> bool:
    return session.handle(code, KEY_RELEASE)


def main() -> int:
    # ── 文本路径 ──────────────────────────────────────────────────────
    s = Session()
    for code in (H, 18, 38, 38, O):   # h e l l o
        press(s, code)
    check("打 hello → 文本可读", s.text_value(), "hello")
    check("可打印字符不进键帽", s.keys(), [])

    press(s, SPACE)
    for code in (B, A, D):             # b a d
        press(s, code)
    check("空格断词后继续累积", s.text_value(), "hello bad")

    press(s, BACKSPACE)
    check("退格删一个字", s.text_value(), "hello ba")
    press(s, ESC)
    check("Esc 清空", s.text_value(), "")

    # ── Shift / Caps 影响大小写 ───────────────────────────────────────
    s = Session()
    press(s, LSHIFT)
    press(s, H)
    release(s, H)
    check("Shift+h → 大写", s.text_value(), "H")
    check("Shift 本身显示成键帽", s.keys(), ["Shift"])
    release(s, LSHIFT)
    check("松开 Shift 后键帽清空", s.keys(), [])

    s = Session()
    press(s, CAPS)
    press(s, A)
    check("Caps 打开 → 大写", s.text_value(), "A")
    press(s, LSHIFT)
    press(s, B)
    check("Caps + Shift → 回到小写", s.text_value(), "Ab")
    check("Caps 本身不当键帽展示", s.keys(), ["Shift"])

    # ── 组合键走键帽，不进文本 ────────────────────────────────────────
    s = Session()
    press(s, LCTRL)
    press(s, A)
    check("Ctrl+a → 键帽", sorted(s.keys()), ["A", "Ctrl"])
    check("Ctrl+a 不进文本", s.text_value(), "")
    release(s, A)
    release(s, LCTRL)
    check("松开后键帽清空", s.keys(), [])

    s = Session()
    press(s, LWIN)
    press(s, LSHIFT)
    press(s, SEMI)
    check("Super+Shift+; → 键帽", sorted(s.keys()), sorted(["Shift", "Super", ";"]))
    check("符号在组合键下也不进文本", s.text_value(), "")

    # ── 不可打印键 ────────────────────────────────────────────────────
    s = Session()
    press(s, UP)
    check("方向键走键帽", s.keys(), ["↑"])
    check("方向键不进文本", s.text_value(), "")

    s = Session()
    press(s, ENTER)
    check("Enter 当空格断词", s.text_value(), " ")

    # ── 自动重复不刷屏 ────────────────────────────────────────────────
    s = Session()
    press(s, A)
    s.handle(A, KEY_REPEAT)
    s.handle(A, KEY_REPEAT)
    check("按住不放不重复追加", s.text_value(), "a")

    # ── 鼠标按键被忽略 ────────────────────────────────────────────────
    s = Session()
    check("鼠标按键无变化", parse_buffer(make_event(BTN_LEFT, KEY_PRESS), s), False)
    check("鼠标按键不进文本", s.text_value(), "")

    # ── 长度上限 ──────────────────────────────────────────────────────
    s = Session(max_text=5)
    for _ in range(8):
        press(s, A)
    check("超长丢最老的", s.text_value(), "aaaaa")

    # ── 闲置超时清空 ──────────────────────────────────────────────────
    s = Session(text_idle=1.0)
    press(s, A)
    check("刚输入不过期", s.expire_text_if_idle(time.monotonic()), False)
    check("超时清空", s.expire_text_if_idle(time.monotonic() + 5), True)
    check("清空后文本为空", s.text_value(), "")

    # ── --no-text 模式：全部退回键帽 ──────────────────────────────────
    s = Session(text_enabled=False)
    press(s, A)
    check("关文本时字母也走键帽", s.keys(), ["A"])
    check("关文本时无文本", s.text_value(), "")

    # ── 一包多事件 / 截断数据 ─────────────────────────────────────────
    s = Session()
    batch = make_event(H, KEY_PRESS) + make_event(H, KEY_RELEASE) + make_event(O, KEY_PRESS)
    check("一包多事件", parse_buffer(batch, s), True)
    # 松开字母**不该**把它从文本里删掉 —— 文本是「已经打出来的历史」，
    # 删掉的话边打边消失，就完全读不出单词了
    check("一包多事件：松开不回退已输入字符", s.text_value(), "ho")

    s = Session()
    check("截断数据被忽略", parse_buffer(make_event(A, KEY_PRESS)[:10], s), False)

    # ── 快照格式（QML 侧解析用） ──────────────────────────────────────
    import json

    s = Session()
    press(s, LCTRL)
    press(s, A)
    payload = json.loads(s.snapshot())
    check("快照含 keys", sorted(payload["keys"]), ["A", "Ctrl"])
    check("快照含 text", payload["text"], "")

    print()
    if FAILURES:
        print(f"{len(FAILURES)} 项失败: {', '.join(FAILURES)}")
        return 1
    print("全部通过")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
