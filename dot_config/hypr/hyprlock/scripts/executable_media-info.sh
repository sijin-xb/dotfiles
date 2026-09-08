#!/usr/bin/env bash
# media-info.sh —— 输出当前播放媒体信息（供 hyprlock label cmd 调用）
# 输出格式: 标题 · 艺术家（最多截断 30 字符）
# 没有播放器运行时输出空行

META=$(playerctl metadata --format "{{title}} · {{artist}}" 2>/dev/null) || META=""
if [[ -n "$META" ]]; then
    # 截断到 36 字符避免撑满锁屏
    echo "${META:0:36}"
else
    echo ""
fi
