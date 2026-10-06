"""临时文件，语义与 lib/10-util.sh 的 mktmp / mktmpd 一致。

⚠ 必须落在 bash 侧的 $TMPRUN 里，且调用前先 mkdir -p 它 —— 不只是为了整洁：
tests/install-sh-tmpfiles-test.sh 的 SIGINT 那节，靠的就是「install.sh 跑到
某个子命令时会建出 /tmp/dotfiles-install.<pid>」这个可观察副作用。
Python 若自己用系统 mktemp，那个目录不会出现，测试会判「run 目录没建出来」。

⚠ 路径由 $TMPRUN 推出而不是另起一个：bash 的 EXIT trap 清的就是这个目录，
两边用同一个才能保证 Python 留下的临时文件也被清掉。
"""
from __future__ import annotations

import os
import shutil
import tempfile
from pathlib import Path


def run_dir() -> Path:
    """统一 run 目录。没设 TMPRUN 时退回系统临时目录下的等价路径。"""
    raw = os.environ.get('TMPRUN')
    if raw:
        return Path(raw)
    return Path(os.environ.get('TMPDIR') or '/tmp') / f'dotfiles-install.{os.getpid()}'


def _ensure(path: Path) -> None:
    try:
        path.mkdir(parents=True, exist_ok=True)
    except OSError:
        pass


def mktmp() -> Path:
    """对应 bash 的 mktmp：先建 run 目录，再在它里面开临时文件。"""
    base = run_dir()
    _ensure(base)
    fd, name = tempfile.mkstemp(dir=base)
    os.close(fd)
    return Path(name)


def mktmpd() -> Path:
    """对应 bash 的 mktmpd：先建 run 目录，再在它里面开临时子目录。"""
    base = run_dir()
    _ensure(base)
    return Path(tempfile.mkdtemp(dir=base))


def cleanup(path: Path) -> None:
    """删掉 mktmpd 建出来的目录树；不存在就静默跳过。"""
    shutil.rmtree(path, ignore_errors=True)
