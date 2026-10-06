"""交互确认，语义与 lib/20-bootstrap.sh 的 read_answer / confirm 一致。

这几个细节必须对齐，否则「非交互下不会误删」这条保证就没了：
  · stdin 是终端 → 正常阻塞等待，用户想看多久看多久
  · stdin 不是终端 → 最多等 3 秒；超时打印提示并按默认值（否）处理
  · EOF（管道读完）→ 不等待，也不报警，按默认值处理
"""
from __future__ import annotations

import select
import sys

from . import ui

DEFAULT_TIMEOUT = 3


def read_answer(timeout: int = DEFAULT_TIMEOUT) -> str:
    if sys.stdin.isatty():
        try:
            return sys.stdin.readline().strip()
        except (OSError, KeyboardInterrupt):
            return ''

    timed_out = False
    try:
        ready, _, _ = select.select([sys.stdin], [], [], timeout)
        timed_out = not ready
        answer = '' if timed_out else sys.stdin.readline().strip()
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
