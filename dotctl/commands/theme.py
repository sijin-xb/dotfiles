"""theme：图标 / 光标 / GTK 主题在九个 sink 里的取值与一致性（只读）。

为什么要这个命令：图标主题散在 gsettings、GTK2/3/4、Qt5/Qt6、fuzzel、
xsettingsd、rofi 共九处，matugen 换壁纸时整批重写，手动改或某个程序自己
写回时又只改一处 —— 结果就是「文件管理器换了、fuzzel 没换」。

输出与 lib/87-cmd-theme.sh 逐字一致。
"""
from __future__ import annotations

import re
import shutil
import subprocess
from pathlib import Path

from .. import paths, ui

_MISSING = ('无此文件', '未设置')

# sed 表达式换成正则：每个 pattern 一个捕获组，取第一个匹配行 ——
# 与 bash 版 `sed -n '<expr>' file | head -1` 的语义一致。
_ICON = r'^gtk-icon-theme-name=(.+)$'
_ICON_QUOTED = r'^gtk-icon-theme-name="?([^"]*)"?$'
_CURSOR = r'^gtk-cursor-theme-name=(.+)$'
_GTK = r'^gtk-theme-name=(.+)$'
_INHERITS = r'^Inherits=(.+)$'
_QT = r'^icon_theme=(.+)$'
_FUZZEL = r'^icon-theme=(.+)$'
_XSETTINGSD = r'^Net/IconThemeName\s*"([^"]*)"'
_ROFI = r'icon-theme:\s*"([^"]*)"'


def _help() -> str:
    return f"""用法：{paths.self_name()} theme

打印图标 / 光标 / GTK 主题在各个 sink 里的当前取值，并标出一致性。

为什么要看这个：图标主题散在 gsettings、GTK2/3/4、Qt5/Qt6、fuzzel、
xsettingsd、rofi 共 9 处；matugen 换壁纸时会整批重写，手动改或某个程序
自己写回时又只改一处 —— 这里能把「哪一处没跟上」直接指出来。

只读，不改任何文件。
"""


def _read_kv(path: Path, pattern: str, fallback: str = '未设置') -> str:
    if not path.is_file():
        return '无此文件'
    try:
        text = path.read_text(errors='replace')
    except OSError:
        return '无此文件'
    for line in text.splitlines():
        found = re.search(pattern, line)
        if found:
            return found.group(1)
    return fallback


def _gsettings(schema: str, key: str) -> str:
    if shutil.which('gsettings') is None:
        return '无 gsettings'
    try:
        out = subprocess.run(['gsettings', 'get', schema, key],
                             capture_output=True, text=True, check=False)
    except OSError:
        return '读取失败'
    # 不检查 returncode：bash 版是 `gsettings get ... | tr -d "'"`，取不到值时
    # 管道仍然成功，于是输出空串。这里保持同一个形状。
    return out.stdout.strip().replace("'", '')


def _consistency(values: list[str]) -> str:
    uniq: list[str] = []
    for value in values:
        if not value or value in _MISSING:
            continue
        if value not in uniq:
            uniq.append(value)
    if not uniq:
        return f'{ui.YELLOW}没有任何一处设置了主题{ui.RESET}'
    if len(uniq) == 1:
        return f'{ui.GREEN}一致{ui.RESET}：{uniq[0]}'
    return f'{ui.YELLOW}不一致{ui.RESET}：{" / ".join(uniq)}'


def _row(label: str, value: str) -> None:
    # ⚠ 按**字节**补位，不是字符：bash 的 `printf '  %-22s %s'` 是 C 语义，
    #   中文标签（"一致性" 9 字节）会比 Python 的 `:<22`（3 字符）少补 6 格。
    pad = max(0, 22 - len(label.encode()))
    print(f'  {label}{" " * pad} {value}')


def run(argv: list[str]) -> int:
    if argv and argv[0] in ('-h', '--help'):
        print(_help(), end='')
        return 0
    if argv:
        ui.warn(f'theme 不接受参数：{argv[0]}')
        return 2

    home = paths.home()

    print('── 图标主题 ──')
    icon_sinks = [
        ('gsettings', lambda: _gsettings('org.gnome.desktop.interface', 'icon-theme')),
        ('gtk-3.0', lambda: _read_kv(home / '.config/gtk-3.0/settings.ini', _ICON)),
        ('gtk-4.0', lambda: _read_kv(home / '.config/gtk-4.0/settings.ini', _ICON)),
        ('gtk-2.0', lambda: _read_kv(home / '.gtkrc-2.0', _ICON_QUOTED)),
        ('qt5ct', lambda: _read_kv(home / '.config/qt5ct/qt5ct.conf', _QT)),
        ('qt6ct', lambda: _read_kv(home / '.config/qt6ct/qt6ct.conf', _QT)),
        ('fuzzel', lambda: _read_kv(home / '.config/fuzzel/fuzzel.ini', _FUZZEL)),
        ('xsettingsd', lambda: _read_kv(home / '.config/xsettingsd/xsettingsd.conf', _XSETTINGSD)),
        ('rofi', lambda: _read_kv(home / '.config/rofi/themes/icons.rasi', _ROFI)),
    ]
    icon_values = []
    for label, read in icon_sinks:
        value = read()
        icon_values.append(value)
        _row(label, value)
    _row('一致性', _consistency(icon_values))

    print()
    print('── 光标主题 ──')
    cursor_sinks = [
        ('gsettings', lambda: _gsettings('org.gnome.desktop.interface', 'cursor-theme')),
        ('gtk-3.0', lambda: _read_kv(home / '.config/gtk-3.0/settings.ini', _CURSOR)),
        ('gtk-4.0', lambda: _read_kv(home / '.config/gtk-4.0/settings.ini', _CURSOR)),
        ('~/.icons/default', lambda: _read_kv(home / '.icons/default/index.theme', _INHERITS)),
        ('icons/default', lambda: _read_kv(home / '.local/share/icons/default/index.theme', _INHERITS)),
    ]
    cursor_values = []
    for label, read in cursor_sinks:
        value = read()
        cursor_values.append(value)
        _row(label, value)
    _row('一致性', _consistency(cursor_values))

    print()
    print('── GTK 主题 ──')
    _row('gsettings', _gsettings('org.gnome.desktop.interface', 'gtk-theme'))
    _row('gtk-3.0', _read_kv(home / '.config/gtk-3.0/settings.ini', _GTK))
    _row('gtk-4.0', _read_kv(home / '.config/gtk-4.0/settings.ini', _GTK))

    print()
    print('提示：图标主题由 matugen 的 [templates.gtk-folder] 在换壁纸时整批重写；')
    print('      手动改过某一处的话，下次换壁纸会被它拉回统一值。')
    return 0
