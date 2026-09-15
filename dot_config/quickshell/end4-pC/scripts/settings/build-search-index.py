#!/usr/bin/env python3
"""生成设置面板的搜索索引：页面 → 小节标题（保留英文 key，运行时再翻译）。"""
import json
import re
from pathlib import Path

ROOT = Path("/home/xibie/.config/quickshell/end4-pC")
PAGES = ROOT / "modules/ii/settings/pages"

# SettingsContent.qml 里 pages 列表的顺序 = 侧边栏顺序
ORDER = [
    ("QuickConfig.qml", "Quick"),
    ("GeneralConfig.qml", "General"),
    ("BarConfig.qml", "Bar"),
    ("BackgroundConfig.qml", "Desktop"),
    ("InterfaceConfig.qml", "Interface"),
    ("ServicesConfig.qml", "Services"),
    ("HyprlandConfig.qml", "Hyprland"),
    ("NiriConfig.qml", "Niri"),
    ("About.qml", "About"),
]

index = []
for filename, page_key in ORDER:
    f = PAGES / filename
    if not f.exists():
        continue
    src = f.read_text(encoding="utf-8")
    # ContentSection / ContentSubsection 的 title
    titles = re.findall(r'(?:ContentSection|ContentSubsection)\s*\{.*?title:\s*Translation\.tr\("([^"]+)"\)',
                        src, re.S)
    # 去重保序
    seen, secs = set(), []
    for t in titles:
        if t not in seen:
            seen.add(t)
            secs.append(t)
    index.append({"page": page_key, "file": filename, "sections": secs})

out = ROOT / "modules/ii/settings/settingsSearchIndex.json"
out.write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
total = sum(len(p["sections"]) for p in index)
print(f"已生成索引: {out.relative_to(ROOT)}")
print(f"页面 {len(index)} 个 / 小节 {total} 条")
for p in index:
    print(f"  {p['page']:10} {len(p['sections']):2} 节")
