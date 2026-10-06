"""clean：清理临时残留、自举缓存、旧快照与旧备份。

默认只清 /tmp 里的安装残留（最安全）。要动快照/备份必须显式给选项 ——
那些是 rollback / restore 的退路，不该被一条「顺手清一下」的命令带走。
一律先列清单再确认，且支持 --dry-run。

输出与 lib/85-cmd-clean.sh 逐字一致。
"""
from __future__ import annotations

import os
import shutil
from pathlib import Path

from .. import fsutil, paths, prompt, ui

DEFAULT_KEEP = 3


def _help() -> str:
    me = paths.self_name()
    return f"""用法：{me} clean [选项]

清理安装残留与缓存。默认只清 /tmp 下的安装残留（最安全）。

选项：
  --cache            删自举缓存（{paths.repo_cache()}）
  --snapshots [N]    快照只保留最近 N 份（默认 {DEFAULT_KEEP}），其余删除
  --updates          删 {paths.backup_root()}/update-* 旧升级备份
  --all              上面三项全做（仍会先列清单再确认）
  -n, --dry-run      只列会删什么，一个字节都不删
  -h, --help         显示本帮助

⚠ 快照与备份是 rollback / restore 的退路，删了就回不去了 —— 所以它们
   不包含在默认行为里。
"""


def _tmp_dirs() -> list[Path]:
    """临时残留。排除当前进程自己的 run 目录 —— 那个由 install.sh 的 EXIT
    trap 负责，这里删掉会让本次运行的 mktemp 全部失效。"""
    base = Path(os.environ.get('TMPDIR') or '/tmp')
    own = os.environ.get('TMPRUN', '')
    if not base.is_dir():
        return []
    out = []
    for entry in sorted(base.glob('dotfiles-install.*')):
        if entry.is_dir() and str(entry) != own:
            out.append(entry)
    return out


def _old_snapshots(keep: int) -> list[Path]:
    root = paths.snap_root()
    if not root.is_dir():
        return []
    snaps = [p for p in root.glob('*.tar.gz') if p.is_file()]
    snaps.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return snaps[keep:]


def _old_updates() -> list[Path]:
    root = paths.backup_root()
    if not root.is_dir():
        return []
    return sorted(p for p in root.glob('update-*') if p.is_dir())


def _collect(dry: bool, do_cache: bool, do_snaps: bool, keep: int,
             do_updates: bool) -> tuple[list[Path], list[str]]:
    targets: list[Path] = []
    labels: list[str] = []
    for path in _tmp_dirs():
        targets.append(path)
        labels.append('临时残留')
    if do_cache and paths.repo_cache().is_dir():
        targets.append(paths.repo_cache())
        labels.append('自举缓存')
    if do_snaps:
        for path in _old_snapshots(keep):
            targets.append(path)
            labels.append('旧快照')
    if do_updates:
        for path in _old_updates():
            targets.append(path)
            labels.append('旧备份')
    return targets, labels


def run(argv: list[str]) -> int:
    dry = False
    do_tmp = True
    do_cache = do_snaps = do_updates = False
    keep = DEFAULT_KEEP

    while argv:
        arg = argv.pop(0)
        if arg in ('-n', '--dry-run'):
            dry = True
        elif arg == '--cache':
            do_cache = True
        elif arg == '--snapshots':
            do_snaps = True
            if argv and argv[0].isdigit():      # 可选数字：不写就保留默认份数
                keep = int(argv.pop(0))
        elif arg == '--updates':
            do_updates = True
        elif arg == '--all':
            do_cache = do_snaps = do_updates = True
        elif arg in ('-h', '--help'):
            print(_help(), end='')
            return 0
        else:
            ui.warn(f'clean: 未知选项 {arg}')
            return 2

    targets, labels = _collect(dry, do_cache, do_snaps, keep, do_updates)

    if not targets:
        ui.say('没有需要清理的东西')
        return 0

    print(f'将删除以下 {len(targets)} 项：')
    for label, path in zip(labels, targets):
        size = fsutil.du(path)
        # 按字节补位，与 bash 的 `printf '  [%s] %-7s %s\n'` 一致
        pad = max(0, 7 - len(size.encode()))
        print(f'  [{label}] {size}{" " * pad} {path}')

    if dry:
        print()
        ui.say('--dry-run：什么都没删')
        return 0

    rc = prompt.confirm(f'确认删除以上 {len(targets)} 项？')
    if rc != 0:
        return rc

    failed = 0
    for path in targets:
        try:
            if path.is_dir() and not path.is_symlink():
                shutil.rmtree(path)
            else:
                path.unlink()
        except OSError:
            ui.warn(f'删不掉：{path}')
            failed += 1
    ui.say(f'已清理 {len(targets) - failed} 项')
    return 1 if failed else 0
