#!/usr/bin/env python3
"""读 /dev/input/event*，把「当前按住了哪些键」按行输出成 JSON。

给 quickshell 的按键显示浮层用（services/KeycapDisplay.qml 起这个进程、
SplitParser 逐行读 stdout）。约定与 scripts/desktopLyrics/splayer-ws.py 一致：
外部脚本 → stdout 逐行 JSON → QML 解析。

设计要点：

* **只读，绝不 grab**。用 EVIOCGRAB 抢设备会让按键不再进到应用里 —— 那是
  键盘重映射工具的活，这里只需要旁观。所以直接读事件节点即可。
* **单线程 select 多路复用**，没有轮询、没有定时唤醒，空闲时进程完全睡着。
* **不区分左右修饰键**（左右 Ctrl 都报 Ctrl）：按键显示要的是用户看得懂的名字。
* **跳过鼠标按键**（BTN_* 即码值 ≥ 256）与自动重复（value == 2），
  否则鼠标一动、按住一个键不放都会刷屏。
* **设备热插拔**：读取出错就把该 fd 丢掉，并且每隔几秒重扫一次设备列表，
  插上外接键盘不用重启守护。

输出（每次「按住集合」变化时一行）：
    {"keys": ["Ctrl", "A"]}

权限：需要能读 /dev/input/event*（通常把用户加进 input 组即可）。
读不到任何设备时会在 stderr 说明原因后退出，QML 侧据此提示。
"""

from __future__ import annotations

import glob
import json
import os
import select
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from keynames import BTN_CODES, KEYNAMES  # noqa: E402  (与脚本同目录，随仓库提交)

# struct input_event { struct timeval time; __u16 type; __u16 code; __s32 value; }
# x86_64 上 timeval 是 16 字节，合计 24。
EVENT = struct.Struct("llHHi")
EVENT_SIZE = EVENT.size

EV_SYN = 0x00
EV_KEY = 0x01

KEY_RELEASE, KEY_PRESS, KEY_REPEAT = 0, 1, 2

# 重扫设备列表的间隔（秒）。select 超时用，空闲时不占 CPU。
RESCAN_INTERVAL = 5.0


def device_paths() -> list[str]:
    return sorted(glob.glob("/dev/input/event*"))


def parse_buffer(data: bytes, held: dict[int, str]) -> bool:
    """把一段 evdev 原始数据喂进 held，返回「按住集合」是否发生了变化。

    抽成独立函数是为了能确定性地测试：真实按键没法在测试里合成
    （ydotool 需要额外安装，uinput 需要 root），但伪造 input_event 字节很容易。
    """
    changed = False
    for offset in range(0, len(data) - EVENT_SIZE + 1, EVENT_SIZE):
        _, _, ev_type, code, value = EVENT.unpack_from(data, offset)
        if ev_type != EV_KEY or code in BTN_CODES:
            continue
        if value == KEY_REPEAT:
            continue
        if value == KEY_PRESS:
            label = KEYNAMES.get(code, f"code {code}")
            if held.get(code) != label:
                held[code] = label
                changed = True
        elif code in held:
            del held[code]
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


def main() -> int:
    opened = open_devices()
    if not opened:
        print(
            "读不到任何 /dev/input/event*。请确认当前用户在 input 组里：\n"
            "  sudo usermod -aG input $USER   # 之后重新登录\n"
            "可用 id -nG 检查。",
            file=sys.stderr,
        )
        return 1

    print(f"keycap-reader: 已接管 {len(opened)} 个输入设备", file=sys.stderr, flush=True)

    held: dict[int, str] = {}   # code -> 显示名，保持按下顺序
    last_line = ""

    def emit() -> None:
        """按住集合变化时才输出，避免重复行。"""
        nonlocal last_line
        line = json.dumps({"keys": list(held.values())}, ensure_ascii=False)
        if line != last_line:
            last_line = line
            print(line, flush=True)

    while True:
        if not opened:
            # 全部设备都掉了（比如切换 TTY 后回来），重开一次
            opened = open_devices()
            if not opened:
                return 1

        try:
            ready, _, _ = select.select(list(opened), [], [], RESCAN_INTERVAL)
        except InterruptedError:
            continue
        except OSError:
            close_all(opened)
            opened = open_devices()
            continue

        if not ready:
            # 超时：重扫设备列表，处理热插拔
            current = set(device_paths())
            known = set(opened.values())
            if current != known:
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
                # 设备消失时把它的按键从「按住」里清掉，否则会一直挂着
                held.clear()
                emit()
                continue

            if parse_buffer(data, held):
                emit()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(0)
