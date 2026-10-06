"""doctor：环境体检（只读）。

定位：装之前/装之后想知道「这台机器到底缺什么」。只报告，不改任何东西 ——
补救命令打印出来由你决定跑不跑。

输出与 lib/84-cmd-doctor.sh 逐字一致。两处环境相关的值由 bash 侧递过来：
  · DOTCTL_BASH_VERSION —— 那一行「bash 5.3」取自 BASH_VERSINFO（未导出）
  · DOTCTL_SELF         —— 提示语里的 $0
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

from .. import bashsrc, paths, state, ui

TOOLCHAIN = ('git', 'sudo', 'pacman', 'python3', 'tar', 'curl')
PKG_TIMEOUT = 5


class Report:
    def __init__(self) -> None:
        self.warns = 0
        self.fails = 0

    def ok(self, msg: str) -> None:
        print(f'  {ui.GREEN}✓{ui.RESET} {msg}')

    def warn(self, msg: str) -> None:
        print(f'  {ui.YELLOW}!{ui.RESET} {msg}')
        self.warns += 1

    def bad(self, msg: str) -> None:
        print(f'  {ui.RED}✗{ui.RESET} {msg}')
        self.fails += 1

    @staticmethod
    def head(msg: str) -> None:
        print(f'\n{msg}')


def _help() -> str:
    return f"""用法：{paths.self_name()} doctor

体检当前环境并打印缺口，只读、不改任何东西。检查项：
  系统（发行版 / 是否 root）· 工具链（git、pacman、python3…）
  当前会话的合成器与 quickshell · 依赖包缺口 · QML 模块自检 · 备份目录可写
"""


def _installed(pkg: str) -> bool:
    try:
        return subprocess.run(['pacman', '-Q', pkg], stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, check=False).returncode == 0
    except OSError:
        return False


def _tilde(path: Path) -> str:
    r"""把 $HOME 前缀缩成 ~ —— bash 版用的是 ${cfg/#$HOME/\~}。"""
    home = str(paths.home())
    text = str(path)
    return '~' + text[len(home):] if text.startswith(home) else text


def _bash_version() -> str:
    return os.environ.get('DOTCTL_BASH_VERSION') or '未知'


def _run_doctor(report: Report) -> None:
    report.head('── 系统 ──')
    if Path('/etc/arch-release').is_file():
        report.ok('Arch 系发行版')
    else:
        report.bad('非 Arch 系（缺 /etc/arch-release）—— 本脚本的装包逻辑写死了 pacman')

    uid = os.getuid()
    if uid == 0:
        report.bad('以 root 运行 —— 请用普通用户，脚本会拒绝 root')
    else:
        report.ok(f'普通用户（uid {uid}）')
    report.ok(f'bash {_bash_version()}')

    report.head('── 工具链 ──')
    for tool in TOOLCHAIN:
        if shutil.which(tool):
            report.ok(tool)
        else:
            report.bad(f'{tool} 缺失')

    helper = next((h for h in ('paru', 'yay') if shutil.which(h)), '')
    if helper:
        report.ok(f'AUR helper: {helper}')
    else:
        report.warn('没有 paru / yay —— 装 AUR 包时会先自动装 yay')

    shell, comp = state.resolve_session()
    report.head(f'── 会话（{state.session_label(shell, comp)}）──')
    home = paths.home()
    if comp == 'niri':
        report.ok('niri 可用') if shutil.which('niri') else report.bad('niri 缺失')
        cfg = home / '.config/niri/config.kdl'
    else:
        report.ok('Hyprland 可用') if shutil.which('Hyprland') else report.bad('Hyprland 缺失')
        cfg = home / '.config/hypr/hyprland.lua'
    if cfg.exists():
        report.ok(f'配置入口 {_tilde(cfg)}')
    else:
        report.warn(f'配置入口不存在：{_tilde(cfg)}（还没装？）')

    if shell == 'dms':
        report.ok('dms 可用') if shutil.which('dms') else report.bad('dms 缺失')
    else:
        report.ok('quickshell（qs）可用') if shutil.which('qs') else report.bad('quickshell 缺失')
        if ((home / '.config/quickshell/end4-PC/shell.qml').exists()
                or (home / '.config/quickshell/caelestia/shell.qml').exists()):
            report.ok('shell 差异层已部署')
        else:
            report.warn(f'shell 差异层未部署（{shell}）')

    report.head('── 依赖包缺口 ──')
    missing: list[str] = []
    if shutil.which('pacman'):
        for kind in ('pacman', 'aur'):
            for pkg in bashsrc.packages(kind):
                if not _installed(pkg):
                    missing.append(pkg)
    if not missing:
        report.ok('本会话依赖齐全')
    else:
        report.warn(f'{len(missing)} 个包未安装：{" ".join(missing)}')
        print(f'     补齐：{paths.self_name()} update --with-packages（只补不卸）')

    report.head('── QML 模块自检 ──')
    checker = paths.repo() / 'check-qml-deps.py'
    if shell == 'dms':
        report.ok('dms 会话不需要 QML 模块自检')
    elif not checker.is_file():
        report.warn('check-qml-deps.py 不在仓库里，跳过')
    elif not shutil.which('python3'):
        report.warn('没有 python3，跳过（QML 自检是 Python 脚本）')
    else:
        try:
            proc = subprocess.run(['python3', str(checker), '--quiet'],
                                  capture_output=True, text=True, check=False)
        except OSError:
            report.warn('check-qml-deps.py 执行失败，跳过')
        else:
            if proc.returncode == 0:
                report.ok('QML 模块齐全')
            else:
                report.bad('QML 模块有缺口：')
                # bash 版是 `| sed 's/^/      /'`：空行也会被加上六个空格
                for line in (proc.stdout + proc.stderr).splitlines():
                    print(f'      {line}')

    report.head('── 备份目录 ──')
    backup = paths.backup_root()
    if os.access(backup, os.W_OK):
        report.ok(f'{backup} 可写')
    elif os.access(backup.parent, os.W_OK):
        report.ok(f'{backup} 尚不存在，父目录可写')
    else:
        report.bad(f'{backup} 不可写 —— snapshot / rollback 会失败')

    report.head('── 结论 ──')
    if report.fails == 0 and report.warns == 0:
        print('  一切正常。')
    else:
        print(f'  {report.warns} 项需要注意，{report.fails} 项必须处理。')


def run(argv: list[str]) -> int:
    if argv and argv[0] in ('-h', '--help'):
        print(_help(), end='')
        return 0
    if argv:
        ui.warn(f'doctor 不接受参数：{argv[0]}')
        return 2

    report = Report()
    _run_doctor(report)
    return 1 if report.fails else 0
