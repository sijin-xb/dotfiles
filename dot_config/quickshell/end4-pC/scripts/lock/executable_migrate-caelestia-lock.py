#!/usr/bin/env python3
"""把上游 Caelestia 的锁屏按原样 vendor 进本仓库，并改写 import 路径。

设计原则：**只改 import，不改业务代码**。
上游锁屏的 18 个文件、以及它依赖的 56 个共享组件，全部按原样复制过来；
唯一改动是把 `qs.components.*` / `qs.services` / `qs.utils` / `qs.modules.lock`
这些「指向 Caelestia 自己 shell 根」的 import 换成本地相对路径，
其余（`Caelestia.*` 来自已编译插件、`M3Shapes` 来自 qt6-m3shapes-git）保持不动。

服务名（Players / Weather / Time / Colours …）不做重命名 —— 由本地 shim 模块
提供同名单例去代理本仓库的服务，这样上游文件的业务代码一个字都不用改。

用法：migrate-caelestia-lock.py <上游仓库根> <目标目录>
"""

from __future__ import annotations

import pathlib
import re
import shutil
import sys

# 上游 import → 本地相对路径。key 是正则，value 是替换模板。
# 注意顺序：更长的前缀要先匹配（qs.components.effects 先于 qs.components）。
IMPORT_REWRITES: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"^import qs\.components\.([a-z]+)$", re.M), r'import "\0"'),  # 占位，下面单独处理
    (re.compile(r"^import qs\.services$", re.M), 'import "../shim"'),
    (re.compile(r"^import qs\.utils$", re.M), 'import "../shim"'),
    (re.compile(r"^import qs\.modules\.lock$", re.M), 'import "."'),
]

# 组件子目录（qs.components.<name>）
COMPONENT_SUBDIRS = ("containers", "controls", "effects", "filedialog", "images", "misc", "widgets")

# 从 components/ 顶层与子目录里原样复制的文件类型
COPY_SUFFIXES = (".qml", ".js", ".qrc", ".png", ".svg")


def rewrite_imports(text: str, depth: int) -> str:
    """把指向 Caelestia shell 根的 import 换成本地相对路径。

    depth = 当前文件相对于 upstream/ 的目录层数，用来算相对前缀。
    """
    prefix = "../" * depth

    # qs.components.<sub>  →  <prefix>components/<sub>
    for sub in COMPONENT_SUBDIRS:
        text = re.sub(
            rf"^import qs\.components\.{sub}$",
            f'import "{prefix}components/{sub}"',
            text,
            flags=re.M,
        )

    # qs.components（顶层组件）
    text = re.sub(r"^import qs\.components$", f'import "{prefix}components"', text, flags=re.M)

    # 服务与工具 → 本地 shim
    text = re.sub(r"^import qs\.services$", f'import "{prefix}shim"', text, flags=re.M)
    text = re.sub(r"^import qs\.utils$", f'import "{prefix}shim"', text, flags=re.M)

    # 同目录模块引用
    text = re.sub(r"^import qs\.modules\.lock$", 'import "."', text, flags=re.M)

    return text


def copy_tree(src: pathlib.Path, dst: pathlib.Path) -> int:
    """递归复制组件树（只复制源码与资源）。"""
    count = 0
    for item in src.rglob("*"):
        if item.is_dir() or item.suffix not in COPY_SUFFIXES:
            continue
        target = dst / item.relative_to(src)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(item, target)
        count += 1
    return count


def rewrite_dir(root: pathlib.Path, base: pathlib.Path) -> int:
    """把 root 下所有 .qml/.js 的 import 改写掉，返回处理文件数。"""
    changed = 0
    for item in root.rglob("*"):
        if item.suffix not in (".qml", ".js"):
            continue
        depth = len(item.relative_to(base).parts) - 1
        original = item.read_text(encoding="utf-8")
        updated = rewrite_imports(original, depth)
        if updated != original:
            item.write_text(updated, encoding="utf-8")
            changed += 1
    return changed


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 1

    upstream = pathlib.Path(sys.argv[1]).expanduser()
    target = pathlib.Path(sys.argv[2]).expanduser()

    lock_src = upstream / "modules" / "lock"
    comp_src = upstream / "components"
    for path in (lock_src, comp_src):
        if not path.is_dir():
            print(f"找不到上游目录: {path}", file=sys.stderr)
            return 1

    # 1) 锁屏本体 → target/
    target.mkdir(parents=True, exist_ok=True)
    lock_count = copy_tree(lock_src, target)

    # 2) 共享组件 → target/components/
    comp_dst = target / "components"
    comp_count = copy_tree(comp_src, comp_dst)

    # 3) 改写 import（锁屏本体与组件都要改，组件里也有 qs.components / qs.services）
    lock_changed = rewrite_dir(target, target)

    print(f"锁屏本体复制 {lock_count} 个文件")
    print(f"共享组件复制 {comp_count} 个文件")
    print(f"改写 import 的文件数 {lock_changed}")
    print(f"目标目录 {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
