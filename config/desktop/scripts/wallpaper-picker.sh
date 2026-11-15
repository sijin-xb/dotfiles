#!/bin/bash
# 壁纸选择器 / 轮播控制（niri 会话，Ctrl+Alt+T 等键位调用）
# 用法：wallpaper-picker.sh [toggle|next|prev]   默认 toggle

set -uo pipefail

action="${1:-toggle}"

case "$action" in
  next) exec dms ipc call wallpaper next ;;
  prev) exec dms ipc call wallpaper prev ;;
  *)    exec dms ipc call dash toggle wallpaper ;;
esac
