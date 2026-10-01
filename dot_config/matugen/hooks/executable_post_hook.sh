#!/usr/bin/env bash
# =============================================================================
#  ~/.config/matugen/hooks/post_hook.sh
#
#  matugen 生成全部模板后的统一收尾钩子：重载合成器配置、热重载常驻组件，
#  对无法热重载的程序只做提示。
#
#  挂载方式（config.toml 里给一个 index 最大的模板挂上，保证它在所有模板
#  都写完之后才跑）：
#      [templates.hooks]
#      input_path  = '~/.config/matugen/templates/hook-anchor.txt'
#      output_path = '~/.local/state/matugen/hook-anchor.txt'
#      index       = 1000
#      post_hook   = 'bash "$HOME/.config/matugen/hooks/post_hook.sh"'
#
#  设计约束
#    · 绝不 kill 任何程序。能热重载的用信号，不能的只打印提示。
#    · 所有外部命令都先探测存在性，缺了不影响其它步骤（脚本永远 exit 0）。
#    · 幂等：重复执行结果一致，不需要清理状态。
#    · 不写任何全局环境（不用 systemctl set-environment）。
#
#  调试：MATUGEN_HOOK_VERBOSE=1 打印每一步；MATUGEN_HOOK_QUIET=1 只打警告。
# =============================================================================

set -uo pipefail

VERBOSE=${MATUGEN_HOOK_VERBOSE:-0}
QUIET=${MATUGEN_HOOK_QUIET:-0}

say()  { [ "$QUIET" = 1 ] || printf '[matugen] %s\n' "$*"; }
dbg()  { [ "$VERBOSE" = 1 ] && printf '[matugen:debug] %s\n' "$*"; return 0; }
warn() { printf '[matugen:warn] %s\n' "$*" >&2; }

have() { command -v "$1" >/dev/null 2>&1; }

# ── 0. 前置检查 ──────────────────────────────────────────────────────────────
# 从 TTY / ssh / systemd timer 里跑 matugen 时没有图形会话，重载动作毫无意义
# 且会刷一堆错误。直接退出。
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ]; then
    dbg "无图形会话（WAYLAND_DISPLAY/DISPLAY 均未设置），跳过重载"
    exit 0
fi

# ── 1. 延迟保护 ──────────────────────────────────────────────────────────────
# matugen 的 post_hook 在文件句柄关闭后立刻执行，但订阅方（niri/hyprland 的
# inotify、waybar 的 CSS 解析）可能读到只写了一半的文件。给 0.5s 让写盘落地。
# 另外 niri 的配置监听有 200ms 级防抖，太早 reload 会拿到旧内容。
sleep 0.5

# ── 2. 双 WM 智能检测 ────────────────────────────────────────────────────────
# 优先信 $XDG_CURRENT_DESKTOP（登录会话里由 dbus-update-activation-environment
# 注入）；它不可靠时（例如从 systemd 单元触发）退回进程探测。
WM=""
case "${XDG_CURRENT_DESKTOP:-}${XDG_SESSION_DESKTOP:-}" in
    *niri*|*Niri*)        WM=niri ;;
    *Hyprland*|*hyprland*) WM=hyprland ;;
esac

if [ -z "$WM" ]; then
    # 注意：pgrep -x 的进程名上限是 15 字符，'niri' / 'Hyprland' 都在范围内。
    if pgrep -x niri >/dev/null 2>&1; then
        WM=niri
    elif pgrep -x Hyprland >/dev/null 2>&1; then
        WM=hyprland
    fi
fi

dbg "检测到 WM=${WM:-<none>}"

case "$WM" in
    niri)
        # niri 的动作名是 load-config-file，不是 reload-config。
        # 它会重新读 ~/.config/niri/config.kdl，进而重新 include matugen 生成的文件。
        if have niri; then
            if niri msg action load-config-file >/dev/null 2>&1; then
                say "niri: 配置已重载"
            else
                warn "niri: load-config-file 失败（niri 是否在运行？）"
            fi
        fi
        ;;
    hyprland)
        if have hyprctl; then
            if hyprctl reload >/dev/null 2>&1; then
                say "hyprland: 配置已重载"
            else
                warn "hyprland: hyprctl reload 失败"
            fi
        fi
        ;;
    *)
        dbg "未识别合成器，跳过 WM 重载"
        ;;
esac

# ── 3. 组件热重载 ────────────────────────────────────────────────────────────

# 3.1 waybar：SIGUSR2 == 界面里的「重载配置」，重读 style.css 与 config。
#     没有实例时 pkill 返回 1，忽略。
if have waybar && pgrep -x waybar >/dev/null 2>&1; then
    if pkill -SIGUSR2 -x waybar; then
        say "waybar: 已重载样式"
    fi
fi

# 3.2 swaync：-rs = reload-style，重读 style.css。
if have swaync-client && pgrep -x swaync >/dev/null 2>&1; then
    if swaync-client -rs >/dev/null 2>&1; then
        say "swaync: 已重载样式"
    fi
fi

# 3.3 kitty：通过远程控制把新配色推给所有窗口。
#     前提是 kitty.conf 里有 allow_remote_control（见文末提示）。
if have kitty && pgrep -x kitty >/dev/null 2>&1; then
    if kitty @ ls >/dev/null 2>&1; then
        if kitty @ set-colors --all --configured "$HOME/.config/kitty/current-theme.conf" >/dev/null 2>&1; then
            say "kitty: 已推送新配色"
        else
            warn "kitty: set-colors 失败"
        fi
    else
        warn "kitty: 远程控制未开启，无法热重载。在 kitty.conf 里加：allow_remote_control socket-only"
    fi
fi

# 3.4 btop：SIGUSR2 等价于 Ctrl+R。btop 的主题由 config.toml 里 btop 模板
#     自己的 post_hook 处理；这里只是兜底，避免有人把那条 hook 删掉。
if pgrep -x btop >/dev/null 2>&1; then
    pkill -SIGUSR2 -x btop 2>/dev/null || true
fi

# 3.5 Firefox userChrome：matugen 只把内容生成到固定位置，这里按当前 profile
#     复制进去。profile 目录名是随机串，「刷新 Firefox」还会换名字，所以不能
#     把 output_path 写死成某个 profile 路径。
#     用 cmp 先比一次，内容没变就不写 —— 避免无谓地改动 profile 的 mtime。
FF_SRC="$HOME/.config/matugen/generated/firefox-userChrome.css"
if [ -f "$FF_SRC" ]; then
    for prof in "$HOME"/.mozilla/firefox/*.default*; do
        [ -d "$prof" ] || continue
        mkdir -p "$prof/chrome"
        if ! cmp -s "$FF_SRC" "$prof/chrome/userChrome.css"; then
            if cp -f "$FF_SRC" "$prof/chrome/userChrome.css"; then
                say "firefox: userChrome.css 已同步到 $(basename "$prof")"
            else
                warn "firefox: 写入 $(basename "$prof")/chrome/ 失败"
            fi
        fi
    done
fi

# ── 3.6 （可选）让 matugen 接管 KDE / Qt 配色方案 ───────────────────────────
# 默认**不启用**。原因见 config.toml 里 [templates.kde_colorscheme] 的注释：
# niri 会话下 DMS 会写 kdeglobals 与 qt6ct.conf，这里再插一手就是两边抢同一个
# 文件。Hyprland 会话没人更新 kdeglobals，启用这一段才划算。
#
# 启用前确认 ~/.local/share/color-schemes/Matugen.colors 已经生成
# （由 [templates.kde_colorscheme] 产出），否则 KDE 应用会找不到方案。
#
# if [ -f "$HOME/.local/share/color-schemes/Matugen.colors" ] \
#    && [ -f "$HOME/.config/kdeglobals" ] \
#    && ! grep -qx 'ColorScheme=Matugen' "$HOME/.config/kdeglobals"; then
#     sed -i 's/^ColorScheme=.*/ColorScheme=Matugen/' "$HOME/.config/kdeglobals"
#     # ColorSchemeHash 是缓存键，方案内容变了必须清掉，否则 KDE 仍用旧色
#     sed -i '/^ColorSchemeHash=/d' "$HOME/.config/kdeglobals"
#     say "kdeglobals: 配色方案已切到 Matugen"
# fi

# ── 4. 优雅降级：只提示，不杀进程 ────────────────────────────────────────────
# 下面这些程序不支持可靠的热重载，或者热重载代价大于收益（重开窗口）。
# 需要重启的才提示，已经在跑且无关的不打扰。

HINTS=()
pgrep -x firefox    >/dev/null 2>&1 && HINTS+=("firefox（userChrome 需要重启才生效）")
pgrep -x mpv        >/dev/null 2>&1 && HINTS+=("mpv（OSC 配色下次打开生效）")
pgrep -x yazi       >/dev/null 2>&1 && HINTS+=("yazi（主题需重新启动）")
pgrep -x code       >/dev/null 2>&1 && HINTS+=("VSCode（Ctrl+Shift+P → Reload Window）")
pgrep -x codium     >/dev/null 2>&1 && HINTS+=("VSCodium（Ctrl+Shift+P → Reload Window）")
pgrep -x kate       >/dev/null 2>&1 && HINTS+=("kate（语法高亮主题需重启）")

if [ ${#HINTS[@]} -gt 0 ]; then
    say "以下程序需要手动重载才能看到新配色："
    for h in "${HINTS[@]}"; do
        say "  · $h"
    done
fi

dbg "post_hook 完成"
exit 0
