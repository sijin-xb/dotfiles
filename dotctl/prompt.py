"""交互确认，语义与 lib/20-bootstrap.sh 的 read_answer / confirm 一致。

这几个细节必须对齐，否则「非交互下不会误删」这条保证就没了：
  · stdin 是终端 → 正常阻塞等待，用户想看多久看多久
  · stdin 不是终端 → 最多等 3 秒；超时打印提示并按默认值（否）处理
  · EOF（管道读完）→ 不等待，也不报警，按默认值处理
"""
from __future__ import annotations

import os
import select
import sys

from . import ui

DEFAULT_TIMEOUT = 3


def _read_line_raw() -> str:
    """从 fd 0 逐字节读到换行，**不预读**。

    ⚠ 不能用 sys.stdin.readline()：它带缓冲，一次会把整块 stdin（例如管道里
    剩下的所有答案）读进用户态缓冲，之后 fork 出去的 bash 子进程就只剩 EOF。
    uninstall 实测踩到：先问「是否存档」读掉一行，接着 bash 侧的
    uninstall_compositor_scope / uninstall_shell_scope 拿不到答案，全走默认值
    （shell 范围恒为 end4-PC）。

    bash 的 read 内建就是逐字节读的（对管道也一样），这里对齐它的行为。
    """
    buf = bytearray()
    while True:
        try:
            ch = os.read(0, 1)
        except OSError:
            break
        if not ch or ch == b'\n':
            break
        buf += ch
    return buf.decode(errors='replace').rstrip('\r')


def read_answer(timeout: int = DEFAULT_TIMEOUT) -> str:
    if sys.stdin.isatty():
        try:
            return _read_line_raw()
        except (OSError, KeyboardInterrupt):
            return ''

    timed_out = False
    try:
        ready, _, _ = select.select([sys.stdin], [], [], timeout)
        timed_out = not ready
        answer = '' if timed_out else _read_line_raw()
    except (OSError, ValueError):
        answer = ''
    # bash 版在非终端分支里无条件补一个换行（提示语没带换行）
    print()
    if timed_out:
        ui.warn(f'非交互环境，{timeout} 秒内无输入，按默认值处理。')
    return answer


def confirm(prompt: str = '是否继续？', allow_back: bool = False) -> int:
    """0 = 确认，1 = 否，2 = 返回（仅 allow_back 时可能）。"""
    opts = '[y/N/b(返回)]' if allow_back else '[y/N]'
    print(f'{prompt} {opts} ', end='', flush=True)
    answer = read_answer()
    if answer.lower() in ('y', 'yes'):
        return 0
    if answer.lower() == 'b' and allow_back:
        return 2
    return 1
