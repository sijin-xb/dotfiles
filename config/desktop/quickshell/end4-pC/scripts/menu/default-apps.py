#!/usr/bin/env python3
# ============================================================
# 桌面右键菜单「默认打开」数据源
# 扫描系统里的 .desktop 文件，按类别列出可设为默认打开方式的应用，
# 并通过 xdg-mime 查询各类别当前默认。输出 JSON 到 stdout。
# ============================================================
import glob
import json
import os
import subprocess
from configparser import RawConfigParser

# 每个类别同时给出 MIME 和 freedesktop Categories 令牌。
# 有些应用（典型如 VS Code）不会声明通用 MIME（text/plain），只靠 Categories=TextEditor 表明身份，
# 只按 MimeType 过滤会把它们漏掉。categories 作为补充匹配来源。
CATEGORY_DEFS = [
    {"key": "file_manager", "name": "文件管理器", "icon": "folder_open", "mimes": ["inode/directory"], "categories": ["FileManager"]},
    {"key": "text_editor", "name": "文本编辑器", "icon": "edit_note", "mimes": ["text/plain"], "categories": ["TextEditor"]},
    {"key": "browser", "name": "浏览器", "icon": "public", "mimes": ["x-scheme-handler/https", "x-scheme-handler/http"], "categories": ["WebBrowser"]},
    {"key": "image", "name": "图片查看器", "icon": "image", "mimes": ["image/png"], "categories": ["ImageViewer"]},
    {"key": "video", "name": "视频播放器", "icon": "movie", "mimes": ["video/mp4"], "categories": ["VideoPlayer"]},
    {"key": "audio", "name": "音乐播放器", "icon": "music_note", "mimes": ["audio/mpeg"], "categories": ["AudioPlayer"]},
    {"key": "terminal", "name": "终端", "icon": "terminal", "mimes": ["x-scheme-handler/terminal"], "categories": ["TerminalEmulator"]},
]

data_dirs = [os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share"))]
data_dirs += [d for d in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":") if d]
data_dirs += [
    os.path.expanduser("~/.local/share/flatpak/exports/share"),
    "/var/lib/flatpak/exports/share",
]

locale = os.environ.get("LC_ALL") or os.environ.get("LC_MESSAGES") or os.environ.get("LANG") or ""
locale = locale.split(".", 1)[0].strip()  # zh_CN.UTF-8 → zh_CN
name_keys = []
if locale:
    name_keys.append(f"Name[{locale}]")
    if "_" in locale:
        name_keys.append(f"Name[{locale.split('_')[0]}]")
name_keys.append("Name")

# ---- 扫描全部 .desktop 文件 ----
apps = {}       # desktop id -> {"name","icon"}
mime_map = {}   # mime -> set(desktop id)
cat_map = {}    # freedesktop category -> set(desktop id)
for data_dir in data_dirs:
    app_root = os.path.join(data_dir, "applications")
    for path in glob.glob(os.path.join(app_root, "**", "*.desktop"), recursive=True):
        app_id = os.path.relpath(path, app_root)
        cp = RawConfigParser(interpolation=None, strict=False)
        try:
            cp.read(path, encoding="utf-8")
        except Exception:
            continue
        if not cp.has_section("Desktop Entry"):
            continue
        entry = cp["Desktop Entry"]
        if entry.get("Hidden", "").lower() == "true" or entry.get("NoDisplay", "").lower() == "true":
            continue
        if entry.get("Type", "Application") != "Application":
            continue
        name = next((entry[k] for k in name_keys if entry.get(k)), app_id)
        if app_id not in apps:
            apps[app_id] = {"name": name, "icon": entry.get("Icon", "")}
        for mime in (entry.get("MimeType") or "").split(";"):
            mime = mime.strip()
            if mime:
                mime_map.setdefault(mime, set()).add(app_id)
        for category in (entry.get("Categories") or "").split(";"):
            category = category.strip()
            if category:
                cat_map.setdefault(category, set()).add(app_id)


def query_default(mime):
    try:
        out = subprocess.run(
            ["xdg-mime", "query", "default", mime],
            capture_output=True, text=True, timeout=5,
        ).stdout.strip()
        return out or ""
    except Exception:
        return ""


result = {"categories": []}
for cat in CATEGORY_DEFS:
    ids = set()
    for mime in cat["mimes"]:
        ids |= mime_map.get(mime, set())
    mime_ids = set(ids)  # 显式声明了该 MIME 的应用，排序时优先
    for token in cat.get("categories", ()):
        ids |= cat_map.get(token, set())
    default_id = query_default(cat["mimes"][0])
    if default_id:
        ids.add(default_id)
    app_list = [
        {"id": i, "name": apps[i]["name"], "icon": apps[i]["icon"]}
        for i in sorted(ids) if i in apps
    ]
    # 当前默认排最前，其次显式声明 MIME 的应用，最后按名称排序，最多 15 个
    app_list.sort(key=lambda a: (
        a["id"] != default_id,
        a["id"] not in mime_ids,
        a["name"].lower(),
    ))
    if default_id and not any(a["id"] == default_id for a in app_list):
        app_list.insert(0, {"id": default_id, "name": default_id, "icon": ""})
    app_list = app_list[:15]
    if not app_list:
        continue  # 系统里没有任何候选的类别不显示
    result["categories"].append({
        "key": cat["key"],
        "name": cat["name"],
        "icon": cat["icon"],
        "mimes": cat["mimes"],
        "default": default_id,
        "apps": app_list,
    })

print(json.dumps(result, ensure_ascii=False))
