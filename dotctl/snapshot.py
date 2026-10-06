"""快照与 state 文件（对应 lib/30-snapshot.sh 与 lib/20-bootstrap.sh 的读写）。

⚠ 为什么经 bashsrc 调而不是在 Python 里重写 tar 逻辑：
`snapshot_current` / `read_state` / `ensure_dirs` / `session_warning_if_running`
同时被仍在 bash 侧的 install 与 update 使用。迁移期两边各存一份实现，迟早
出现「rollback 生成的快照 install 读不到」这类漂移。所以这一层只做**包装**，
真正的打包、路径清单、告警都在 bash 侧那一份里。

`snapshot_current` 里的 $SNAP_PATHS 是 19 项受管理路径的清单，同理留在 bash。
"""
from __future__ import annotations

from pathlib import Path

from . import bashsrc, paths


def ensure_dirs() -> None:
    bashsrc.call('ensure_dirs')


def read_state(key: str) -> Path | None:
    """state/<key> 指向的快照绝对路径；没有或文件不存在则 None。

    对应 bash 的 read_state：它要求「state 文件存在」且「文件里那行指向的
    快照真的在」，两者缺一都算读不到。这一段是纯读文件，所以在 Python 里
    直接实现（不 fork bash）—— 它是 rollback / restore 的第一个判断点，
    在隔离测试里要能便宜地造出来。
    """
    state_file = paths.state_dir() / key
    try:
        line = state_file.read_text().strip()
    except OSError:
        return None
    if not line:
        return None
    snap = Path(line)
    return snap if snap.is_file() else None


def snapshot_current(prefix: str, state_key: str = '') -> bool:
    """打一份快照。成功返回 True。

    ⚠ 经 bash 调用是**必需**的，不只是省事：打包参数里有
    `--warning=no-file-changed --warning=no-file-removed` 这类细节，而且
    失败时返回 1 的语义被 install / update 依赖（它们会据此决定要不要继续）。
    输出直接流到终端（进度与大小是给用户看的）。
    """
    return bashsrc.call_streaming('snapshot_current', prefix, state_key)


def session_warning_if_running() -> None:
    bashsrc.call_streaming('session_warning_if_running')
