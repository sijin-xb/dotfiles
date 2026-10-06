"""uninstall：卸载 rice（可选先存档），删除受管理路径。

这是整个安装器里**唯一会递归删 $HOME 下路径**的命令，所以几处边界必须守住：
  · 只删 active_snap_paths + EXTRA_ARCHIVE_PATHS 里的项，其他个人文件不碰
  · 删除范围按会话过滤（另一套合成器 / shell 的配置原样保留）
  · 任一确认处答 n 都不得删除任何东西
  · 「用户拒绝存档」必须与「存档失败」区分开 —— 前者要再确认一次，
    否则用户会以为自己有备份

⚠ 范围选择与清单计算必须在**同一个 bash 进程**里完成（见 lib/15-python.sh
  的 dotctl_uninstall_plan）：那两个 scope 函数设的变量决定 active_snap_paths
  的输出，分两次 fork 会让过滤失效、误删另一套会话的配置。
"""
from __future__ import annotations

import shutil
import time
from pathlib import Path

from .. import bashsrc, paths, prompt, tmpfiles, ui

ARCHIVE_HELPERS_EXTRA = 'dotctl_extra_paths'
PLAN_HELPERS = 'dotctl_uninstall_plan'


def _help() -> str:
    return bashsrc.help_text()


def _now_ts() -> str:
    return time.strftime('%Y%m%d-%H%M%S')


def _read_plan(plan_file: Path) -> tuple[str, list[str]]:
    """解析 dotctl_uninstall_plan 写的文件：第一行 SCOPE=…，其余是路径。"""
    scope = ''
    rels: list[str] = []
    try:
        lines = plan_file.read_text().splitlines()
    except OSError:
        return scope, rels
    for line in lines:
        if line.startswith('SCOPE='):
            scope = line[len('SCOPE='):]
        elif line.strip():
            rels.append(line)
    return scope, rels


def _remove(rel: str) -> bool:
    """删一条相对 $HOME 的路径。返回 True 表示确实删了。

    ⚠ 存在性判断只用 exists()，与 bash 的 `[[ -e "$HOME/$p" ]]` 一致 ——
    两者对**断链符号链接**都返回假，所以这种项会被跳过、不打印「已删除」。
    加上 is_symlink() 会把断链也删掉，与迁移前不一致。
    """
    target = paths.home() / rel
    if not target.exists():
        return False
    try:
        if target.is_dir() and not target.is_symlink():
            shutil.rmtree(target)
        else:
            target.unlink()
    except OSError as exc:
        ui.warn(f'删不掉 ~/{rel}：{exc}')
        return False
    print(f'     已删除 ~/{rel}')
    return True


def run(argv: list[str]) -> int:
    if argv and argv[0] in ('-h', '--help'):
        print(_help(), end='')
        return 0
    if argv:
        ui.warn(f'uninstall 不接受参数，已忽略: {" ".join(argv)}')

    bashsrc.call('dotctl_ensure_frozen_dirs')
    print('卸载 rice 配置：建议先打包存档作为备份。')

    do_archive = prompt.confirm('是否先打包存档？') == 0
    if do_archive:
        archive_path = paths.home() / f'dotfiles-archive-uninstall-{_now_ts()}.tar.gz'
        # 复用已迁移的 archive 实现；返回码 2 = 用户在打包确认处取消
        from . import archive as archive_cmd
        arc_rc = archive_cmd.run(['-o', str(archive_path)])
        if arc_rc == 2:
            ui.warn('你取消了存档 —— 本次卸载**没有备份**。')
            if prompt.confirm('仍然继续卸载？') != 0:
                ui.say('已中止，未删除任何文件。')
                return 0
        elif arc_rc != 0:
            ui.warn('存档失败，将继续执行卸载（无备份）')

    # 选范围 + 算清单：一次 fork 完成（见模块 docstring）
    plan_file = tmpfiles.mktmp()
    try:
        # 提示要直接进终端、答案要从 stdin 读，所以不走 call（那会捕获 stdout）
        bashsrc.call_streaming(PLAN_HELPERS, str(plan_file))
        _scope, rels = _read_plan(plan_file)
    finally:
        plan_file.unlink(missing_ok=True)

    if prompt.confirm('确认删除 rice 相关路径？（合成器与 shell 配置只删上述范围；'
                      '不会删除其他个人文件）') != 0:
        return 0

    for rel in bashsrc.call(ARCHIVE_HELPERS_EXTRA).splitlines():
        if rel.strip():
            rels.append(rel.strip())

    for rel in rels:
        _remove(rel)

    ui.say('卸载完成。如果你还想保留 quickshell/hyprland 程序本身，请使用 pacman -Rns 手动卸载。')
    return 0
