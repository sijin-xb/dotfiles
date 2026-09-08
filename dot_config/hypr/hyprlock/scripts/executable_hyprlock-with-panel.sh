#!/usr/bin/env bash
# hyprlock-with-panel.sh --- 启动 hyprlock 同时开启锁屏伴侣面板
# ----------------------------------------------------------------
# 1. 启动 hyprlock-panel.py（GTK3 LayerShell 媒体面板）在后台
# 2. 以 blocking 模式启动 hyprlock
# 3. hyprlock 退出后自动关闭面板
# ----------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PANEL_PY="$SCRIPT_DIR/hyprlock-panel.py"

# 确保面板脚本存在
if [[ ! -f "$PANEL_PY" ]]; then
    # 回退查找
    PANEL_PY="$HOME/.config/hypr/hyprlock/scripts/hyprlock-panel.py"
fi

if [[ -x "$PANEL_PY" ]]; then
    # 启动面板（--watch-pid $$ 让面板监控本脚本的 PID）
    # 当 hyprlock 退出后本脚本退出，面板 watchdog 检测到后自动关闭
    "$PANEL_PY" --watch-pid "$$" &
    PANEL_PID=$!
    echo "锁屏面板已启动 (PID=$PANEL_PID)"
else
    echo "警告: 未找到 hyprlock-panel.py，仅启动 hyprlock" >&2
    PANEL_PID=
fi

# 启动 hyprlock（blocking）
hyprlock "$@"
HYP_EXIT=$?

# hyprlock 退出后清理面板
if [[ -n "${PANEL_PID:-}" ]] && kill -0 "$PANEL_PID" 2>/dev/null; then
    kill "$PANEL_PID" 2>/dev/null || true
    wait "$PANEL_PID" 2>/dev/null || true
fi

exit $HYP_EXIT
