#!/usr/bin/env python3
"""Generate pinyin search aliases for desktop entries with Chinese names.

Scans application desktop files, and for every app whose localized Name
contains CJK characters, emits pinyin variants (full, spaced, initials).
Output is consumed by AppSearch.qml so the launcher can find e.g. 萌音
by typing "mengyin" or "my".

Run with the quickshell venv python (has pypinyin):
  ~/.local/state/quickshell/.venv/bin/python generate_app_pinyin.py
"""

import configparser
import glob
import json
import os
import re
import sys

from pypinyin import Style, lazy_pinyin

SEARCH_DIRS = [
    "/usr/share/applications",
    os.path.expanduser("~/.local/share/applications"),
]
OUTPUT_PATH = os.path.expanduser(
    "~/.local/state/quickshell/user/generated/app_pinyin.json"
)
CJK_RE = re.compile(r"[\u4e00-\u9fff]")


def pinyin_variants(name):
    syllables = lazy_pinyin(name, style=Style.NORMAL, errors="ignore")
    syllables = [s for s in syllables if s.strip()]
    if not syllables:
        return ""
    joined = "".join(syllables)
    spaced = " ".join(syllables)
    initials = "".join(s[0] for s in syllables)
    return f"{joined} {spaced} {initials}"


def main():
    aliases = {}
    for d in SEARCH_DIRS:
        for path in glob.glob(os.path.join(d, "*.desktop")):
            cp = configparser.ConfigParser(interpolation=None, strict=False)
            try:
                cp.read(path, encoding="utf-8")
            except Exception:
                continue
            if "Desktop Entry" not in cp:
                continue
            entry = cp["Desktop Entry"]
            if entry.get("type") != "Application":
                continue
            if entry.get("nodisplay", "false").lower() == "true":
                continue
            name = (
                entry.get("name[zh_cn]")
                or entry.get("name[zh]")
                or entry.get("name")
                or ""
            )
            if not CJK_RE.search(name):
                continue
            app_id = os.path.basename(path)[: -len(".desktop")]
            variants = pinyin_variants(name)
            if variants:
                aliases.setdefault(app_id, variants)

    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(aliases, f, ensure_ascii=False, indent=2)
    print(f"{len(aliases)} pinyin aliases -> {OUTPUT_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
