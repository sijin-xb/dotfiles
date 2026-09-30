#!/usr/bin/env python3
"""检查 quickshell 会话用到的 QML 模块是否都已安装。

## 为什么需要这个

QML 的模块依赖是**运行时**解析的：缺一个 `import` 的模块不会让 shell 启动失败，
只会让「那一个文件」变成 unavailable，然后**引用它的东西连带失败** —— 日志里
只有一行 `WARN scene: ... unavailable`，没有 ERROR，肉眼看到的是「某个组件
凭空消失」。历史上踩过两次：

  · Caelestia 插件（import Caelestia.Config）→ 锁屏整个加载不出来
  · kirigami（AppIcon.qml 的根类型是 Kirigami.Icon）→ Bar 的 workspaces 消失

而且这类缺失在**开发机上往往看不见**：装过 KDE/Plasma 的机器会被全家桶顺带
补上（kirigami 被 36 个 Plasma 包依赖、syntax-highlighting 被 kate 依赖），
只有纯净安装的机器才暴露。所以必须在装完之后显式核一遍。

## 判据

不维护「模块 → 包」的硬编码清单（那种清单一定会过期），而是直接看
**Qt 的 QML 导入路径下有没有对应的模块目录**：
    import Qt5Compat.GraphicalEffects  →  <qmlpath>/Qt5Compat/GraphicalEffects
包名只在「报出补救命令」时才用，缺失时给个提示。

## 用法

    ./check-qml-deps.py                       # 自动扫 ~/.config/quickshell/*
    ./check-qml-deps.py <shell目录> [...]      # 只扫指定目录
    ./check-qml-deps.py --quiet               # 只输出缺失项

退出码：0 = 全部齐全；1 = 有缺失（install.sh 据此给警告，不中断安装）。
"""

import argparse
import os
import re
import sys
from collections import defaultdict

# Qt 的 QML 导入路径。顺序与 Qt 自己的搜索顺序一致。
QML_PATHS = [
    "/usr/lib/qt6/qml",
    "/usr/lib/qt/qml",
    "/usr/lib64/qt6/qml",
    os.path.expanduser("~/.local/lib/qml"),
    os.path.expanduser("~/.local/lib/qt6/qml"),
]

# 已知模块 → 提供它的包（仅在缺失时用于提示，不是判据）
KNOWN_PROVIDERS = {
    "Qt5Compat": "qt6-5compat",
    "QtPositioning": "qt6-positioning",
    "QtLocation": "qt6-location",
    "QtSensors": "qt6-sensors",
    "QtMultimedia": "qt6-multimedia",
    "QtWebSockets": "qt6-websockets",
    "QtWebEngine": "qt6-webengine",
    "QtQuick3D": "qt6-quick3d",
    "QtCharts": "qt6-charts",
    "QtDataVisualization": "qt6-datavis3d",
    "M3Shapes": "qt6-m3shapes-git（AUR）",
    "org.kde.kirigami": "kirigami",
    "org.kde.syntaxhighlighting": "syntax-highlighting",
    "org.kde.kirigamiaddons": "kirigami-addons",
    "Quickshell": "quickshell",
    "Caelestia": "Caelestia QML 插件（见 install.sh 的 [4a/7]）",
}

# 这些前缀属于「本仓库 / shell 自己」的模块，不该按 Qt 模块去找
SKIP_PREFIXES = (
    "qs.",
    "qs/",
    "Caelestia.",
    "Quickshell",     # 由 quickshell 包提供，但路径检查仍有效 —— 不跳过
)
# 上面刻意保留了 Quickshell：它确实在 /usr/lib/qt6/qml/Quickshell 下，
# 检查它能顺带发现「quickshell 装坏了」。

# 由 qt6-declarative / qt6-svg 等基础包提供的模块 —— 它们是 quickshell 的硬依赖，
# 缺失说明 quickshell 本身坏了，单独归一类报出来。
CORE_PREFIXES = ("QtQuick", "QtQml", "QtCore", "QtGui", "QtWidgets", "QtNetwork", "Qt.labs")

import_re = re.compile(r'^\s*import\s+([A-Za-z_][A-Za-z0-9_.]*)')


def module_exists(module):
    """模块目录是否存在于任一 QML 导入路径下。"""
    rel = module.replace(".", "/")
    for base in QML_PATHS:
        if os.path.isdir(os.path.join(base, rel)):
            return True
    return False


def provider_of(module):
    for prefix, pkg in KNOWN_PROVIDERS.items():
        if module == prefix or module.startswith(prefix + "."):
            return pkg
    for prefix in CORE_PREFIXES:
        if module == prefix or module.startswith(prefix + "."):
            return "qt6-declarative（quickshell 的硬依赖，装了 quickshell 就该有）"
    return None


def collect(shell_dirs):
    """{module: [(file, line), ...]}"""
    found = defaultdict(list)
    for shell_dir in shell_dirs:
        for dirpath, dirnames, filenames in os.walk(shell_dir):
            dirnames[:] = [d for d in dirnames if d != ".git"]
            for name in filenames:
                if not name.endswith(".qml"):
                    continue
                path = os.path.join(dirpath, name)
                try:
                    with open(path, encoding="utf-8", errors="ignore") as fh:
                        for lineno, line in enumerate(fh, 1):
                            m = import_re.match(line)
                            if not m:
                                continue
                            module = m.group(1)
                            if module.startswith("qs") or module.startswith("Caelestia"):
                                continue
                            found[module].append((path, lineno))
                except OSError:
                    continue
    return found


def main():
    ap = argparse.ArgumentParser(description="检查 quickshell 会话的 QML 模块依赖")
    ap.add_argument("shell_dirs", nargs="*", help="要扫描的 shell 目录（默认 ~/.config/quickshell/*）")
    ap.add_argument("--quiet", action="store_true", help="只输出缺失项")
    args = ap.parse_args()

    shell_dirs = args.shell_dirs
    if not shell_dirs:
        base = os.path.expanduser("~/.config/quickshell")
        if not os.path.isdir(base):
            print(f"找不到 {base}，先装 shell 再来检查。", file=sys.stderr)
            return 0
        shell_dirs = [
            os.path.join(base, d)
            for d in sorted(os.listdir(base))
            if os.path.isdir(os.path.join(base, d))
        ]
    shell_dirs = [d for d in shell_dirs if os.path.isdir(d)]
    if not shell_dirs:
        print("没有可扫描的目录。", file=sys.stderr)
        return 0

    if not args.quiet:
        print(f"[check-qml-deps] 扫描: {', '.join(shell_dirs)}")

    used = collect(shell_dirs)
    missing = {m: refs for m, refs in used.items() if not module_exists(m)}

    if not args.quiet:
        print(f"[check-qml-deps] 用到 {len(used)} 个外部 QML 模块，"
              f"缺失 {len(missing)} 个")

    if not missing:
        if not args.quiet:
            print("[check-qml-deps] 全部齐全。")
        return 0

    print()
    print("=" * 78)
    print("缺失的 QML 模块（会导致对应组件静默 unavailable）")
    print("=" * 78)
    pkgs = set()
    for module in sorted(missing, key=lambda m: -len(missing[m])):
        refs = missing[module]
        pkg = provider_of(module)
        print(f"\n  {module}   （{len(refs)} 处引用）")
        if pkg:
            print(f"    提供它的包: {pkg}")
            if "（" not in pkg:
                pkgs.add(pkg)
        else:
            print("    未知提供方 —— 需要人工确认是哪个包")
        for path, lineno in refs[:3]:
            print(f"    {path}:{lineno}")
        if len(refs) > 3:
            print(f"    …还有 {len(refs) - 3} 处")

    if pkgs:
        official = sorted(p for p in pkgs if "（" not in p)
        print()
        print("=" * 78)
        print("补救命令（官方仓库的直接装，AUR 的走 helper）：")
        print(f"  sudo pacman -S --needed {' '.join(official)}")
        aur = sorted(p.replace("（AUR）", "") for p in pkgs if "（" in p)
        if aur:
            print(f"  yay -S --needed {' '.join(aur)}")
        print()
        print("装完重启 shell：killall qs; qs -c <会话名> &")
        print("然后确认日志里不再有 unavailable：")
        print("  grep -nE 'unavailable|Property value set multiple times' /tmp/qs-check.log")

    return 1


if __name__ == "__main__":
    sys.exit(main())
