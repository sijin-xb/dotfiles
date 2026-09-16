#!/usr/bin/env python3
"""读 /dev/input/event*，输出「当前按住了什么」和「已经打出了什么」。

给 quickshell 的按键显示浮层用（services/KeycapDisplay.qml 起这个进程、
SplitParser 逐行读 stdout）。约定与 scripts/desktopLyrics/splayer-ws.py 一致：
外部脚本 → stdout 逐行 JSON → QML 解析。

输出（每次状态变化一行）：
    {"keys": ["Ctrl", "Shift"], "text": "hello wor"}

    keys —— 需要以键帽形式展示的键：修饰键，以及「按住 Ctrl/Alt/Super 时」的组合键、
            方向键 / F 键这类不可打印键。
    text —— 已经打出来的可见文本（可读的那种）。可打印字符不进 keys，而是追加到这里，
            否则一个单词会被拆成一堆单独的键帽，根本读不出来。

为什么不把字母放进 keys：按键显示适合看快捷键，但打字时「h 闪一下、e 闪一下」
永远读不出你打的是什么。两种需求要分开满足。

其它设计要点：

* **只读，绝不 grab**。用 EVIOCGRAB 抢设备会让按键不再进到应用里 —— 那是键盘
  重映射工具的活，这里只需要旁观。
* **单线程 select 多路复用**，没有轮询。只有在「屏幕上还有文本」时才用 0.5 秒的
  select 超时去检查该不该清空文本；没有文本时完全睡着。
* **字符映射按 US 布局**（本机 kb_layout = us）。evdev 给的是键码不是字符，
  要还原出「打了什么字」必须有一张布局表；非 US 布局下字符会不对，
  所以下面有 LAYOUT 常量标注清楚，换布局时改这里。
* **跳过鼠标按键**（BTN_*，码值集合由内核头文件生成）与自动重复（value == 2）。
* **设备热插拔**：读取出错就丢掉该 fd，并每隔几秒重扫设备列表。

权限：需要能读 /dev/input/event*（通常把用户加进 input 组即可）。
"""

from __future__ import annotations

import glob
import json
import os
import select
import struct
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from keynames import BTN_CODES, KEYNAMES  # noqa: E402  (与脚本同目录，随仓库提交)

# struct input_event { struct timeval time; __u16 type; __u16 code; __s32 value; }
# x86_64 上 timeval 是 16 字节，合计 24。
EVENT = struct.Struct("llHHi")
EVENT_SIZE = EVENT.size

EV_SYN = 0x00
EV_KEY = 0x01

KEY_RELEASE, KEY_PRESS, KEY_REPEAT = 0, 1, 2

# 重扫设备列表的间隔（秒）
RESCAN_INTERVAL = 5.0
# 有文本待清空时的检查间隔（秒）。只在「屏幕上还有字」时才这么频繁地醒。
TEXT_IDLE_TICK = 0.5

# ── 键码常量（与 linux/input-event-codes.h 一致） ──────────────────────
KEY_ESC = 1
KEY_BACKSPACE = 14
KEY_TAB = 15
KEY_ENTER = 28
KEY_KPENTER = 96
KEY_LEFTCTRL, KEY_RIGHTCTRL = 29, 97
KEY_LEFTSHIFT, KEY_RIGHTSHIFT = 42, 54
KEY_LEFTALT, KEY_RIGHTALT = 56, 100
KEY_LEFTMETA, KEY_RIGHTMETA = 125, 126
KEY_CAPSLOCK = 58

MODIFIER_CODES = {
    KEY_LEFTCTRL, KEY_RIGHTCTRL,
    KEY_LEFTSHIFT, KEY_RIGHTSHIFT,
    KEY_LEFTALT, KEY_RIGHTALT,
    KEY_LEFTMETA, KEY_RIGHTMETA,
}
SHIFT_CODES = {KEY_LEFTSHIFT, KEY_RIGHTSHIFT}
# 按住这些键时，别的键算「组合键」，只显示键帽、不进文本
COMMAND_CODES = {
    KEY_LEFTCTRL, KEY_RIGHTCTRL,
    KEY_LEFTALT, KEY_RIGHTALT,
    KEY_LEFTMETA, KEY_RIGHTMETA,
}
# 锁键不当作「按住」展示，只影响大小写
LOCK_CODES = {KEY_CAPSLOCK}

# ── US 布局字符表：键码 → (无 Shift, 有 Shift) ─────────────────────────
# 换键盘布局时改这里。非 US 布局下文本会是错的，所以布局不匹配时
# 建议用 --no-text 只显示键帽（KeycapDisplay 会根据配置传这个开关）。
LAYOUT = "us"
US_MAP: dict[int, tuple[str, str]] = {
    2: ("1", "!"), 3: ("2", "@"), 4: ("3", "#"), 5: ("4", "$"), 6: ("5", "%"),
    7: ("6", "^"), 8: ("7", "&"), 9: ("8", "*"), 10: ("9", "("), 11: ("0", ")"),
    12: ("-", "_"), 13: ("=", "+"),
    16: ("q", "Q"), 17: ("w", "W"), 18: ("e", "E"), 19: ("r", "R"), 20: ("t", "T"),
    21: ("y", "Y"), 22: ("u", "U"), 23: ("i", "I"), 24: ("o", "O"), 25: ("p", "P"),
    26: ("[", "{"), 27: ("]", "}"),
    30: ("a", "A"), 31: ("s", "S"), 32: ("d", "D"), 33: ("f", "F"), 34: ("g", "G"),
    35: ("h", "H"), 36: ("j", "J"), 37: ("k", "K"), 38: ("l", "L"), 39: (";", ":"),
    40: ("'", '"'), 41: ("`", "~"), 43: ("\\", "|"),
    44: ("z", "Z"), 45: ("x", "X"), 46: ("c", "C"), 47: ("v", "V"), 48: ("b", "B"),
    49: ("n", "N"), 50: ("m", "M"), 51: (",", "<"), 52: (".", ">"), 53: ("/", "?"),
    57: (" ", " "),
    # 小键盘
    71: ("7", "7"), 72: ("8", "8"), 73: ("9", "9"), 74: ("-", "-"), 75: ("4", "4"),
    76: ("5", "5"), 77: ("6", "6"), 78: ("+", "+"), 79: ("1", "1"), 80: ("2", "2"),
    81: ("3", "3"), 82: ("0", "0"), 83: (".", "."), 98: ("/", "/"),
}

LETTER_CODES = {c for c, pair in US_MAP.items() if pair[0].isalpha()}


class Session:
    """按键与文本的累积状态。

    抽成类是为了能确定性地测试：真实按键没法在测试里合成
    （ydotool 需要额外安装，uinput 需要 root），但伪造 input_event 字节很容易。
    """

    def __init__(self, max_text: int = 48, text_idle: float = 2.5, text_enabled: bool = True):
        self.held: dict[int, str] = {}       # 需要显示成键帽的键
        self.text: list[str] = []
        self.max_text = max_text
        self.text_idle = text_idle
        self.text_enabled = text_enabled
        self.last_input_at = 0.0
        # 注意必须是实例属性：可变对象写成类属性会被所有实例共享
        self._pressed_mods: set[int] = set()
        self._locks: set[int] = set()

    # ── 供外部读取的快照 ──────────────────────────────────────────────
    def keys(self) -> list[str]:
        return list(self.held.values())

    def text_value(self) -> str:
        return "".join(self.text)

    def snapshot(self) -> str:
        return json.dumps(
            {"keys": self.keys(), "text": self.text_value()},
            ensure_ascii=False,
        )

    # ── 修饰键状态 ────────────────────────────────────────────────────
    def _shift(self) -> bool:
        return any(code in self.held or code in self._pressed_mods for code in SHIFT_CODES)

    def _caps(self) -> bool:
        return KEY_CAPSLOCK in self._locks

    def _command(self) -> bool:
        return any(code in self._pressed_mods for code in COMMAND_CODES)

    def _char_for(self, code: int) -> str | None:
        pair = US_MAP.get(code)
        if pair is None:
            return None
        plain, shifted = pair
        upper = self._shift() != self._caps() if code in LETTER_CODES else self._shift()
        return shifted if upper else plain

    # ── 事件入口 ──────────────────────────────────────────────────────
    def handle(self, code: int, value: int) -> bool:
        """处理一个按键事件，返回快照是否变化。"""
        if value == KEY_REPEAT:
            # 自动重复：文本不要重复追加（按住 a 不该出 aaaa）
            return False

        if value == KEY_PRESS:
            self.last_input_at = time.monotonic()
            return self._on_press(code)
        return self._on_release(code)

    def _on_press(self, code: int) -> bool:
        if code in MODIFIER_CODES:
            self._pressed_mods.add(code)
            label = KEYNAMES.get(code, f"code {code}")
            if self.held.get(code) == label:
                return False
            self.held[code] = label
            return True

        if code in LOCK_CODES:
            if code in self._locks:
                self._locks.discard(code)
            else:
                self._locks.add(code)
            return False  # 锁键不展示，只影响后续大小写

        # 组合键（Ctrl / Alt / Super 按住时）：整体当键帽显示，不进文本
        if self._command():
            label = KEYNAMES.get(code, f"code {code}")
            if self.held.get(code) == label:
                return False
            self.held[code] = label
            return True

        if not self.text_enabled:
            label = KEYNAMES.get(code, f"code {code}")
            if self.held.get(code) == label:
                return False
            self.held[code] = label
            return True

        # 文本编辑类按键
        if code == KEY_BACKSPACE:
            if self.text:
                self.text.pop()
                return True
            return False
        if code == KEY_ESC:
            if self.text:
                self.text.clear()
                return True
            return False
        if code in (KEY_ENTER, KEY_KPENTER):
            # 换行在单行浮层里没意义，当空格断词用
            return self._append(" ")

        char = self._char_for(code)
        if char is not None:
            return self._append(char)

        # 其余不可打印键（方向键 / F 键 / Home 等）走键帽
        label = KEYNAMES.get(code, f"code {code}")
        if self.held.get(code) == label:
            return False
        self.held[code] = label
        return True

    def _on_release(self, code: int) -> bool:
        self._pressed_mods.discard(code)
        if code in self.held:
            del self.held[code]
            return True
        return False

    def _append(self, char: str) -> bool:
        self.text.append(char)
        # 超长就丢最老的，避免浮层无限变宽
        if len(self.text) > self.max_text:
            del self.text[: len(self.text) - self.max_text]
        return True

    def expire_text_if_idle(self, now: float) -> bool:
        """闲置超时后清空文本。返回快照是否变化。"""
        if not self.text:
            return False
        if now - self.last_input_at < self.text_idle:
            return False
        self.text.clear()
        return True

    def reset(self) -> None:
        self.held.clear()
        self.text.clear()
        self._pressed_mods.clear()
        self._locks.clear()


def device_paths() -> list[str]:
    return sorted(glob.glob("/dev/input/event*"))


def parse_buffer(data: bytes, session: Session) -> bool:
    """把一段 evdev 原始数据喂进 session，返回快照是否变化。

    抽成独立函数是为了能确定性地测试：真实按键没法在测试里合成，
    但伪造 input_event 字节很容易。
    """
    changed = False
    for offset in range(0, len(data) - EVENT_SIZE + 1, EVENT_SIZE):
        _, _, ev_type, code, value = EVENT.unpack_from(data, offset)
        if ev_type != EV_KEY or code in BTN_CODES:
            continue
        if session.handle(code, value):
            changed = True
    return changed


def make_event(code: int, value: int, ev_type: int = EV_KEY) -> bytes:
    """构造一个 input_event，仅供测试使用。"""
    return EVENT.pack(0, 0, ev_type, code, value)


def open_devices() -> dict[int, str]:
    """打开所有能读的事件节点，返回 {fd: 路径}。读不到的静默跳过。"""
    opened: dict[int, str] = {}
    for path in device_paths():
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        except OSError:
            continue
        opened[fd] = path
    return opened


def close_all(opened: dict[int, str]) -> None:
    for fd in list(opened):
        try:
            os.close(fd)
        except OSError:
            pass
    opened.clear()


def parse_args(argv: list[str]) -> dict:
    """极简参数解析（只有三个开关，不值得引 argparse）。

    --no-text        只显示键帽，不做文本累积（非 US 布局时建议打开）
    --text-idle N    停止输入多少秒后清空文本（默认 2.5）
    --max-text N     文本缓冲区上限（默认 48）
    """
    options = {"text_enabled": True, "text_idle": 2.5, "max_text": 48}
    index = 0
    while index < len(argv):
        arg = argv[index]
        if arg == "--no-text":
            options["text_enabled"] = False
        elif arg == "--text-idle" and index + 1 < len(argv):
            index += 1
            options["text_idle"] = max(0.5, float(argv[index]))
        elif arg == "--max-text" and index + 1 < len(argv):
            index += 1
            options["max_text"] = max(4, int(argv[index]))
        index += 1
    return options


def main() -> int:
    options = parse_args(sys.argv[1:])
    session = Session(
        max_text=options["max_text"],
        text_idle=options["text_idle"],
        text_enabled=options["text_enabled"],
    )

    opened = open_devices()
    if not opened:
        # 第一行是给 QML 用的稳定错误码（界面据此翻译成本地语言），
        # 以 # 开头的后续行是给人手工运行本脚本时看的提示。
        print("ERROR:NO_INPUT_DEVICES", file=sys.stderr)
        print("# 读不到任何 /dev/input/event*。请确认当前用户在 input 组里：", file=sys.stderr)
        print("#   sudo usermod -aG input $USER   # 之后重新登录", file=sys.stderr)
        print("# 可用 id -nG 检查。", file=sys.stderr)
        return 1

    print(f"keycap-reader: 已接管 {len(opened)} 个输入设备", file=sys.stderr, flush=True)

    last_line = ""

    def emit() -> None:
        """快照变化时才输出，避免重复行。"""
        nonlocal last_line
        line = session.snapshot()
        if line != last_line:
            last_line = line
            print(line, flush=True)

    while True:
        if not opened:
            # 全部设备都掉了（比如切换 TTY 后回来），重开一次
            opened = open_devices()
            if not opened:
                return 1

        # 有文本待清空时用短超时，否则长睡 —— 空闲时不占 CPU
        tick = TEXT_IDLE_TICK if session.text else RESCAN_INTERVAL

        try:
            ready, _, _ = select.select(list(opened), [], [], tick)
        except InterruptedError:
            continue
        except OSError:
            close_all(opened)
            opened = open_devices()
            continue

        if not ready:
            if session.expire_text_if_idle(time.monotonic()):
                emit()
            # 顺便重扫设备列表，处理热插拔
            if set(device_paths()) != set(opened.values()):
                close_all(opened)
                opened = open_devices()
            continue

        for fd in ready:
            try:
                data = os.read(fd, EVENT_SIZE * 64)
            except OSError:
                # 设备被拔了 / 权限变了，丢掉这个 fd
                try:
                    os.close(fd)
                except OSError:
                    pass
                opened.pop(fd, None)
                # 设备消失时把状态清掉，否则键帽/文本会一直挂着
                session.reset()
                emit()
                continue

            if parse_buffer(data, session):
                emit()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(0)
