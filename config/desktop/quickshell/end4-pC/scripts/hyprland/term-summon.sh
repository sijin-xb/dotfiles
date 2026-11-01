#!/usr/bin/env bash
# SUPER+T 终端召唤：kitty 常驻 special:quake 工作区（浮动、居中、半透明）。
# 已存在 → 切换显示/隐藏（终端状态保留）；不存在 → 启动、等映射完成后显示。
# 由 keybinds.lua 里 SUPER + T 调用，也可手动：
#   ~/.config/quickshell/end4-pC/scripts/hyprland/term-summon.sh
set -euo pipefail

CLASS="kitty-quake"

window_exists() {
	hyprctl clients -j 2>/dev/null | jq -e --arg c "$CLASS" 'any(.[]; .class == $c)' >/dev/null
}

toggle_ws() {
	hyprctl dispatch 'hl.dsp.workspace.toggle_special("quake")' >/dev/null 2>&1 || true
}

if ! window_exists; then
	setsid kitty --single-instance \
		--class "$CLASS" --title "$CLASS" >/dev/null 2>&1 &
	# 等窗口映射（最多 2s），避免闪出一个空的 special 工作区
	for _ in $(seq 1 40); do
		window_exists && break
		sleep 0.05
	done
fi

toggle_ws
