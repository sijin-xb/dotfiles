#!/usr/bin/env python3
"""把 material_colors.scss 里的颜色填进终端配色模板。

applycolor.sh 原来用 `cut -d ' ' -f2` 解析 scss、再用 sed 逐行替换模板。
这套写法依赖「冒号后面正好一个空格」这种排版细节：generate_colors_material.py
的排版一变，抽出来的值就是空的，sed 会把占位符替换成空字符串，终端被刷成
一片黑，而且全程没有任何报错。同理，模板里新增一个 scss 里没有的占位符，
也只是安静地留下 `#$foo #` 这种半成品。

这里改成显式两步：
  1. 解析 scss → name 到 6 位十六进制值的映射（容忍任意空白与引号）；
  2. 替换模板里的 `$name #` 占位符（`#` 是模板自带的十六进制前缀，
     所以替换值本身不含 `#`）。
替换不完整就报错退出、不写输出文件 —— 宁可让终端停在上一套配色，
也不要推一套坏的过去。

用法：
    render_terminal_theme.py <template> <material_colors.scss> <output>

退出码：
    0  成功写出
    1  scss 不可读，或模板里还有解析不到的占位符
"""

from __future__ import annotations

import re
import sys

# `$name` + 至少一个空白 + `#`。末尾的 `#` 会被一起吃掉，
# 因为模板里真正的十六进制前缀是它前面那个 `#`。
PLACEHOLDER = re.compile(rb"\$([A-Za-z][A-Za-z0-9_]*)[ \t]+#")

# scss 里形如 `$onSecondaryContainer: #EDE4E4;`，值允许带引号
SCSS_ENTRY = re.compile(r"^\s*\$([A-Za-z][A-Za-z0-9_]*)\s*:\s*[\"']?#?([0-9A-Fa-f]{6})[\"']?\s*;")


def parse_scss(path: str) -> dict[str, bytes]:
    """读出 name → 6 位十六进制（大写）的映射。

    scss 里除了颜色还有 `$darkmode: True;` 这类非颜色项，正则天然过滤掉了。
    """
    colors: dict[str, bytes] = {}
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            matched = SCSS_ENTRY.match(line)
            if matched:
                colors[matched.group(1)] = matched.group(2).upper().encode("ascii")
    return colors


def main() -> int:
    if len(sys.argv) != 4:
        print("用法：render_terminal_theme.py <template> <material_colors.scss> <output>", file=sys.stderr)
        return 1

    template_path, scss_path, output_path = sys.argv[1], sys.argv[2], sys.argv[3]

    try:
        colors = parse_scss(scss_path)
    except OSError as error:
        print(f"读取 {scss_path} 失败: {error}", file=sys.stderr)
        return 1
    if not colors:
        print(f"{scss_path} 里没解析出任何颜色，格式可能变了", file=sys.stderr)
        return 1

    try:
        with open(template_path, "rb") as handle:
            text = handle.read()
    except OSError as error:
        print(f"读取 {template_path} 失败: {error}", file=sys.stderr)
        return 1

    unresolved: set[str] = set()

    def substitute(matched: re.Match[bytes]) -> bytes:
        name = matched.group(1).decode("ascii")
        value = colors.get(name)
        if value is None:
            unresolved.add(name)
            return matched.group(0)
        return value

    rendered = PLACEHOLDER.sub(substitute, text)
    if unresolved:
        print(
            f"{template_path} 里的占位符在 scss 中找不到：{', '.join(sorted(unresolved))}",
            file=sys.stderr,
        )
        return 1

    try:
        with open(output_path, "wb") as handle:
            handle.write(rendered)
    except OSError as error:
        print(f"写出 {output_path} 失败: {error}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
