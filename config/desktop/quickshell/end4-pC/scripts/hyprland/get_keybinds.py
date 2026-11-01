#!/usr/bin/env python3
import argparse
import re
import os
import json
from typing import Dict, List, Optional

HIDE_MARKERS = ["[hidden]", "# [hidden]"]

parser = argparse.ArgumentParser(description='Hyprland Lua keybind reader')
parser.add_argument('--path', type=str, default="$HOME/.config/hypr/hyprland/keybinds.lua")
args = parser.parse_args()

content_lines = []
reading_line = 0
# 当前正在解析的文件路径，随每条绑定一起带出去（供改键定位源码行）
current_file = ""


class KeyBinding(dict):
    def __init__(self, mods, key, dispatcher, params, comment, file="", line=0, raw=""):
        self["mods"]       = mods
        self["key"]        = key
        # 文件里的原始组合字符串（含空格/顺序）。改键时用它做 expect 校验，
        # 比从 mods+key 重建可靠 —— 原文件未必按标准顺序或单空格书写。
        self["raw"]        = raw
        self["dispatcher"] = dispatcher
        self["params"]     = params
        self["comment"]    = comment
        # 源码位置（1-based 行号）。
        # 改键必须**原地改这一行**，因为 hyprctl binds 只给出
        # dispatcher="__lua" + arg="<序号>"，无法还原成可写回的 Lua 表达式；
        # 只有从源码行里改 key 字符串，才能原样保住原来的 dispatcher。
        self["file"]       = file
        self["line"]       = line


class Section(dict):
    def __init__(self, children, keybinds, name):
        self["children"] = children
        self["keybinds"] = keybinds
        self["name"]     = name


def read_content(path: str) -> str:
    expanded = os.path.expanduser(os.path.expandvars(path))
    if not os.access(expanded, os.R_OK):
        return "error"
    with open(expanded, "r") as f:
        return f.read()


def parse_key_string(key_str: str):
    """Parse 'SUPER + SHIFT + Q' into (['SUPER', 'SHIFT'], 'Q')"""
    known_mods = {"SUPER", "SHIFT", "CTRL", "ALT", "META", "SUPER_L", "SUPER_R"}
    parts = [p.strip() for p in key_str.split("+")]
    mods, key = [], ""
    for p in parts:
        if p.upper() in known_mods:
            mods.append(p)
        else:
            key = p
    return mods, key

def autogenerate_comment(dispatcher: str, params: str = "") -> str:
    d = dispatcher.lower()
    if "exec_cmd" in d or "exec" in d:
        if any(x in params for x in ["qsIsAlive", "qsIpcCall", "qsScripts", "hyprScripts", "grimhyprctl", "mediaNextCommand", ".."]):
            return ""
        return "Execute: {}".format(params[:60] + "..." if len(params) > 60 else params)

def is_hidden(line: str) -> bool:
    for marker in HIDE_MARKERS:
        if marker in line:
            return True
    return False


def parse_lua_bind(line: str, override_comment: str = "",
                   file: str = "", line_no: int = 0) -> Optional[KeyBinding]:
    """
    Handles:
      hl.bind("SUPER + Q", hl.dsp.window.close(), {description = "Close"})
      hl.bind("SUPER + Q", function() ... end, {description = "..."})
    """
    if is_hidden(line):
        return None

    m = re.match(r'\s*hl\.bind\s*\(\s*"([^"]+)"\s*,\s*(.*)', line, re.DOTALL)
    if not m:
        return None

    key_str = m.group(1).strip()
    rest    = m.group(2)

    # Extract description from options table
    desc_match = re.search(r'description\s*=\s*"([^"]+)"', rest)
    comment    = override_comment or (desc_match.group(1) if desc_match else "")

    if is_hidden(rest) or is_hidden(comment):
        return None

    # Extract dispatcher name
    disp_match = re.match(r'(hl\.dsp\.[a-zA-Z_.]+)', rest)
    if disp_match:
        dispatcher = disp_match.group(1)
        # Extract params inside dispatcher call parens
        params_match = re.search(r'hl\.dsp\.[a-zA-Z_.]+\(([^)]*)\)', rest)
        params = params_match.group(1).strip() if params_match else ""
    elif rest.strip().startswith("function"):
        dispatcher = "function"
        params     = ""
    else:
        dispatcher = rest.split(",")[0].strip()
        params     = ""

    if not comment:
        comment = autogenerate_comment(dispatcher, params)

    if not comment:
        return None  # Skip binds with no useful description

    mods, key = parse_key_string(key_str)
    return KeyBinding(mods, key, dispatcher, params, comment, file, line_no, key_str)


def get_binds_recursive(current_content: Section, scope: int) -> Section:
    global content_lines, reading_line

    while reading_line < len(content_lines):
        line = content_lines[reading_line]

        # ── Section headings ──────────────────────────────────────────
        # --##! Title  (scope 2)
        # --###! Title (scope 3)
        heading_match = re.match(r'^(-+#+)!\s*(.*)', line)
        if heading_match:
            heading_scope = heading_match.group(1).count("#")
            section_name  = heading_match.group(2).strip()
            if heading_scope <= scope:
                reading_line -= 1
                return current_content
            reading_line += 1
            current_content["children"].append(
                get_binds_recursive(Section([], [], section_name), heading_scope)
            )
            reading_line += 1
            continue

        # ── Special comment bind: --#/# hl.bind(...) ─────────────────
        # Used for loop-generated binds that need a custom label
        # e.g.: --#/# bind = SUPER + ←/↑/→/↓,, -- Focus in direction
        comment_bind_match = re.match(r'^--#/#\s*(.*)', line)
        if comment_bind_match:
            rest = comment_bind_match.group(1).strip()
            # It might be a descriptive comment like "bind = SUPER + ←, -- Focus left"
            # Extract the comment after "--"
            comment_part = ""
            if " -- " in rest:
                comment_part = rest.split(" -- ", 1)[1].strip()
                if is_hidden(comment_part):
                    reading_line += 1
                    continue
            # Try to parse as hl.bind if it starts with hl.bind
            if rest.startswith("hl.bind"):
                kb = parse_lua_bind(rest, override_comment=comment_part,
                                    file=current_file, line_no=reading_line + 1)
                if kb:
                    current_content["keybinds"].append(kb)
            elif comment_part:
                # It's a descriptive placeholder like "bind = SUPER + ←/→ -- Focus in direction"
                # Extract key hint from before " -- "
                key_hint = rest.split(" -- ")[0].strip()
                # Build a synthetic KeyBinding for display
                kb = KeyBinding([], key_hint, "comment", "", comment_part)
                current_content["keybinds"].append(kb)
            reading_line += 1
            continue

        # ── Normal hl.bind(...) ───────────────────────────────────────
        if re.match(r'\s*hl\.bind\s*\(', line):
            # 行号要在 lookahead 推进**之前**记下来 —— 多行 bind 的起始行才是
            # 改键时要改的那一行（key 字符串总在第一行）。
            bind_line = reading_line + 1

            # Handle multiline binds by collecting until closing paren+bracket
            full_line = line
            depth = full_line.count("(") - full_line.count(")")
            lookahead = reading_line + 1
            while depth > 0 and lookahead < len(content_lines):
                next_line = content_lines[lookahead]
                full_line += " " + next_line.strip()
                depth += next_line.count("(") - next_line.count(")")
                lookahead += 1

            # Check trailing comment for hidden marker
            # e.g. ) -- # [hidden]
            if is_hidden(full_line):
                reading_line = lookahead
                continue

            kb = parse_lua_bind(full_line, file=current_file, line_no=bind_line)
            if kb:
                current_content["keybinds"].append(kb)
            reading_line = lookahead
            continue

        reading_line += 1

    return current_content


def parse_keys(path: str) -> Section:
    global content_lines, reading_line, current_file
    raw = read_content(path)
    if raw == "error":
        return Section([], [], "error")
    content_lines = raw.splitlines()
    reading_line  = 0
    # 记成绝对路径，QML 侧改键时直接用，不用再拼
    current_file  = os.path.expanduser(os.path.expandvars(path))
    return get_binds_recursive(Section([], [], ""), 0)


if __name__ == "__main__":
    result = parse_keys(args.path)
    print(json.dumps(result))