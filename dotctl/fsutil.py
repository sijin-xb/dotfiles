"""文件系统小工具（只读）。"""
from __future__ import annotations

import subprocess
from pathlib import Path


def du(path: Path, *, total: bool = False) -> str:
    """`du -h` / `du -sh` 的第一列，取不到返回 '?'。

    不自己递归求和：备份目录有几万个文件，os.walk + stat 会比 du 慢一个数量级。
    """
    flag = '-sh' if total else '-h'
    try:
        out = subprocess.run(['du', flag, str(path)], capture_output=True,
                             text=True, check=False)
    except OSError:
        return '?'
    parts = out.stdout.split()
    return parts[0] if parts else '?'
