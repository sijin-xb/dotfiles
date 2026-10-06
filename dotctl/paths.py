"""路径与常量。

与 lib/00-env.sh 是同一套取值 —— bash 侧还没迁完，两边同时在用，
改一处必须改另一处（迁移完成后 lib/00-env.sh 会消失）。

一律走函数而不是模块级常量：测试要用临时 HOME 覆盖，而常量在 import 那一刻
就定死了，函数每次读环境才有得测。
"""
from __future__ import annotations

import os
from pathlib import Path


def home() -> Path:
    return Path(os.environ.get('HOME') or Path.home())


def repo() -> Path:
    """仓库根：本包就在仓库里，用 __file__ 往上推，不看 cwd ——
    安装器可以从任意目录被调用（自举模式下 cwd 甚至是 /）。"""
    return Path(__file__).resolve().parent.parent


def _frozen(env_key: str, fallback: Path) -> Path:
    """优先用 bash 侧传下来的值（见 lib/15-python.sh 的说明）。

    bash 的 BACKUP_ROOT / SNAP_ROOT / STATE_DIR 是 source 时算好的常量，
    之后不随 $HOME 变；直接按 $HOME 动态推会在「改 HOME 再调函数」的场景下
    与 bash 不一致。
    """
    raw = os.environ.get(env_key)
    return Path(raw) if raw else fallback


def backup_root() -> Path:
    return _frozen('DOTCTL_BACKUP_ROOT', home() / '.local/state/dotfiles-backup')


def snap_root() -> Path:
    return _frozen('DOTCTL_SNAP_ROOT', backup_root() / 'snapshots')


def state_dir() -> Path:
    return _frozen('DOTCTL_STATE_DIR', backup_root() / 'state')


def repo_url() -> str:
    return os.environ.get('DOTFILES_REPO_URL', 'https://github.com/sijin-xb/dotfiles.git')


def repo_cache() -> Path:
    return Path(os.environ.get('DOTFILES_SRC_DIR') or home() / '.local/share/dotfiles-src')


def rice_version() -> str:
    """版本号单一来源：仓库根的 VERSION 文件（bash 侧也读它）。"""
    try:
        return (repo() / 'VERSION').read_text().strip() or 'unknown'
    except OSError:
        return 'unknown'


def self_name() -> str:
    """调用者看到的安装器路径，用于提示语。

    bash 侧写的是 $0（`./install.sh` / `install.sh` / 绝对路径，随调用方式
    变），Python 拿不到它 —— 由 lib/15-python.sh 的 dotctl_run 经 DOTCTL_SELF
    传进来。兜底值只是为了让直接 `python3 -m dotctl` 时不至于崩。
    """
    return os.environ.get('DOTCTL_SELF') or './install.sh'
