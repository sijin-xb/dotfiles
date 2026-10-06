"""终端输出，与 lib/10-util.sh 的 say/warn/die 保持同一形状。

颜色规则也一致：设了 NO_COLOR 或 stdout 不是终端时全部关掉 —— 否则
`./install.sh status > out.txt` 会把 ANSI 码写进文件。

⚠ warn 走 stdout（不是 stderr），这是 bash 侧既有的行为，保持一致。
"""
from __future__ import annotations

import os
import sys

_COLOR = sys.stdout.isatty() and not os.environ.get('NO_COLOR')


def _c(code: str) -> str:
    return code if _COLOR else ''


GREEN = _c('\033[1;32m')
YELLOW = _c('\033[1;33m')
RED = _c('\033[1;31m')
RESET = _c('\033[0m')


def say(msg: str) -> None:
    # flush 是必须的：迁移后的命令会在中途 fork bash（bashsrc.call_streaming），
    # 子进程直接写 fd 1，而 Python 的 stdout 在管道下是块缓冲 —— 不 flush 就会
    # 出现「子进程的输出跑到本函数前面」的乱序（rollback 实测踩到）。
    print(f'{GREEN}==>{RESET} {msg}', flush=True)


def warn(msg: str) -> None:
    print(f'{YELLOW} ->{RESET} {msg}', flush=True)


def die(msg: str, code: int = 1) -> 'NoReturn':  # noqa: F821
    print(f'{RED}错误:{RESET} {msg}', file=sys.stderr)
    sys.exit(code)
