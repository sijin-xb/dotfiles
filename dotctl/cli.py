"""dotctl 的命令行入口（`python3 -m dotctl <子命令> [参数]`）。

迁移进度表就写在 COMMANDS 里：在这里的命令由 Python 实现，不在的仍走 bash
（install.sh 分发）。迁完一个就从 lib/99-main.sh 的 case 与对应
lib/8x-cmd-*.sh 里把实现删掉，只留一行转发。
"""
from __future__ import annotations

import sys

from . import ui
from .commands import (archive, clean, deps, doctor, install, rollback,  # noqa: E402
                       status, theme, uninstall, update)

COMMANDS = {
    'status': status.run,
    'deps': deps.run,
    'theme': theme.run,
    'clean': clean.run,
    'doctor': doctor.run,
    'rollback': rollback.rollback,
    'restore': rollback.restore,
    'archive': archive.run,
    'uninstall': uninstall.run,
    'update': update.run,
    'install': install.run,
}

HELP = """dotctl —— dotfiles 安装器的 Python 侧

已迁移的子命令：
  status                当前部署状态一览（只读）
  deps                  依赖清单，--missing 只看缺口（只读）
  theme                 图标 / 光标 / GTK 主题的取值与一致性（只读）
  clean                 清理临时残留 / 自举缓存 / 旧快照 / 旧备份
  doctor                环境体检（只读）
  rollback / restore    从快照还原 $HOME（有副作用）
  archive               打包 rice 配置为 tar.gz（有副作用）
  uninstall             卸载 rice（可选先存档，有副作用）
  update                增量升级：只同步文件层（有副作用）
  install               完整安装（7 步，有副作用）

全部子命令都已迁到 Python。完整用法见 ./install.sh --help。
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
