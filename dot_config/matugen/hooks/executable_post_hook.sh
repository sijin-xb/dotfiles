#!/usr/bin/env bash
# =============================================================================
#  ~/.config/matugen/hooks/post_hook.sh
#
#  matugen 生成全部模板后的统一收尾钩子：重载合成器配置、热重载常驻组件、
#  同步 KDE/Qt 配色方案，对无法热重载的程序只做提示。
#
#  用法
#    post_hook.sh            正常执行（config.toml 的 post_hook 调的就是这个）
#    post_hook.sh --check    只检测环境并报告「将会做什么」，绝不落任何改动
#    post_hook.sh --help
#
#  挂载方式（config.toml 里给 index 最大的模板挂上，保证它在所有模板都写完后
#  才跑）：
#      [templates.hooks]
#      input_path  = '~/.config/matugen/templates/hook-anchor.txt'
#      output_path = '~/.local/state/matugen/last-run.txt'
#      index       = 1000
#      post_hook   = 'bash "$HOME/.config/matugen/hooks/post_hook.sh"'
#
#  环境变量
#    MATUGEN_HOOK_VERBOSE=1     打印每一步（含跳过原因）
#    MATUGEN_HOOK_QUIET=1       只打警告
#    MATUGEN_HOOK_KDE_SCHEME=0  关闭 kdeglobals 配色方案同步
#    MATUGEN_HOOK_LOCK=0        关闭并发锁
#
#  设计约束
#    · 绝不 kill 任何程序。能热重载的用信号，不能的只打印提示。
#    · 所有外部命令都先探测存在性，缺了不影响其它步骤。
#    · 任何分支都 exit 0 —— 钩子失败不该让 matugen 报错。
#    · 幂等：重复执行结果一致，不需要清理状态。
#    · 不写任何全局环境（不用 systemctl set-environment）。
#    · --check 绝不修改任何东西。所有会产生副作用的语句都在 `[ "$EXEC" = 1 ]`
#      分支里，`chk` 只负责打印。改这个脚本时务必保持这个不变量。
# =============================================================================

set -uo pipefail

VERBOSE=${MATUGEN_HOOK_VERBOSE:-0}
QUIET=${MATUGEN_HOOK_QUIET:-0}
KDE_SCHEME=${MATUGEN_HOOK_KDE_SCHEME:-1}
USE_LOCK=${MATUGEN_HOOK_LOCK:-1}
MODE=run
EXEC=1                      # 1 = 真执行；--check 时置 0

case "${1:-}" in
    --check) MODE=check; EXEC=0 ;;
    --help|-h)
        awk 'NR>1 { if (/^#/) { sub(/^# ?/, ""); print } else exit }' "$0"
        exit 0
        ;;
    "") ;;
    *) printf '[matugen:warn] 未知参数: %s（用 --help 看用法）\n' "$1" >&2 ;;
esac

say()  { [ "$QUIET" = 1 ] || printf '[matugen] %s\n' "$*"; }
dbg()  { [ "$VERBOSE" = 1 ] && printf '[matugen:debug] %s\n' "$*"; return 0; }
warn() { printf '[matugen:warn] %s\n' "$*" >&2; }
chk()  { [ "$EXEC" = 0 ] && printf '[check] %s\n' "$*"; return 0; }
have() { command -v "$1" >/dev/null 2>&1; }

HOME_DIR=${HOME:-}
if [ -z "$HOME_DIR" ] || [ ! -d "$HOME_DIR" ]; then
    warn "HOME 未设置或不存在，退出"
    exit 0
fi

RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp}

# ── 0. 前置检查 ──────────────────────────────────────────────────────────────
# 从 TTY / ssh / systemd timer 里跑 matugen 时没有图形会话，重载动作毫无意义
# 且会刷一堆错误。直接退出。
HAS_GRAPHICAL=1
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ]; then
    HAS_GRAPHICAL=0
fi

if [ "$EXEC" = 0 ]; then
    echo "=== matugen post_hook 环境自检 ==="
    printf '图形会话            : %s\n' "$([ "$HAS_GRAPHICAL" = 1 ] && echo 有 || echo 无)"
    printf 'XDG_CURRENT_DESKTOP : %s\n' "${XDG_CURRENT_DESKTOP:-<空>}"
    printf 'XDG_SESSION_DESKTOP : %s\n' "${XDG_SESSION_DESKTOP:-<空>}"
    printf 'WAYLAND_DISPLAY     : %s\n' "${WAYLAND_DISPLAY:-<空>}"
    printf 'DISPLAY             : %s\n' "${DISPLAY:-<空>}"
    printf 'NIRI_SOCKET         : %s\n' "${NIRI_SOCKET:-<空>}"
    if [ -n "${NIRI_SOCKET:-}" ] && [ ! -e "${NIRI_SOCKET:-}" ]; then
        printf '  ↳ 注意：该 socket 不存在（niri 可能重启过），会走回退探测\n'
    fi
    printf 'flock 可用          : %s\n' "$(have flock && echo 是 || echo 否)"
    printf 'kwriteconfig6 可用  : %s\n' "$(have kwriteconfig6 && echo 是 || echo 否)"
fi

if [ "$HAS_GRAPHICAL" = 0 ]; then
    chk "无图形会话 → 将跳过全部重载动作并退出"
    dbg "无图形会话（WAYLAND_DISPLAY/DISPLAY 均未设置），跳过重载"
    [ "$EXEC" = 0 ] && echo "结论                : 什么都不做，直接退出"
    exit 0
fi

# ── 1. 并发锁 ────────────────────────────────────────────────────────────────
# 连续换壁纸时两次 matugen 的钩子可能重叠，导致 niri 两次 reload 抢同一个配置、
# Firefox 的 cmp+cp 序列交错写出半截文件。
#
# 用 mkdir 而不是 flock 的 fd 形式：`exec 9>file` 失败会让非交互 bash 直接退出
# （exec 是特殊内建，重定向错误即退出），而 mkdir 是原子且失败可恢复的。
LOCK_DIR="$RUNTIME_DIR/matugen-hook.lock"

acquire_lock() {
    local now age
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT INT TERM
        return 0
    fi
    # 陈旧锁：持有者被 SIGKILL 时 trap 不会执行。超过 60s 视为残留并抢占。
    now=$(date +%s)
    age=$(( now - $(stat -c %Y "$LOCK_DIR" 2>/dev/null || echo "$now") ))
    if [ "$age" -gt 60 ]; then
        dbg "清除陈旧锁（存在 ${age}s）"
        rmdir "$LOCK_DIR" 2>/dev/null || true
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT INT TERM
            return 0
        fi
    fi
    return 1
}

if [ "$USE_LOCK" = 1 ] && [ "$EXEC" = 1 ]; then
    if acquire_lock; then
        dbg "已取得并发锁 $LOCK_DIR"
    else
        dbg "另一个 post_hook 正在执行，本次跳过"
        exit 0
    fi
fi

# ── 2. 延迟保护 ──────────────────────────────────────────────────────────────
# matugen 的 post_hook 在文件句柄关闭后立刻执行，但订阅方（niri/hyprland 的
# inotify、waybar 的 CSS 解析）可能读到只写了一半的文件。给 0.5s 让写盘落地。
# 另外 niri 的配置监听有 200ms 级防抖，太早 reload 会拿到旧内容。
if [ "$EXEC" = 0 ]; then
    chk "将 sleep 0.5 等写盘落地"
else
    sleep 0.5
fi

# ── 3. 双 WM 智能检测 ────────────────────────────────────────────────────────
# 优先信 $XDG_CURRENT_DESKTOP（登录会话里由 dbus-update-activation-environment
# 注入）；它不可靠时（例如从 systemd 单元触发）退回进程探测。
WM=""
case "${XDG_CURRENT_DESKTOP:-}${XDG_SESSION_DESKTOP:-}" in
    *niri*|*Niri*)         WM=niri ;;
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
[ "$EXEC" = 0 ] && printf '检测到的 WM         : %s\n' "${WM:-未识别}"

# niri 的 reload 封装。`niri msg` 只认 $NIRI_SOCKET，不会自己找 socket；
# 而 niri 重启（换会话、崩溃恢复）后，从旧会话继承来的 $NIRI_SOCKET 会指向
# 已消失的路径。这里先按原值试，失败再退回「$XDG_RUNTIME_DIR 下最新的
# niri.*.sock」。2026-10-02 实测：用户 06:37 重启 niri 后，钩子里继承的
# NIRI_SOCKET 仍指向 PID 929 的旧 socket，reload 一直失败。
niri_reload() {
    niri msg action load-config-file >/dev/null 2>&1 && return 0

    local sock
    if [ -n "${NIRI_SOCKET:-}" ] && [ ! -e "$NIRI_SOCKET" ]; then
        sock=$(ls -t "$RUNTIME_DIR"/niri.*.sock 2>/dev/null | head -1)
        if [ -n "$sock" ]; then
            dbg "NIRI_SOCKET 已失效，回退到 $sock"
            NIRI_SOCKET="$sock" niri msg action load-config-file >/dev/null 2>&1 && return 0
        fi
    fi
    return 1
}

# 关键产物缺失时不做重载 —— 让合成器去读一个不存在的 include 会刷错误。
NIRI_COLORS="$HOME_DIR/.config/niri/matugen-colors.kdl"
HYPR_COLORS="$HOME_DIR/.config/hypr/hyprland/colors.lua"

case "$WM" in
    niri)
        if [ ! -e "$NIRI_COLORS" ]; then
            chk "niri 配色产物不存在 → 将跳过 reload"
            warn "niri: 配色产物不存在，跳过 reload：$NIRI_COLORS"
        elif ! have niri; then
            chk "niri 命令不存在 → 将跳过 reload"
        elif [ "$EXEC" = 0 ]; then
            chk "将执行 niri msg action load-config-file"
        else
            # niri 的动作名是 load-config-file，不是 reload-config。
            if niri_reload; then
                say "niri: 配置已重载"
            else
                warn "niri: load-config-file 失败（niri 是否在运行？NIRI_SOCKET=${NIRI_SOCKET:-<空>}）"
            fi
        fi
        ;;
    hyprland)
        if [ ! -e "$HYPR_COLORS" ]; then
            chk "hyprland 配色产物不存在 → 将跳过 reload"
            warn "hyprland: 配色产物不存在，跳过 reload：$HYPR_COLORS"
        elif ! have hyprctl; then
            chk "hyprctl 不存在 → 将跳过 reload"
        elif [ "$EXEC" = 0 ]; then
            chk "将执行 hyprctl reload"
        else
            if hyprctl reload >/dev/null 2>&1; then
                say "hyprland: 配置已重载"
            else
                warn "hyprland: hyprctl reload 失败"
            fi
        fi
        ;;
    *)
        dbg "未识别合成器，跳过 WM 重载"
        chk "未识别合成器 → 将跳过 WM 重载"
        ;;
esac

# ── 4. 组件热重载 ────────────────────────────────────────────────────────────

# 4.1 waybar：SIGUSR2 == 界面里的「重载配置」，重读 style.css 与 config。
#     没有实例时 pkill 返回 1，忽略。
if pgrep -x waybar >/dev/null 2>&1 && have pkill; then
    if [ "$EXEC" = 0 ]; then
        chk "将给 waybar 发 SIGUSR2"
    elif pkill -SIGUSR2 -x waybar; then
        say "waybar: 已重载样式"
    fi
fi

# 4.2 swaync：-rs = reload-style，重读 style.css。
if pgrep -x swaync >/dev/null 2>&1 && have swaync-client; then
    if [ "$EXEC" = 0 ]; then
        chk "将执行 swaync-client -rs"
    elif swaync-client -rs >/dev/null 2>&1; then
        say "swaync: 已重载样式"
    fi
fi

# 4.3 kitty：通过远程控制把新配色推给所有窗口。
#
# 不用 `kitty @ ls` 去探测远程控制是否可用：没有 allow_remote_control 时，
# kitty 会退回「往 tty 写 DCS 再读回复」的路径，把
# [*x@kitty-cmd{...}] 这种转义序列直接打进用户的终端（本机实测确认）。
# 只认 KITTY_LISTEN_ON —— kitty 在启用了远程控制时才会给子进程设这个变量。
KITTY_THEME="$HOME_DIR/.config/kitty/current-theme.conf"
if pgrep -x kitty >/dev/null 2>&1 && [ -e "$KITTY_THEME" ] && have kitty; then
    if [ -z "${KITTY_LISTEN_ON:-}" ]; then
        dbg "kitty: KITTY_LISTEN_ON 未设置（kitty.conf 缺 allow_remote_control），跳过热重载"
    elif [ "$EXEC" = 0 ]; then
        chk "将执行 kitty @ set-colors --all --configured"
    elif kitty @ set-colors --all --configured "$KITTY_THEME" >/dev/null 2>&1; then
        say "kitty: 已推送新配色"
    else
        warn "kitty: set-colors 失败"
    fi
fi

# 4.4 btop：SIGUSR2 等价于 Ctrl+R。btop 的主题由 config.toml 里 btop 模板
#     自己的 post_hook 处理；这里只是兜底，避免有人把那条 hook 删掉。
if [ "$EXEC" = 1 ] && pgrep -x btop >/dev/null 2>&1 && have pkill; then
    pkill -SIGUSR2 -x btop 2>/dev/null || true
fi

# ── 5. Firefox userChrome 同步 ───────────────────────────────────────────────
# matugen 只把内容生成到固定位置，这里按当前 profile 复制进去。profile 目录名
# 是随机串，「刷新 Firefox」还会换名字，所以不能把 output_path 写死成某个
# profile 路径。用 cmp 先比一次，内容没变就不写 —— 避免无谓地改动 mtime。
FF_SRC="$HOME_DIR/.config/matugen/generated/firefox-userChrome.css"
FF_ROOT="$HOME_DIR/.mozilla/firefox"
FF_SYNCED=0

if [ ! -f "$FF_SRC" ]; then
    dbg "firefox: 源文件不存在，跳过（$FF_SRC）"
elif [ ! -d "$FF_ROOT" ]; then
    dbg "firefox: 没有 profile 目录，跳过（$FF_ROOT）"
else
    for prof in "$FF_ROOT"/*.default*; do
        [ -d "$prof" ] || continue          # glob 未匹配时保持字面量，跳过
        if [ "$EXEC" = 0 ]; then
            chk "将同步 userChrome.css → $(basename "$prof")/chrome/"
            continue
        fi
        mkdir -p "$prof/chrome" 2>/dev/null || continue
        if cmp -s "$FF_SRC" "$prof/chrome/userChrome.css"; then
            dbg "firefox: $(basename "$prof") 内容未变，跳过"
        elif cp -f "$FF_SRC" "$prof/chrome/userChrome.css"; then
            say "firefox: userChrome.css 已同步到 $(basename "$prof")"
            FF_SYNCED=1
        else
            warn "firefox: 写入 $(basename "$prof")/chrome/ 失败"
        fi
    done
fi

# ── 6. KDE / Qt 配色方案同步 ─────────────────────────────────────────────────
# 生成 ≠ 生效：matugen 把配色方案写到 ~/.local/share/color-schemes/Matugen.colors，
# 但 KDE/Qt 读哪个方案由 ~/.config/kdeglobals 的 [General] ColorScheme= 决定。
# 本机实测该键长期停在 MaterialYouDark（旧值），没有任何进程维护它。
#
# 用 kwriteconfig6 而不是 sed：它能正确处理「段不存在」与值转义。
# 同时删掉 ColorSchemeHash —— 那是方案内容的缓存键，留着会让 KDE 继续用旧色。
#
# 关掉：MATUGEN_HOOK_KDE_SCHEME=0
#   （例如你更想让 DMS 或 kde-material-you-colors 管这条链）
KDE_SCHEME_FILE="$HOME_DIR/.local/share/color-schemes/Matugen.colors"
KDE_GLOBALS="$HOME_DIR/.config/kdeglobals"

if [ "$KDE_SCHEME" != 1 ]; then
    dbg "kdeglobals 同步已按 MATUGEN_HOOK_KDE_SCHEME=0 关闭"
elif [ ! -f "$KDE_SCHEME_FILE" ]; then
    dbg "Matugen.colors 不存在，跳过 kdeglobals 同步"
elif [ ! -f "$KDE_GLOBALS" ]; then
    dbg "kdeglobals 不存在，跳过"
else
    CUR=""
    if have kreadconfig6; then
        CUR=$(kreadconfig6 --file kdeglobals --group General --key ColorScheme 2>/dev/null)
    else
        CUR=$(sed -n 's/^ColorScheme=//p' "$KDE_GLOBALS" 2>/dev/null | head -1)
    fi

    if [ "$CUR" = "Matugen" ]; then
        dbg "kdeglobals: 已经是 Matugen，跳过"
    elif [ "$EXEC" = 0 ]; then
        chk "将把 kdeglobals ColorScheme 从 '${CUR:-<空>}' 改为 Matugen"
    elif have kwriteconfig6; then
        if kwriteconfig6 --file kdeglobals --group General --key ColorScheme Matugen 2>/dev/null \
           && kwriteconfig6 --file kdeglobals --group General --key ColorSchemeHash --delete 2>/dev/null; then
            say "kdeglobals: 配色方案已切到 Matugen（原值 ${CUR:-<空>}）"
        else
            warn "kdeglobals: kwriteconfig6 写入失败"
        fi
    elif grep -q '^ColorScheme=' "$KDE_GLOBALS" 2>/dev/null; then
        if sed -i 's/^ColorScheme=.*/ColorScheme=Matugen/' "$KDE_GLOBALS" \
           && sed -i '/^ColorSchemeHash=/d' "$KDE_GLOBALS"; then
            say "kdeglobals: 配色方案已切到 Matugen（sed 兜底）"
        else
            warn "kdeglobals: sed 写入失败"
        fi
    else
        warn "kdeglobals: 没有 ColorScheme 键且无 kwriteconfig6，跳过"
    fi
fi

# ── 6.5 Konsole：把默认 profile 指向 matugen 生成的那个 ─────────────────────
# Konsole 的「当前配色」由 ~/.config/konsolerc 的 [Desktop Entry] DefaultProfile
# 决定，而那一项不在 matugen 的模板体系里，只能在这里补。
#
# 本机原来的值是 "Profile 1.profile"，它指向 kde-material-you-colors 写的
# MaterialYou 配色（种子和 matugen 不是同一个），所以终端颜色一直是另一套。
# 这里改成 Matugen.profile，与 ~/.local/share/konsole/Matugen.colorscheme 配套。
#
# 注意：Konsole 在**新建会话**时读 profile，已在跑的会话不会立刻换色。
# 关掉：MATUGEN_HOOK_KONSOLE=0
KONSOLE_PROFILE="Matugen.profile"
KONSOLE_RC="$HOME_DIR/.config/konsolerc"
KONSOLE_DIR="$HOME_DIR/.local/share/konsole"

if [ "${MATUGEN_HOOK_KONSOLE:-1}" != 1 ]; then
    dbg "Konsole 同步已按 MATUGEN_HOOK_KONSOLE=0 关闭"
elif [ ! -d "$KONSOLE_DIR" ]; then
    dbg "Konsole 未安装（无 $KONSOLE_DIR），跳过"
elif [ ! -f "$KONSOLE_DIR/$KONSOLE_PROFILE" ]; then
    dbg "Konsole profile 不存在（$KONSOLE_DIR/$KONSOLE_PROFILE），跳过"
elif [ ! -f "$KONSOLE_RC" ] && ! have kwriteconfig6; then
    dbg "konsolerc 不存在且没有 kwriteconfig6，跳过"
else
    CUR_PROFILE=""
    if have kreadconfig6; then
        CUR_PROFILE=$(kreadconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile 2>/dev/null)
    else
        CUR_PROFILE=$(sed -n 's/^DefaultProfile=//p' "$KONSOLE_RC" 2>/dev/null | head -1)
    fi

    if [ "$CUR_PROFILE" = "$KONSOLE_PROFILE" ]; then
        dbg "konsolerc: DefaultProfile 已经是 $KONSOLE_PROFILE，跳过"
    elif [ "$EXEC" = 0 ]; then
        chk "将把 konsolerc DefaultProfile 从 '${CUR_PROFILE:-<空>}' 改为 $KONSOLE_PROFILE"
    elif have kwriteconfig6; then
        if kwriteconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile "$KONSOLE_PROFILE" 2>/dev/null; then
            say "konsolerc: 默认 profile 已切到 $KONSOLE_PROFILE（原值 ${CUR_PROFILE:-<空>}）"
        else
            warn "konsolerc: kwriteconfig6 写入失败"
        fi
    elif grep -q '^DefaultProfile=' "$KONSOLE_RC" 2>/dev/null; then
        if sed -i "s|^DefaultProfile=.*|DefaultProfile=$KONSOLE_PROFILE|" "$KONSOLE_RC"; then
            say "konsolerc: 默认 profile 已切到 $KONSOLE_PROFILE（sed 兜底）"
        else
            warn "konsolerc: sed 写入失败"
        fi
    else
        warn "konsolerc: 没有 DefaultProfile 键且无 kwriteconfig6，跳过"
    fi
fi

# ── 7. 优雅降级：只提示，不杀进程 ────────────────────────────────────────────
# 下面这些程序不支持可靠的热重载，或者热重载代价大于收益（重开窗口）。
# 只在「确实在跑」且「确实刚被改了配置」时提示，避免无意义打扰。

HINTS=()
if [ "$FF_SYNCED" = 1 ] && pgrep -x firefox >/dev/null 2>&1; then
    HINTS+=("firefox（userChrome 刚更新，需重启才生效）")
fi
[ -f "$HOME_DIR/.config/mpv/script-opts/osc.conf" ] \
    && pgrep -x mpv >/dev/null 2>&1 && HINTS+=("mpv（OSC 配色下次打开生效）")
pgrep -x yazi   >/dev/null 2>&1 && HINTS+=("yazi（主题需重新启动）")
pgrep -x code   >/dev/null 2>&1 && HINTS+=("VSCode（Ctrl+Shift+P → Reload Window）")
pgrep -x codium >/dev/null 2>&1 && HINTS+=("VSCodium（Ctrl+Shift+P → Reload Window）")
pgrep -x kate   >/dev/null 2>&1 && HINTS+=("kate（语法高亮主题需重启）")
pgrep -x obs    >/dev/null 2>&1 && HINTS+=("OBS（外观主题需重启，或在设置里重选一次）")

if [ ${#HINTS[@]} -gt 0 ]; then
    say "以下程序需要手动重载才能看到新配色："
    for h in "${HINTS[@]}"; do
        say "  · $h"
    done
fi

[ "$EXEC" = 0 ] && echo "结论                : 以上为将执行的动作；本次 --check 未做任何改动"

dbg "post_hook 完成"
exit 0
