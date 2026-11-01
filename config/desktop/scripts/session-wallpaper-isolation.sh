#!/usr/bin/env bash
# 会话壁纸栈隔离：进某个合成器的会话时，清掉另一个合成器遗留的壁纸进程。
#
#   session-wallpaper-isolation.sh niri      # 进 niri：清 Hyprland/end4-pC 栈
#   session-wallpaper-isolation.sh hyprland  # 进 Hyprland：清 niri/DMS 栈
#
# ── 为什么需要 ────────────────────────────────────────────────
# Arch 的 systemd-logind 默认 KillUserProcesses=no：注销后 detached 的
# mpvpaper / quickshell 实例 / kde-material-you-colors 不会随会话结束而死。
# 于是「Hyprland 注销 → 进 niri」时，end4-pC 的旧 mpvpaper 还叠在
# layer-shell 背景上与 DMS 的壁纸互相接管；直接 kill 也没用 —— 活着的旧
# qs 实例（end4-pC 的 Background.qml）会把它再拉起来。
#
# 本脚本按 **cmdline 特征** 精确区分两套栈，互不误杀：
#   end4-pC 栈   mpvpaper 的 ipc-sock 路径含 .cache/quickshell/mpvpaper
#   DMS 栈       mpvpaper 的 ipc-sock 路径含 dms-mpvpaper
# 杀的顺序是「先杀会复活的（qs 实例 / 守护），再杀壁纸本体，最后清 socket」。
#
# 挂载点（两处都要，改动需同步）：
#   niri      ~/.config/niri/config.kdl  spawn-at-startup
#   Hyprland  ~/.config/hypr/hyprland/execs.lua  hl.exec_cmd(...)

set -uo pipefail

side="${1:-}"
QS_PIDS=""

# pkill -f 的目标串里的点号等元字符按 ERE 解释，这里的目标串都只含
# 字面量字符，无需转义；统一 || true —— 目标不存在时 pkill 返回 1，不是错误。

case "$side" in
    niri)
        # ── 清 Hyprland / end4-pC 栈 ─────────────────────────────
        # 1) 先杀会复活的：旧 quickshell 实例（end4-pC）。当前 niri 会话的
        #    DMS shell 是 `qs -p /run/user/1000/danklinux-shell/…`，cmdline
        #    不含 `-c end4-pC`，不会被误伤。
        pkill -f 'qs -c end4-pC' 2>/dev/null || true
        pkill -f 'end4-pC' 2>/dev/null || true
        # 2) 杀 end4-pC 管的取色链（DMS 自带取色，不依赖它）。
        pkill -f 'kde-material-you-colors-wrapper.sh' 2>/dev/null || true
        pkill -f 'venv/bin/kde-material-you-colors' 2>/dev/null || true
        # 3) 只杀 end4-pC 风格的 mpvpaper（sock 路径特征），DMS 的不碰。
        #    ⚠ 不要用 pkill -x mpvpaper：会无差别杀掉 DMS 自己刚拉起的壁纸。
        pkill -f 'input-ipc-server=.*\.cache/quickshell/mpvpaper' 2>/dev/null || true
        # 4) 清掉孤儿 socket，避免下次 Hyprland 会话复用时撞旧文件。
        rm -f "$HOME/.cache/quickshell/mpvpaper"/mpvpaper-*.sock 2>/dev/null || true
        ;;
    hyprland)
        # ── 清 niri / DMS 栈 ─────────────────────────────────────
        # 正常情况下 niri 退出时 dms run / danklinux qs 会随之结束；这里
        # 只兜底处理跨会话残留（KillUserProcesses=no 的漏网之鱼）。
        pkill -f '^dms run' 2>/dev/null || true
        pkill -f 'danklinux-shell' 2>/dev/null || true
        pkill -f 'input-ipc-server=.*dms-mpvpaper' 2>/dev/null || true
        rm -f /run/user/"$(id -u)"/dms-mpvpaper-*.sock 2>/dev/null || true
        ;;
    *)
        echo "用法: session-wallpaper-isolation.sh <niri|hyprland>" >&2
        exit 1
        ;;
esac

exit 0
