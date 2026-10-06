"""调用仍在 bash 侧的安装器函数（迁移期的桥）。

包列表、部署清单这类东西 bash 侧还是权威，Python 侧只读不重写 —— 两边各存
一份，迟早漂移，而这台机器的 install 就是靠那些列表装包的。

⚠ 只调用**只读**函数。带副作用的（cmd_install / cmd_update / cmd_uninstall）
不许从这里进：它们各自带着快照与确认提示，绕过去等于拆掉安全网。
"""
from __future__ import annotations

import subprocess

from . import paths

# bash -c 的位置参数约定：$0 是占位名，$1 是仓库路径，其余是要调的函数与参数。
# source 掉输出：install.sh 被 source 时不跑 main，但 lib/95-tui.sh 顶层会调
# tput（失败也只是空串），不值得让那些噪音进 stderr。
_LOADER = 'source "$1/install.sh" >/dev/null 2>&1 || exit 1; shift; "$@"'


def call(func: str, *args: str) -> str:
    """source 安装器后调用 func(...)，返回 stdout（去掉尾部换行）。"""
    proc = subprocess.run(
        ['bash', '-c', _LOADER, 'dotctl-bashsrc', str(paths.repo()), func, *args],
        capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError(
            f'调用 bash 侧 {func}() 失败（退出码 {proc.returncode}）：{proc.stderr.strip()[:200]}')
    return proc.stdout.rstrip('\n')


def packages(kind: str) -> list[str]:
    """deps_collect <kind> 的结果，一行一个。

    「有的 *_pkgs() 把多个包写在一行」这件事 bash 侧的 deps_collect 已经处理过
    （见 lib/86-cmd-deps.sh 里那段 tr），这里直接用它的输出。
    """
    return [line for line in call('deps_collect', kind).splitlines() if line.strip()]
