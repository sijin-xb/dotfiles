#!/usr/bin/env python3
"""原地修改某条 hl.bind 的按键组合。

为什么是「原地改那一行」而不是往 custom/keybinds.lua 追加一条覆盖：
  hyprctl binds 只给出 dispatcher="__lua" + arg="<序号>"，无法还原成可写回的
  Lua 表达式；配置里大量绑定用的是内联 function，重建必然失真。
  只有从源码行里把 key 字符串换掉，才能原样保住原来的 dispatcher。

安全措施：
  - 只替换 `hl.bind(` 之后**第一个**引号字符串，同一行其余内容一字不动；
  - --expect 传入当前组合，若对不上说明文件已被改动（解析结果过期）→ 拒绝执行；
  - 写回前自动留一份 .bak-<时间戳> 备份；
  - 支持 --dry-run，只报告将要做什么。

输出：一行 JSON，便于 QML 侧解析。
"""

import argparse
import json
import os
import re
import shutil
import sys
import time

# hl.bind("  ...  "   只匹配紧随 hl.bind( 的第一个引号串
BIND_KEY_RE = re.compile(r'(hl\.bind\s*\(\s*")([^"]*)(")')

# 允许出现在组合里的修饰键名
KNOWN_MODS = ["SUPER", "SHIFT", "CTRL", "ALT", "META"]


def fail(msg):
    print(json.dumps({"ok": False, "error": msg}, ensure_ascii=False))
    sys.exit(1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", required=True)
    ap.add_argument("--line", type=int, required=True, help="1-based 行号")
    ap.add_argument("--combo", required=True, help='新的组合，如 "SUPER + SHIFT + Q"')
    ap.add_argument("--expect", default="", help="当前组合；对不上则拒绝执行")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    path = os.path.expanduser(os.path.expandvars(args.file))
    if not os.path.isfile(path):
        fail(f"文件不存在: {path}")

    combo = " + ".join(p.strip() for p in args.combo.split("+") if p.strip())
    if not combo:
        fail("组合为空")

    # 粗略校验：修饰键必须是我们认识的，最后一段是按键/鼠标
    parts = [p.strip() for p in combo.split("+")]
    bad = [p for p in parts[:-1] if p.upper() not in KNOWN_MODS]
    if bad:
        fail(f"未知修饰键: {', '.join(bad)}")
    if not parts[-1]:
        fail("缺少按键")

    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    idx = args.line - 1
    if idx < 0 or idx >= len(lines):
        fail(f"行号 {args.line} 超出范围（文件共 {len(lines)} 行）")

    original = lines[idx]
    m = BIND_KEY_RE.search(original)
    if not m:
        fail(f"第 {args.line} 行不是 hl.bind(\"…\") 形式，拒绝修改")

    current = m.group(2)
    if args.expect and current.strip() != args.expect.strip():
        fail(f"第 {args.line} 行当前是 {current!r}，与预期 {args.expect!r} 不符"
             f"（配置可能已改动，请刷新后重试）")

    if current.strip() == combo:
        print(json.dumps({"ok": True, "changed": False,
                          "old": current, "new": combo, "file": path,
                          "line": args.line}, ensure_ascii=False))
        return

    new_line = original[:m.start(2)] + combo + original[m.end(2):]

    result = {
        "ok": True,
        "changed": True,
        "old": current,
        "new": combo,
        "file": path,
        "line": args.line,
        "dryRun": bool(args.dry_run),
    }

    if args.dry_run:
        result["preview"] = new_line.rstrip("\n")
        print(json.dumps(result, ensure_ascii=False))
        return

    backup = f"{path}.bak-{int(time.time())}"
    try:
        shutil.copy2(path, backup)
    except OSError as e:
        fail(f"备份失败，已中止: {e}")

    try:
        lines[idx] = new_line
        with open(path, "w", encoding="utf-8") as f:
            f.writelines(lines)
    except OSError as e:
        shutil.copy2(backup, path)   # 写失败就回滚
        fail(f"写入失败，已回滚: {e}")

    # 复核：写回后这一行的组合确实是新值
    with open(path, "r", encoding="utf-8") as f:
        check = f.readlines()[idx]
    m2 = BIND_KEY_RE.search(check)
    if not m2 or m2.group(2) != combo:
        shutil.copy2(backup, path)
        fail("写回校验失败，已回滚")

    result["backup"] = backup
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
