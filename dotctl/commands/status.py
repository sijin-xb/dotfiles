"""status：当前部署状态一览（只读）。

输出与 lib/83-cmd-status.sh 逐字一致 —— 迁移期两边并存，漂移了把两条命令
的输出 diff 一下就看得出来。

标签后手写空格而不是用 %-Ns：printf 与 Python 的格式化都按**字符数**补位，
中文是双宽，用它们对齐会参差不齐。
"""
from __future__ import annotations

import subprocess
from pathlib import Path

from .. import paths, state, ui

HELP = """用法：./install.sh status

打印当前部署状态，只读、不写任何文件：
  会话 / 部署清单条目数 / 上次部署时间与 revision / 仓库工作区状态 /
  快照数量与最近一份 / 备份目录占用
"""


def _du(path: Path, *, total: bool = False) -> str:
    """`du -h` / `du -sh` 的第一列。自己递归求和会在几万个文件的备份目录上
    慢一个数量级，这里就用 du 本身。"""
    flag = '-sh' if total else '-h'
    try:
        out = subprocess.run(['du', flag, str(path)], capture_output=True, text=True, check=False)
        return out.stdout.split()[0]
    except (OSError, IndexError):
        return '?'


def _git(*args: str) -> str:
    try:
        out = subprocess.run(['git', '-C', str(paths.repo()), *args],
                             capture_output=True, text=True, check=False)
    except OSError:
        return ''
    return out.stdout.strip() if out.returncode == 0 else ''


def run(argv: list[str]) -> int:
    if argv and argv[0] in ('-h', '--help'):
        print(HELP, end='')
        return 0
    if argv:
        ui.warn(f'status 不接受参数：{argv[0]}')
        return 2

    shell, comp = state.resolve_session()
    print(f'会话        {state.session_label(shell, comp)}')

    manifest = state.manifest_file(shell, comp)
    try:
        text = manifest.read_text()
    except OSError:
        print('部署清单    无（这台机器没跑过 install，或清单属于别的会话）')
    else:
        # 用 count('\n') 而不是 splitlines()：前者等价 `wc -l`，
        # 文件末尾没换行时两者会差一行。
        print(f'部署清单    {manifest.name} · {text.count(chr(10))} 项')

    rev = state.read_revision(shell, comp)
    if rev:
        print('上次部署    {}（revision {} · {} · 当时工作区改动 {} 项）'.format(
            rev.get('time', '未知'), rev.get('revision', '?'),
            rev.get('branch', '?'), rev.get('dirty', '?')))
    else:
        print('上次部署    无记录')

    if _git('rev-parse', '--short', 'HEAD'):
        dirty = len(_git('status', '--porcelain').splitlines())
        print(f'仓库        {paths.repo()} · {paths.rice_version()} · '
              f'当前 revision {_git("rev-parse", "--short", "HEAD")}（工作区改动 {dirty} 项）')
    else:
        print(f'仓库        {paths.repo()} · {paths.rice_version()}（非 git 检出）')

    if paths.snap_root().is_dir():
        snaps = sorted((p for p in paths.snap_root().glob('*.tar.gz') if p.is_file()),
                       key=lambda p: p.stat().st_mtime, reverse=True)
    else:
        snaps = []
    if snaps:
        print(f'快照        {len(snaps)} 份 · 最近 {snaps[0].name}（{_du(snaps[0])}）')
    else:
        print('快照        0 份')

    if paths.backup_root().is_dir():
        print(f'备份占用    {_du(paths.backup_root(), total=True)}（{paths.backup_root()}）')
    else:
        print(f'备份占用    无（{paths.backup_root()} 不存在）')
    return 0
