"""调用仍在 bash 侧的安装器函数（迁移期的桥）。

包列表、部署清单这类东西 bash 侧还是权威，Python 侧只读不重写 —— 两边各存
一份，迟早漂移，而这台机器的 install 就是靠那些列表装包的。

⚠ 只调用**只读**函数。带副作用的（cmd_install / cmd_update / cmd_uninstall）
不许从这里进：它们各自带着快照与确认提示，绕过去等于拆掉安全网。
"""
from __future__ import annotations

import os
import subprocess
import sys

from . import paths

# bash -c 的位置参数约定：$0 是占位名（**不能**传安装器真实路径，见下），
# $1 是仓库路径，其余是要调的函数与参数。
#
# ⚠ $0 必须是无关的占位名，不能传安装器路径。install.sh 用它判定「是否直接
#   执行」：`[[ ${BASH_SOURCE[0]} == "${0}" ]]` —— source 时 BASH_SOURCE[0]
#   正是 install.sh 的路径，一旦 $0 也等于它，守卫就误判成「直接执行」，
#   顶层 main 立刻跑起来并把本次调用吃掉（实测：help_text 返回空、退出码 2）。
#   提示语里要用的调用者路径改由 DOTCTL_SELF 环境变量传下去，bash 侧
#   print_help 读的是 $0 —— 所以下面再 export 一份 DOTCTL_SELF 给不出效果，
#   真正的办法见 help_text()。
#
# ⚠ 子进程会**重新 source** install.sh，于是 BACKUP_ROOT / SNAP_ROOT /
#   STATE_DIR 会按子进程当时的 $HOME 重算 —— 而父进程（真正的安装器）用的是
#   source 时冻结的值。两者在「改了 HOME 再调函数」时会分叉（archive 的测试
#   就是这么踩到的：子进程按 empty-home 建出 dotfiles-backup，让本该「无可
#   打包路径」的场景变成有路径）。
#   所以这里把父进程的冻结值经环境变量传进去，source 之后覆盖掉重算的结果。
_FROZEN_VARS = ('DOTCTL_BACKUP_ROOT', 'DOTCTL_SNAP_ROOT', 'DOTCTL_STATE_DIR')

# DOTCTL_BACKUP_ROOT -> BACKUP_ROOT 等。写成 shell 片段，source 之后执行。
_PIN = '; '.join(
    f'if [ -n "${{{v}:-}}" ]; then {v[7:]}="${v}"; fi'
    for v in _FROZEN_VARS
)
_LOADER = f'source "$1/install.sh" >/dev/null 2>&1 || exit 1; {_PIN}; shift; "$@"'


def _bash_argv() -> list[str]:
    return ['bash', '-c', _LOADER, 'dotctl-bashsrc', str(paths.repo())]


def call(func: str, *args: str) -> str:
    """source 安装器后调用 func(...)，返回 stdout（去掉尾部换行）。"""
    proc = subprocess.run(
        [*_bash_argv(), func, *args],
        capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError(
            f'调用 bash 侧 {func}() 失败（退出码 {proc.returncode}）：{proc.stderr.strip()[:200]}')
    return proc.stdout.rstrip('\n')


def call_streaming(func: str, *args: str) -> bool:
    """同 call，但**不捕获**输出：bash 侧的进度与告警直接进用户终端。

    `snapshot_current` 会打「创建快照 …」「快照完成，大小：…」，
    `session_warning_if_running` 会打会话告警 —— 这些是给用户看的，
    捕获回来再由 Python 转发只会多一层出错的机会。

    返回 True 表示 bash 侧退出码为 0（注意：bash 函数 return 1 也会反映到
    这里的 False，调用方要按各自语义处理，别一律当异常）。
    """
    # ⚠ 必须先 flush 自己的 stdout：子进程直接写 fd 1，而 Python 的 stdout
    #   在管道 / 重定向下是块缓冲 —— 不 flush 的话子进程的输出会插到本进程
    #   尚未落盘的内容前面（archive --delete 的空行位置就是这么错的）。
    sys.stdout.flush()
    proc = subprocess.run([*_bash_argv(), func, *args], check=False)
    return proc.returncode == 0


def packages(kind: str) -> list[str]:
    """deps_collect <kind> 的结果，一行一个。

    「有的 *_pkgs() 把多个包写在一行」这件事 bash 侧的 deps_collect 已经处理过
    （见 lib/86-cmd-deps.sh 里那段 tr），这里直接用它的输出。
    """
    return [line for line in call('deps_collect', kind).splitlines() if line.strip()]


def help_text() -> str:
    """完整的 --help 文本（**保留**结尾换行）。

    `print_help` 同时被仍在 bash 侧的 update / archive / uninstall 与主分发
    使用，所以不能搬到 Python。已迁移的命令（rollback / restore 等）的 -h
    就取这一份，保证两边永远是同一段文字。

    调用者路径经 DOTCTL_SELF 传给 bash 侧（见 _LOADER 上面那段说明：$0 只能
    是占位名）。help 里 19 处「用法：$0 ...」都读这个变量。

    ⚠ 不能用 call()：它会把结尾换行 rstrip 掉，而 bash 的 heredoc 是带换行
    结尾的 —— 少一个换行，`-h` 的输出就与迁移前不一致（对照 diff 会指出来）。
    """
    proc = subprocess.run(
        [*_bash_argv(), 'print_help'],
        capture_output=True, text=True, check=False,
        env={**os.environ, 'DOTCTL_SELF': paths.self_name()})
    return proc.stdout
