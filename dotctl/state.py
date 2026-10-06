"""部署状态的读取侧（对应 lib/40-manifest.sh 与 lib/83-cmd-status.sh 的读逻辑）。

⚠ `deployed-*` 文件名里的 shell / compositor 是**部署时**用的会话，不是此刻
正在跑的会话 —— 机器上装的是哪套，它就记哪套。所以 status 优先信这些文件，
环境变量只在没有部署记录时才拿来推断。
"""
from __future__ import annotations

import os
from pathlib import Path

from . import paths, ui

# SESSION 预设值 → (QS_SHELL, COMPOSITOR)，与 lib/50-session.sh 的 case 对齐。
SESSION_PRESETS: dict[str, tuple[str, str]] = {
    'end4pc': ('end4-pC', 'hyprland'),
    'caelestia': ('caelestia', 'hyprland'),
    'dms': ('dms', 'niri'),
}

SESSION_LABELS: dict[tuple[str, str], str] = {
    ('end4-pC', 'hyprland'): 'end4pc（Hyprland + quickshell end4-PC）',
    ('caelestia', 'hyprland'): 'caelestia（Hyprland + caelestia shell）',
    ('dms', 'niri'): 'dms（niri + DankMaterialShell）',
}

DEFAULT_SESSION = SESSION_PRESETS['end4pc']


def session_file() -> Path:
    return paths.state_dir() / 'deployed-session'


def revision_file(shell: str, comp: str) -> Path:
    return paths.state_dir() / f'deployed-revision-{shell}-{comp}'


def manifest_file(shell: str, comp: str) -> Path:
    return paths.state_dir() / f'deployed-{shell}-{comp}.tsv'


def session_from_env() -> tuple[str, str]:
    raw = os.environ.get('SESSION', '')
    preset = SESSION_PRESETS.get(raw)
    if preset:
        return preset
    if raw:
        ui.warn(f'未知的 SESSION 预设值 {raw!r}（合法：end4pc / caelestia / dms），按默认 end4pc 处理')
    return DEFAULT_SESSION


def resolve_session() -> tuple[str, str]:
    """(QS_SHELL, COMPOSITOR)：部署记录优先，其次环境变量，最后默认。"""
    try:
        raw = session_file().read_text().strip()
    except OSError:
        raw = ''
    if '|' in raw:
        shell, comp = raw.split('|', 1)
        return shell.strip(), comp.strip()
    return session_from_env()


def session_label(shell: str, comp: str) -> str:
    return SESSION_LABELS.get((shell, comp), f'{shell or "未知"} + {comp or "未知"}')


def read_revision(shell: str, comp: str) -> dict[str, str]:
    """读 deployed-revision-* 的 key=value；文件不存在就返回空 dict。"""
    out: dict[str, str] = {}
    try:
        text = revision_file(shell, comp).read_text()
    except OSError:
        return out
    for line in text.splitlines():
        if '=' in line:
            key, value = line.split('=', 1)
            out[key.strip()] = value.strip()
    return out
