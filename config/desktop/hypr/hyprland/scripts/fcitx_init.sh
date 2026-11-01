#!/usr/bin/env bash
# Fcitx5 初始化（**有界**，失败不影响桌面）。
#
# 为什么单独抽出来
# ----------------
# 这段逻辑原来内联在 hyprland/execs.lua 的一行字符串里，用的是**无界**等待：
#
#     while ! fcitx5-remote --check >/dev/null 2>&1; do sleep 0.1; done
#
# `fcitx5-remote --check` 的语义是「Fcitx 已经在运行就返回 0，否则返回 1」，
# 而 fcitx5 没起来、DBus 不可用（沙箱/异常会话）、或 fcitx5-remote 本身缺失时，
# 它都返回非 0 —— 于是这个循环**永远不会退出**。
#
# 单独一行执行时它只是让输入法不可用；但同一行如果还串着「然后启动 Quickshell」
# （见历史版本 execs.lua），表现就是登录后黑屏、只剩鼠标光标。
# 所以这类等待必须有明确超时。
#
# 约束
# ----
#   * 就绪检查有明确超时（FCITX_READY_TIMEOUT_SEC，默认 10 秒），单次探测也包
#     timeout —— fcitx5-remote 在 DBus 卡住时会一直挂着
#   * 任何一步失败都只记日志并以 0 退出：输入法没起来不该影响桌面
#   * **不注入** QT_IM_MODULE / GTK_IM_MODULE / QT_WAYLAND_TEXT_INPUT_PROTOCOL：
#     那套组合与 layer-shell 有已知死锁，会把整个合成器拖死，见
#     docs/troubleshooting.md「登录后整个桌面卡死」
#   * 不在这里启动 Quickshell，两者解耦，见 start_quickshell.sh

set -uo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
LOG="$STATE_DIR/fcitx-init.log"
READY_TIMEOUT_SEC="${FCITX_READY_TIMEOUT_SEC:-10}"
PROBE_TIMEOUT_SEC="${FCITX_PROBE_TIMEOUT_SEC:-2}"
MAX_LOG_BYTES=262144

mkdir -p "$STATE_DIR"

# 日志轮转：超过 256 KiB 只留最后 512 行，避免无限增长
if [[ -f $LOG ]] && [[ $(wc -c <"$LOG") -gt $MAX_LOG_BYTES ]]; then
    tail -n 512 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

log() { printf '%s [fcitx] %s\n' "$(date '+%F %T')" "$*" >>"$LOG"; }

# fcitx5-remote 在 DBus 卡住时不会自己返回，所有调用都包一层 timeout
probe() { timeout "$PROBE_TIMEOUT_SEC" fcitx5-remote --check >/dev/null 2>&1; }

if ! command -v fcitx5 >/dev/null 2>&1; then
    log "未安装 fcitx5，跳过（不影响桌面）"
    exit 0
fi
if ! command -v fcitx5-remote >/dev/null 2>&1; then
    log "找不到 fcitx5-remote，跳过（不影响桌面）"
    exit 0
fi

if probe; then
    log "fcitx5 已在运行"
else
    log "启动 fcitx5"
    fcitx5 -d >/dev/null 2>&1 || log "fcitx5 -d 返回非 0，继续等就绪"
fi

# ---- 有界等待就绪 ----
deadline=$((SECONDS + READY_TIMEOUT_SEC))
ready=0
while ((SECONDS < deadline)); do
    if probe; then
        ready=1
        break
    fi
    sleep 0.2
done

if ((ready == 0)); then
    log "fcitx5 在 ${READY_TIMEOUT_SEC}s 内未就绪：输入法未激活（桌面不受影响）"
    exit 0
fi

log "fcitx5 就绪（${SECONDS}s 内）"

timeout "$PROBE_TIMEOUT_SEC" fcitx5-remote -o >/dev/null 2>&1 || log "fcitx5-remote -o 失败"
timeout "$PROBE_TIMEOUT_SEC" fcitx5-remote -s rime >/dev/null 2>&1 || log "切换到 rime 失败"

# 输入法相关环境变量只在这里导出一次（供新起的应用通过 dbus 激活环境拿到），
# 不再往 Quickshell 进程里注入。
if dbus-update-activation-environment --systemd \
    XMODIFIERS GTK_IM_MODULE QT_IM_MODULE QT_IM_MODULES LANG LANGUAGE >/dev/null 2>&1; then
    log "输入法环境已导出到 dbus 激活环境"
else
    log "dbus-update-activation-environment 失败（输入法环境未导出）"
fi

exit 0
