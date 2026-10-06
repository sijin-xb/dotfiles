"""archive：把 rice 配置 / 状态 / 缓存打包成 tar.gz（有副作用）。

几处必须与 bash 版一致的地方：
  · 用户取消返回 **2**（不是 1）—— 调用方 cmd_uninstall 靠这个区分
    「用户拒绝存档」与「存档真的失败」，混淆会让用户以为已有备份就去删文件
  · 排除 `.local/state/dotfiles-backup/snapshots`：里面的快照覆盖的正是同一
    批路径，不排除会让包体积随安装次数接近平方增长
  · 一次成型（先 MANIFEST 后配置，用两个 -C）；GNU tar 对压缩归档不支持追加
  · --delete 的删除范围用 active_snap_paths（只删当前会话那套）
"""
from __future__ import annotations

import os
import shutil
import socket
import subprocess
import time
from pathlib import Path

from .. import bashsrc, fsutil, paths, prompt, tmpfiles, ui

EXCLUDE_SNAPSHOTS = '.local/state/dotfiles-backup/snapshots'
ARCHIVE_HELPERS = 'dotctl_archive_paths'

# ⚠ 这两个色码是**硬编码**的，刻意不用 ui.GREEN / ui.YELLOW。
#   照抄 bash 版：cmd_archive 里那两行 printf 直接写 `\033[1;32m✓\033[0m`，
#   绕过了 C_GREEN 的「非终端就关色」判定 —— 于是它的计划清单在管道 / 重定向
#   下照样带 ANSI（与 lib/10-util.sh 开头声明的规则相矛盾，是 bash 侧的不一致）。
#   迁移目标是逐字一致，所以先照抄；要修那个不一致应作为独立改动，
#   顺便把 bash 侧一起改掉。
_PLAN_OK = '\033[1;32m'
_PLAN_SKIP = '\033[1;33m'
_PLAN_OFF = '\033[0m'


def _help() -> str:
    return bashsrc.help_text()


def _now_ts() -> str:
    return time.strftime('%Y%m%d-%H%M%S')


def _numfmt(kb: int) -> str:
    """`numfmt --to=iec` 的输出；没有 numfmt 时退回「N KB」（与 bash 一致）。"""
    try:
        proc = subprocess.run(['numfmt', '--to=iec', f'{kb}K'],
                              capture_output=True, text=True, check=False)
    except OSError:
        return f'{kb} KB'
    out = proc.stdout.strip()
    return out if out else f'{kb} KB'


def _dir_kb(path: Path) -> int:
    try:
        proc = subprocess.run(['du', '-sk', str(path)], capture_output=True,
                              text=True, check=False)
        return int(proc.stdout.split()[0])
    except (OSError, ValueError, IndexError):
        return 0


def _write_manifest(target: Path, present: list[str], all_paths: list[str],
                    remaining: list[str]) -> None:
    """MANIFEST.txt 的内容。时间戳等每跑一次都会变，所以格式要逐字对齐 bash。"""
    lines = [
        "# sijin-xb's dotfiles archive MANIFEST",
        f'用户名      : {os.environ.get("USER", "unknown")}',
        f'时间戳      : {_iso_now()}',
        f'主机名      : {_hostname()}',
        f'Rice 版本  : {paths.rice_version()}',
        f'打包命令行  : {paths.self_name()} {" ".join(remaining)}',
        '',
        '源路径清单（相对 $HOME）：',
    ]
    for rel in all_paths:
        mark = 'PRESENT' if rel in present else 'MISSING'
        lines.append(f'  [{mark}]  {rel}')
    lines += [
        '',
        '注意：.local/state/dotfiles-backup/snapshots/ 已排除。',
        '      那些快照覆盖的正是同一批路径，包含进来会让本包体积',
        '      随安装/回档次数接近平方增长。需要历史快照请单独备份该目录。',
        '',
        '归档内实际包含的文件列表（前 50 项）：',
    ]
    lines += sorted(present)[:50]
    target.write_text('\n'.join(lines) + '\n')


def _iso_now() -> str:
    """`date -Iseconds` 的形状：2026-10-06T08:40:00+08:00。"""
    try:
        proc = subprocess.run(['date', '-Iseconds'], capture_output=True,
                              text=True, check=False)
        out = proc.stdout.strip()
        if out:
            return out
    except OSError:
        pass
    return time.strftime('%Y-%m-%dT%H:%M:%S%z')


def _hostname() -> str:
    try:
        return socket.gethostname() or 'unknown'
    except OSError:
        return 'unknown'


def _collect(all_paths: list[str]) -> tuple[list[str], int]:
    present: list[str] = []
    total_kb = 0
    home = paths.home()
    for rel in all_paths:
        target = home / rel
        if target.exists() or target.is_symlink():
            present.append(rel)
            total_kb += _dir_kb(target)
    return present, total_kb


def _print_plan(present: list[str], all_paths: list[str], out_path: Path,
                total_kb: int) -> None:
    print('-' * 70)
    print(f'  将打包 {len(present)} 个顶级路径，总大小约：{_numfmt(total_kb)}')
    print('  源路径清单（缺省自动跳过）：')
    for rel in all_paths:
        if rel in present:
            print(f'     {_PLAN_OK}✓{_PLAN_OFF} ~/{rel}')
        else:
            print(f'     {_PLAN_SKIP}·{_PLAN_OFF} ~/{rel} （缺失，跳过）')
    print(f'  输出文件：{out_path}')
    print('-' * 70)


def _run_tar(out_path: Path, manifest_dir: Path, list_file: Path) -> bool:
    """一次成型：先收 MANIFEST，再收 $HOME 下的配置。

    ⚠ 两个 -C 都必须绝对路径：GNU tar 的 -C 相对前一个 -C 解析。
    ⚠ --exclude 位置敏感，必须在 --files-from 之前。
    """
    home = paths.home()
    argv = ['tar', '--numeric-owner', '-pzcf', str(out_path),
            f'--exclude={EXCLUDE_SNAPSHOTS}',
            '-C', str(manifest_dir), 'MANIFEST.txt',
            '-C', str(home), f'--files-from={list_file}']
    try:
        proc = subprocess.run(argv, check=False)
    except OSError as exc:
        ui.warn(f'tar 执行失败：{exc}')
        return False
    return proc.returncode == 0


def run(argv: list[str]) -> int:
    out_path: Path | None = None
    do_delete = False

    while argv:
        arg = argv.pop(0)
        if arg == '-o':
            if not argv:
                ui.die(f'archive: -o 需要一个输出路径参数，例如：{paths.self_name()} archive -o ~/backup.tar.gz')
                return 1
            out_path = Path(argv.pop(0)).expanduser()
        elif arg.startswith('-o='):
            out_path = Path(arg[3:]).expanduser()
        elif arg == '--delete':
            do_delete = True
        elif arg in ('--help', '-h'):
            print(_help(), end='')
            return 0
        else:
            ui.warn(f'archive 未知参数: {arg}（已忽略）')

    if out_path is None:
        out_path = paths.home() / f'dotfiles-archive-{_now_ts()}.tar.gz'

    out_dir = out_path.parent
    if not out_dir.is_dir():
        ui.die(f'输出目录不存在：{out_dir}（先创建目录，或用 -o 指定别的路径）')
        return 1
    if not os.access(out_dir, os.W_OK):
        ui.die(f'输出目录不可写：{out_dir}')
        return 1

    bashsrc.call('ensure_dirs')

    all_paths = [line for line in bashsrc.call(ARCHIVE_HELPERS).splitlines() if line.strip()]
    # 列表文件在**收集阶段**就开（对应 bash 的 `tmp_list="$(mktmp)"`）。
    # 这不只是形式：$TMPRUN 会因此被提前建出来，而 tests 的 SIGINT 那节正是
    # 靠「确认提示还挂着时 run 目录已存在」来观察的。
    list_file = tmpfiles.mktmp()
    present, total_kb = _collect(all_paths)
    if not present:
        ui.warn('没有可打包的 rice 相关文件，退出。')
        list_file.unlink(missing_ok=True)
        return 1
    list_file.write_text('\n'.join(present) + '\n')

    _print_plan(present, all_paths, out_path, total_kb)

    # 2 = 用户主动取消，区别于 1 = 真的失败。调用方必须能区分（见模块 docstring）
    if prompt.confirm('确认开始打包？') != 0:
        ui.say('已取消打包，未写入任何文件。')
        return 2

    # 用 tmpfiles.mktmpd（= bash 的 mktmpd）：先建 $TMPRUN 再在里面开目录。
    # 不这么做的话 tests 的 SIGINT 那节观察不到 run 目录被建出来。
    tmpdir = tmpfiles.mktmpd()
    try:
        # ⚠ 第 4 个参数传空列表是**照抄 bash**：cmd_archive 的 while 循环把参数
        #   全 shift 掉了，轮到写 MANIFEST 时 `$*` 已经是空 —— 所以那一行永远只有
        #   `$0 `，看不到用户实际传的 -o / --delete。
        _write_manifest(tmpdir / 'MANIFEST.txt', present, all_paths, [])
        ui.say('打包中 ...')
        if not _run_tar(out_path, tmpdir, list_file):
            ui.warn('打包失败。')
            return 1
    finally:
        tmpfiles.cleanup(tmpdir)
        list_file.unlink(missing_ok=True)
    ui.say(f'打包完成 → {out_path} ({fsutil.du(out_path)})')

    if do_delete:
        # 不在这里补空行：bash 版那个 `echo` 与 uninstall_compositor_scope
        # 开头的 `echo` 之所以看起来是两个空行，是因为前者来自本进程、后者
        # 来自子进程。现在 call_streaming 会先 flush，两边各自一个换行，
        # 再补一个就多出来了（实测 diff 会指出来）。
        return _delete_scope()
    return 0


def _delete_scope() -> int:
    """--delete：删除范围用 active_snap_paths（另一套会话的配置原样保留）。"""
    print()
    bashsrc.call_streaming('uninstall_compositor_scope')
    del_paths = [line for line in bashsrc.call('active_snap_paths').splitlines() if line.strip()]
    del_paths += [line for line in bashsrc.call('dotctl_extra_paths').splitlines() if line.strip()]

    home = paths.home()
    ui.warn('--delete 模式：以下 rice 管理路径将在确认后删除（其他用户文件绝不触碰）：')
    for rel in del_paths:
        target = home / rel
        if target.exists() or target.is_symlink():
            print(f'     rm -rf ~/{rel}  ({fsutil.du(target, total=True)})')

    if prompt.confirm('⚠️  真的要删除吗？此操作不可恢复！') != 0:
        ui.say('已取消删除。')
        return 0

    for rel in del_paths:
        target = home / rel
        if target.exists() or target.is_symlink():
            shutil.rmtree(target, ignore_errors=True) if target.is_dir() and not target.is_symlink() \
                else target.unlink(missing_ok=True)
            print(f'     已删除 ~/{rel}')
    ui.say('--delete 清理完成。建议注销重新登录。')
    return 0
