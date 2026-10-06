"""deps：列出当前会话需要的依赖包（只读）。

包列表本身留在 bash 侧（lib/86-cmd-deps.sh 的 deps_collect → 各 *_pkgs()），
经 bashsrc 读取 —— 那是 install 装包用的同一份清单，Python 侧再接一份就会
出现「deps 说有、install 装的时候没有」这类漂移。

输出与 lib/86-cmd-deps.sh 逐字一致。
"""
from __future__ import annotations

import subprocess

from .. import bashsrc, paths, state, ui

# 与 bash 版的四组一一对应，顺序也一致
GROUPS: tuple[tuple[str, str], ...] = (
    ('官方仓库（pacman）', 'pacman'),
    ('AUR', 'aur'),
    ('字体（pacman）', 'fonts-pacman'),
    ('字体（AUR）', 'fonts-aur'),
)


def _help() -> str:
    me = paths.self_name()
    return f"""用法：{me} deps [选项]

列出当前会话需要的依赖包，按来源分组。只读，不装任何东西。

选项：
  --missing    只列**当前未安装**的包（用 pacman -Q 查）
  --pacman     只列官方仓库包
  --aur        只列 AUR 包
  --fonts      只列字体链（含 FONTS=0 时会跳过的那些）
  -h, --help   显示本帮助

装缺失项：{me} update --with-packages（只补不卸）或 {me} install
"""


def _installed(pkg: str) -> bool:
    """等价 bash 的 `pacman -Q "$p" >/dev/null 2>&1`。"""
    try:
        return subprocess.run(['pacman', '-Q', pkg], stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, check=False).returncode == 0
    except OSError:
        return False


def _emit_group(title: str, packages: list[str], only_missing: bool) -> None:
    rows = [p for p in packages if not (only_missing and _installed(p))]
    if not rows:                       # 空组整块不输出，与 bash 一致
        return
    print(f'{title}（{len(rows)}）')
    for pkg in rows:
        print(f'  {pkg}')
    print()


def run(argv: list[str]) -> int:
    only_missing = False
    want = 'all'
    while argv:
        arg = argv.pop(0)
        if arg in ('-h', '--help'):
            print(_help(), end='')
            return 0
        if arg == '--missing':
            only_missing = True
        elif arg == '--pacman':
            want = 'pacman'
        elif arg == '--aur':
            want = 'aur'
        elif arg == '--fonts':
            want = 'fonts'
        else:
            ui.warn(f'deps: 未知选项 {arg}')
            return 2

    shell, comp = state.resolve_session()
    print(f'会话: {state.session_label(shell, comp)}')
    if only_missing:
        print('过滤: 只看未安装')
    print()

    for title, kind in GROUPS:
        # want=pacman / aur 只取同名那一组；字体两组由 want=fonts 单独要
        if want == 'pacman' and kind != 'pacman':
            continue
        if want == 'aur' and kind != 'aur':
            continue
        if want == 'fonts' and not kind.startswith('fonts'):
            continue
        _emit_group(title, bashsrc.packages(kind), only_missing)

    if only_missing:
        print(f'以上为未安装项。补齐：{paths.self_name()} update --with-packages')
    else:
        print('以上为完整清单。只看缺口加 --missing。')
    return 0
