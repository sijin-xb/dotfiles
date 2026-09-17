#!/usr/bin/env python3
"""matugen 模板表预检。

matugen 是「全有或全无」的：config.toml 里任何一个 [templates.*] 的
input_path 不存在，整轮渲染都会失败，结果就是所有应用一起停在旧配色上，
而报错信息只说某个文件找不到，很容易被当成别的问题。

这个脚本把 input_path 缺失的模板块剔掉，输出一份仍然可用的副本，
并把被剔掉的名字打到 stdout（每行一个），交给调用方记日志 / 发通知。

用法：
    filter_matugen_templates.py <config.toml> <output.toml>

退出码：
    0  已写出副本（可能剔掉了若干模板，也可能一个都没剔）
    1  输入不可读 / 写不出副本
"""

from __future__ import annotations

import os
import re
import sys

TEMPLATE_HEADER = re.compile(r"^\s*\[templates\.([^\]\s]+)\]\s*$")
ANY_HEADER = re.compile(r"^\s*\[")
INPUT_PATH = re.compile(r"^\s*input_path\s*=\s*(['\"])(?P<path>.+?)\1\s*$")


def split_chunks(text: str) -> list[tuple[str, str, str]]:
    """把 TOML 切成块。

    返回 [(kind, name, body)]，kind 为 "raw"（非模板内容，含其它 section）
    或 "template"。name 仅对 template 有意义。
    """
    chunks: list[tuple[str, str, str]] = []
    current_kind = "raw"
    current_name = ""
    current_lines: list[str] = []

    def flush() -> None:
        if current_lines:
            chunks.append((current_kind, current_name, "".join(current_lines)))

    for line in text.splitlines(keepends=True):
        header = TEMPLATE_HEADER.match(line)
        if header:
            flush()
            current_kind, current_name, current_lines = "template", header.group(1), [line]
        elif ANY_HEADER.match(line):
            # 其它 section（[config] 之类）关掉当前模板块，按原样保留
            flush()
            current_kind, current_name, current_lines = "raw", "", [line]
        else:
            current_lines.append(line)
    flush()
    return chunks


def template_input_path(body: str) -> str | None:
    for line in body.splitlines():
        matched = INPUT_PATH.match(line)
        if matched:
            return matched.group("path")
    return None


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        print("用法：filter_matugen_templates.py <config.toml> <output.toml>", file=sys.stderr)
        return 1

    config_path, output_path = sys.argv[1], sys.argv[2]
    try:
        with open(config_path, encoding="utf-8") as handle:
            text = handle.read()
    except OSError as error:
        print(f"读取 {config_path} 失败: {error}", file=sys.stderr)
        return 1

    kept: list[str] = []
    dropped: list[str] = []
    for kind, name, body in split_chunks(text):
        if kind == "raw":
            kept.append(body)
            continue
        path = template_input_path(body)
        # 拿不到 input_path 就不敢判断，按可用处理（真有问题时 matugen 自己会报）
        if path is None or os.path.exists(os.path.expanduser(path)):
            kept.append(body)
        else:
            dropped.append(name)

    try:
        output_dir = os.path.dirname(os.path.abspath(output_path))
        os.makedirs(output_dir, exist_ok=True)
        tmp_path = output_path + ".tmp"
        with open(tmp_path, "w", encoding="utf-8") as handle:
            handle.write("".join(kept))
        os.replace(tmp_path, output_path)
    except OSError as error:
        print(f"写出 {output_path} 失败: {error}", file=sys.stderr)
        return 1

    for name in dropped:
        print(name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
