#!/usr/bin/env python3
"""从内核头文件生成键码 → 显示名对照表。

键名表手写容易漏键（多媒体键、小键盘、国际键盘的键位特别多），
而 /usr/include/linux/input-event-codes.h 是权威来源，直接从它生成。

生成物 scripts/keyboard/keynames.py 随仓库提交，运行时不再依赖头文件 ——
在没装 linux-api-headers 的机器上也能跑。

用法：gen-keynames.py [头文件路径] [输出路径]
"""

from __future__ import annotations

import pathlib
import re
import sys

DEFAULT_HEADER = "/usr/include/linux/input-event-codes.h"

# 显示名不好直接由内核常量名推出来的，在这里显式指定。
# 键位显示只需要「用户看得懂的名字」，不需要区分左右（左右 Ctrl 都显示 Ctrl）。
EXPLICIT = {
    "LEFTCTRL": "Ctrl", "RIGHTCTRL": "Ctrl",
    "LEFTSHIFT": "Shift", "RIGHTSHIFT": "Shift",
    "LEFTALT": "Alt", "RIGHTALT": "Alt",
    "LEFTMETA": "Super", "RIGHTMETA": "Super",
    "CAPSLOCK": "Caps", "NUMLOCK": "Num", "SCROLLLOCK": "Scroll",
    "ENTER": "Enter", "SPACE": "Space", "TAB": "Tab", "ESC": "Esc",
    "BACKSPACE": "Backspace", "DELETE": "Del", "INSERT": "Ins",
    "HOME": "Home", "END": "End", "PAGEUP": "PgUp", "PAGEDOWN": "PgDn",
    "UP": "↑", "DOWN": "↓", "LEFT": "←", "RIGHT": "→",
    "MINUS": "-", "EQUAL": "=", "LEFTBRACE": "[", "RIGHTBRACE": "]",
    "BACKSLASH": "\\", "SEMICOLON": ";", "APOSTROPHE": "'", "GRAVE": "`",
    "COMMA": ",", "DOT": ".", "SLASH": "/",
    "SYSRQ": "PrtSc", "PAUSE": "Pause", "STOP": "Stop", "AGAIN": "Again",
    "COMPOSE": "Compose", "MENU": "Menu", "KPENTER": "KP Enter",
    "KPSLASH": "KP /", "KPASTERISK": "KP *", "KPMINUS": "KP -",
    "KPPLUS": "KP +", "KPDOT": "KP .", "KPCOMMA": "KP ,",
    "VOLUMEUP": "Vol+", "VOLUMEDOWN": "Vol-", "MUTE": "Mute",
    "PLAYPAUSE": "Play/Pause", "NEXT": "Next", "NEXTSONG": "Next",
    "PREVIOUS": "Prev", "PREVIOUSSONG": "Prev", "STOPCD": "Stop",
    "BRIGHTNESSUP": "Bright+", "BRIGHTNESSDOWN": "Bright-",
    "BRIGHTNESSAUTO": "Bright auto", "BRIGHTNESSTOGGLE": "Bright toggle",
    "KBDILLUMUP": "Kbd light+", "KBDILLUMDOWN": "Kbd light-",
    "KBDILLUMTOGGLE": "Kbd light", "MICMUTE": "Mic mute",
    "POWER": "Power", "SLEEP": "Sleep", "WAKEUP": "Wake",
    "CALCULATOR": "Calc", "MAIL": "Mail", "HOMEPAGE": "Browser home",
    "BACK": "Back", "FORWARD": "Forward", "REFRESH": "Refresh",
    "BOOKMARKS": "Bookmarks", "SEARCH": "Search", "FAVORITES": "Favorites",
    "BASSBOOST": "Bass+", "MEDIA": "Media",
    "SLEEP": "Sleep", "SUSPEND": "Suspend",
}


def display_name(raw: str) -> str:
    if raw in EXPLICIT:
        return EXPLICIT[raw]
    # 字母与数字键直接用字符
    if len(raw) == 1 and raw.isalnum():
        return raw
    # F1..F24
    if re.fullmatch(r"F\d{1,2}", raw):
        return raw
    # 小键盘数字
    if re.fullmatch(r"KP\d", raw):
        return "KP " + raw[2:]
    # 其余：下划线转空格、首字母大写，至少比 KEY_FOO_BAR 好读
    return raw.replace("_", " ").title()


def main() -> int:
    header = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else DEFAULT_HEADER)
    output = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "keynames.py")

    if not header.is_file():
        print(f"找不到内核头文件 {header}", file=sys.stderr)
        return 1

    text = header.read_text(encoding="utf-8", errors="replace")
    # 注意码值可能是十进制也可能是十六进制（KEY_* 用十进制，BTN_* 用 0x 十六进制），
    # 只吃十进制的话 BTN_* 会一个都解析不出来。
    value = r"(0[xX][0-9a-fA-F]+|\d+)"

    table: dict[int, str] = {}
    for matched in re.finditer(rf"^#define\s+KEY_([A-Z0-9_]+)\s+{value}\s*$", text, re.M):
        table[int(matched.group(2), 0)] = display_name(matched.group(1))

    # BTN_*（鼠标/手柄/触控板按键）单独收一份码值集合。
    # 不能用「码值 >= 256 就是鼠标键」这种区间判断 —— BTN_* 与 KEY_* 的码值区间
    # 是重叠的（BTN_TRIGGER_HAPPY 在 0x2c0，而 KEY_* 一直用到 0x2ff）。
    btn_codes = sorted({
        int(matched.group(2), 0)
        for matched in re.finditer(rf"^#define\s+BTN_([A-Z0-9_]+)\s+{value}\s*$", text, re.M)
    })

    if not table:
        print(f"{header} 里没解析出任何 KEY_* 定义", file=sys.stderr)
        return 1
    if not btn_codes:
        print(f"{header} 里没解析出任何 BTN_* 定义（过滤鼠标按键会失效）", file=sys.stderr)

    lines = [
        '"""键码 → 显示名对照表（自动生成，不要手改）。',
        "",
        f"来源：{header}",
        "生成器：scripts/keyboard/gen-keynames.py",
        '"""',
        "",
        "# fmt: off",
        "KEYNAMES: dict[int, str] = {",
    ]
    for code in sorted(table):
        lines.append(f"    {code}: {table[code]!r},")
    lines += ["}", "", "# BTN_* 的码值，用于把鼠标/手柄按键从按键显示里排除", "BTN_CODES: frozenset[int] = frozenset({"]
    for code in btn_codes:
        lines.append(f"    {code},")
    lines += ["})", "# fmt: on", ""]

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines), encoding="utf-8")
    print(f"已写出 {output}（{len(table)} 个键码）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
