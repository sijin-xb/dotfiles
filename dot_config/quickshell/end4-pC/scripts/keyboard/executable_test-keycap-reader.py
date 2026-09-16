#!/usr/bin/env python3
"""keycap-reader.py 的确定性测试。

真实按键没法在测试里合成（ydotool 需要额外装，uinput 需要 root），
所以直接伪造 input_event 字节喂给 parse_buffer，验证：

  1. 组合键的按下顺序被保留（Ctrl 先按，就显示在前面）
  2. 自动重复（value == 2）不会产生新行
  3. 鼠标按键（BTN_*，码值 ≥ 256）被忽略
  4. 非按键事件（EV_SYN 之类）被忽略
  5. 重复的「已按住」不会重复报告变化
  6. 未知键码有兜底名字
"""

from __future__ import annotations

import importlib.util
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent


def load_reader():
    """按路径加载 keycap-reader.py。

    文件名带连字符，不能直接 import，所以用 importlib 按路径加载；
    加载前把本目录塞进 sys.path，让它的 `from keynames import ...` 能找到。
    """
    sys.path.insert(0, str(HERE))
    spec = importlib.util.spec_from_file_location("keycap_reader", HERE / "keycap-reader.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader = load_reader()
KEY_PRESS = reader.KEY_PRESS
KEY_RELEASE = reader.KEY_RELEASE
KEY_REPEAT = reader.KEY_REPEAT
make_event = reader.make_event
parse_buffer = reader.parse_buffer

FAILURES: list[str] = []


def check(name: str, got, want) -> None:
    if got == want:
        print(f"  ok    {name}")
    else:
        print(f"  FAIL  {name}: got {got!r}, want {want!r}")
        FAILURES.append(name)


def main() -> int:
    held: dict[int, str] = {}

    # 1) Ctrl 按下 → 变化；A 按下 → 变化；顺序保持
    check("Ctrl 按下", parse_buffer(make_event(29, KEY_PRESS), held), True)
    check("按住集合", list(held.values()), ["Ctrl"])
    check("A 按下", parse_buffer(make_event(30, KEY_PRESS), held), True)
    check("组合顺序", list(held.values()), ["Ctrl", "A"])

    # 2) 自动重复不算变化
    check("自动重复被忽略", parse_buffer(make_event(30, KEY_REPEAT), held), False)
    check("重复后集合不变", list(held.values()), ["Ctrl", "A"])

    # 3) 鼠标按键（BTN_LEFT = 272）被忽略
    check("鼠标按键被忽略", parse_buffer(make_event(272, KEY_PRESS), held), False)

    # 4) 非按键事件被忽略
    check("EV_SYN 被忽略", parse_buffer(make_event(0, 0, ev_type=0x00), held), False)

    # 5) 松开 A → 变化；再松一次 → 不变
    check("A 松开", parse_buffer(make_event(30, KEY_RELEASE), held), True)
    check("松开后集合", list(held.values()), ["Ctrl"])
    check("重复松开不算变化", parse_buffer(make_event(30, KEY_RELEASE), held), False)

    # 6) 未知键码有兜底
    held.clear()
    check("未知键码仍报告", parse_buffer(make_event(600, KEY_PRESS), held), True)
    check("未知键码兜底名", list(held.values()), ["code 600"])

    # 7) 一次 read 里的多个事件被全部处理（真实 evdev 常见一包多个事件）
    held.clear()
    batch = make_event(29, KEY_PRESS) + make_event(46, KEY_PRESS) + make_event(46, KEY_RELEASE)
    check("一包多事件", parse_buffer(batch, held), True)
    check("一包多事件结果", list(held.values()), ["Ctrl"])

    # 8) 半截事件（不足一个 input_event）不会被误解析
    check("截断数据被忽略", parse_buffer(make_event(29, KEY_PRESS)[:10], held), False)

    print()
    if FAILURES:
        print(f"{len(FAILURES)} 项失败: {', '.join(FAILURES)}")
        return 1
    print("全部通过")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
