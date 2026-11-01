#!/usr/bin/env bash
#
# 把 matugen 产出的配色应用给终端。
#
# 数据流：
#   generate_colors_material.py → material_colors.scss
#                                     │
#                        render_terminal_theme.py（填占位符）
#                                     │
#                                     └→ OSC 序列 → /dev/pts/*（已经开着的终端立刻变色）
#
# kitty 的配色文件由 matugen 的 [templates.kitty] 直接渲染到
# ~/.config/kitty/current-theme.conf，这里只发 SIGUSR1 让它重读配置。
# 不再自己渲染一份 kitty 主题：旧实现把它写到 state 目录，
# 而那个文件没有任何消费者，属于纯冗余。
#
# 调用方：switchwall.sh，在 matugen 成功后执行；锁色模式不调用。

set -u

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SCSS_FILE="$STATE_DIR/user/generated/material_colors.scss"
SEQUENCES_TEMPLATE="$SCRIPT_DIR/terminal/sequences.txt"
RENDER_SCRIPT="$SCRIPT_DIR/render_terminal_theme.py"
# 渲染结果在 state 下留一份，方便排查「推给终端的到底是什么」
RENDERED_SEQUENCES="$STATE_DIR/user/generated/terminal/sequences.txt"

log() { printf '[applycolor] %s\n' "$*" >&2; }

# 设置 → 界面 → 配色生成 → 终端。配置读不到时按「开启」处理。
terminal_theming_enabled() {
    local cfg="$XDG_CONFIG_HOME/illogical-impulse/config.json"
    [[ -f "$cfg" ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    [[ "$(jq -r '.appearance.wallpaperTheming.enableTerminal // true' "$cfg" 2>/dev/null)" != "false" ]]
}

# 渲染模板 → 目标文件。失败时不产出半成品，由调用方决定后续动作。
render() {
    local template="$1" output="$2"
    [[ -f "$template" ]] || { log "模板不存在，跳过：$template"; return 1; }
    [[ -f "$RENDER_SCRIPT" ]] || { log "缺少渲染脚本：$RENDER_SCRIPT"; return 1; }
    mkdir -p "$(dirname "$output")" || return 1
    python3 "$RENDER_SCRIPT" "$template" "$SCSS_FILE" "$output"
}

# 把 OSC 序列写进每个终端设备节点，让已经开着的终端立刻换色。
push_to_terminals() {
    local file="$1" tty
    for tty in /dev/pts/*; do
        # 只认真正的伪终端，排除 /dev/pts/ptmx
        [[ $tty =~ ^/dev/pts/[0-9]+$ ]] || continue
        # 别人的终端写不进去，失败就跳过，不要中断整轮
        { cat "$file" >"$tty"; } 2>/dev/null & disown || true
    done
}

# 让 kitty 重读 ~/.config/kitty/current-theme.conf。
# pidof 没有结果时不能直接 kill —— 那样 kill 会因为缺少参数报用法错误。
reload_kitty() {
    command -v pidof >/dev/null 2>&1 || return 0
    local pids
    pids="$(pidof kitty 2>/dev/null)" || return 0
    [[ -n $pids ]] || return 0
    # shellcheck disable=SC2086 # pidof 返回空格分隔的多个 PID，需要展开
    kill -SIGUSR1 $pids 2>/dev/null || true
}

apply_terminal() {
    if ! render "$SEQUENCES_TEMPLATE" "$RENDERED_SEQUENCES"; then
        log "终端配色渲染失败，保持原样（详见上方错误）"
        return 1
    fi
    push_to_terminals "$RENDERED_SEQUENCES"
    reload_kitty
}

if ! terminal_theming_enabled; then
    log "终端取色已关闭（设置 → 界面 → 配色生成 → 终端），跳过"
    exit 0
fi

if [[ ! -f "$SCSS_FILE" ]]; then
    log "找不到 $SCSS_FILE，先跑一次取色再回来"
    exit 0
fi

# 后台执行：换壁纸不该为了推终端配色而卡住主流程
apply_terminal &
exit 0
