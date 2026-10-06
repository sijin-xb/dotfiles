"""dotctl 的命令行入口（`python3 -m dotctl <子命令> [参数]`）。

迁移进度表就写在 COMMANDS 里：在这里的命令由 Python 实现，不在的仍走 bash
（install.sh 分发）。迁完一个就从 lib/99-main.sh 的 case 与对应
lib/8x-cmd-*.sh 里把实现删掉，只留一行转发。
"""
from __future__ import annotations

import sys

from . import ui
from .commands import deps, status

COMMANDS = {
    'status': status.run,
    'deps': deps.run,
}

HELP = """dotctl —— dotfiles 安装器的 Python 侧

已迁移的子命令：
  status                当前部署状态一览（只读）
  deps                  依赖清单，--missing 只看缺口（只读）

其余子命令（install / update / rollback / restore / archive / uninstall /
doctor / theme / clean）仍在 bash 侧，由 ./install.sh 分发。
完整用法见 ./install.sh --help。
"""


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv or argv[0] in ('-h', '--help'):
        print(HELP, end='')
        return 0
    cmd, rest = argv[0], argv[1:]
    handler = COMMANDS.get(cmd)
    if handler is None:
        ui.die(f'dotctl 尚未接管子命令 {cmd!r}（仍在 bash 侧），请用 ./install.sh {cmd}')
        return 2
    return handler(rest)


if __name__ == '__main__':
    sys.exit(main())
