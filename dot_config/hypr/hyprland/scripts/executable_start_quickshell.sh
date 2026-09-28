#!/usr/bin/env bash
# 启动 Quickshell（首选 $qsConfig，失败自动回退 end4-pC），并把全过程写进日志。
#
# 为什么要有这个脚本
# ------------------
# 原来 Quickshell 是内联在 hyprland/execs.lua 一行字符串里启动的，而且那行**前面
# 串着一个无界等待**：
#
#     while ! fcitx5-remote --check; do sleep 0.1; done; ... ; qs -c $qsConfig
#
# 两个后果，任一都会导致「登录后黑屏、只剩鼠标光标」：
#
#   1. 输入法没就绪 → 循环永不退出 → qs 永远不启动 → 桌面只剩光标。
#   2. `$qsConfig` 指向一个**加载不起来**的 shell（典型：caelestia 克隆成功、
#      但 C++ QML 插件没编译，242 个 QML 文件 import Caelestia.* 全部失败）
#      → qs 立刻退出，没有任何回退 → 同样只剩光标。
#
# 所以这里做三件事：**不依赖输入法**、**有健康检查**、**失败会回退**。
#
# 设计约束
# --------
#   * 不用 `timeout` 包住 qs 本体——它是长期运行的进程，只在就绪/健康探测上用
#     timeout（`qs ipc show`、fcitx 探测）
#   * 所有等待都有上限（QS_HEALTH_TIMEOUT_SEC，默认 15 秒）
#   * 首选 shell 的偏好仍然来自 custom/variables.lua 设置的 $qsConfig，
#     本脚本只负责「它真的能用吗」以及「不能用时退到哪」
#   * 保留 QML2_IMPORT_PATH 注入（caelestia 的 C++ 插件在这里），
#     目录不存在时不设置、留痕
#   * 日志：~/.local/state/dotfiles/quickshell-startup.log

set -uo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
LOG="$STATE_DIR/quickshell-startup.log"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
QS_DIR="$CONFIG_HOME/quickshell"
CAELESTIA_BUILD="${CAELESTIA_BUILD_DIR:-$HOME/src/caelestia-build}"
HEALTH_TIMEOUT_SEC="${QS_HEALTH_TIMEOUT_SEC:-15}"
PROBE_TIMEOUT_SEC="${QS_PROBE_TIMEOUT_SEC:-3}"
FALLBACK_SHELL="end4-pC"
MAX_LOG_BYTES=524288

mkdir -p "$STATE_DIR"

# 日志轮转：超过 512 KiB 只留最后 1024 行
if [[ -f $LOG ]] && [[ $(wc -c <"$LOG") -gt $MAX_LOG_BYTES ]]; then
    tail -n 1024 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

log() { printf '%s [qs] %s\n' "$(date '+%F %T')" "$*" >>"$LOG"; }

# --- 1) QML 导入路径：caelestia 的 C++ 插件在这里 ---
if [[ -d $CAELESTIA_BUILD/qml ]]; then
    if [[ -n ${QML2_IMPORT_PATH:-} ]]; then
        export QML2_IMPORT_PATH="$CAELESTIA_BUILD/qml:$QML2_IMPORT_PATH"
    else
        export QML2_IMPORT_PATH="$CAELESTIA_BUILD/qml"
    fi
    log "QML2_IMPORT_PATH=$QML2_IMPORT_PATH"
else
    log "未发现 $CAELESTIA_BUILD/qml，不设置 QML2_IMPORT_PATH"
fi

# --- 2) 候选顺序：首选（$qsConfig）→ end4-pC ---
preferred="${qsConfig:-}"
if [[ -z $preferred ]]; then
    preferred="$FALLBACK_SHELL"
    log "环境变量 qsConfig 为空，按 $FALLBACK_SHELL 处理"
fi

candidates=("$preferred")
[[ $preferred == "$FALLBACK_SHELL" ]] || candidates+=("$FALLBACK_SHELL")

log "开始启动：首选=$preferred 候选=${candidates[*]}"

# caelestia 的界面由编译出来的 C++ QML 模块提供（Caelestia.Config 等）。
# 只检查 shell.qml 存在会把「克隆成功但没编译」当成可用。
caelestia_module_missing() {
    ! compgen -G "$CAELESTIA_BUILD/qml/Caelestia/*.so" >/dev/null 2>&1
}

# 启动一个候选；成功返回 0，失败返回 1（失败原因已写日志）
start_shell() {
    local cfg="$1"
    local entry="$QS_DIR/$cfg/shell.qml"

    if [[ ! -f $entry ]]; then
        log "跳过 $cfg：入口不存在（$entry）"
        return 1
    fi

    if [[ $cfg == caelestia ]] && caelestia_module_missing; then
        log "跳过 caelestia：Caelestia QML 模块缺失（找不到 $CAELESTIA_BUILD/qml/Caelestia/*.so）"
        log "        → 这就是「shell.qml 在、模块不在」的状态，qs 会报 module \"Caelestia.Config\" is not installed"
        return 1
    fi

    # 已经有同配置的实例在跑：不重复启动（脚本可安全重跑）
    if timeout "$PROBE_TIMEOUT_SEC" qs -c "$cfg" ipc show >/dev/null 2>&1; then
        log "$cfg 已在运行，不重复启动"
        return 0
    fi

    log "启动：qs -c $cfg"
    nohup qs -c "$cfg" >>"$LOG" 2>&1 &
    local pid=$!
    local deadline=$((SECONDS + HEALTH_TIMEOUT_SEC))

    while ((SECONDS < deadline)); do
        if ! kill -0 "$pid" 2>/dev/null; then
            wait "$pid"
            log "$cfg 启动后立即退出（exit=$?），原因见本日志上方 qs 的输出"
            return 1
        fi
        if timeout "$PROBE_TIMEOUT_SEC" qs -c "$cfg" ipc show >/dev/null 2>&1; then
            log "$cfg 启动成功（pid=$pid，用时 $((HEALTH_TIMEOUT_SEC - (deadline - SECONDS)))s 内注册 IPC）"
            return 0
        fi
        sleep 0.25
    done

    log "$cfg 在 ${HEALTH_TIMEOUT_SEC}s 内没有注册任何 IPC 目标，判定启动失败，清理这个实例"
    kill -TERM "$pid" 2>/dev/null
    sleep 0.5
    kill -KILL "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    return 1
}

for cfg in "${candidates[@]}"; do
    if start_shell "$cfg"; then
        if [[ $cfg != "$preferred" ]]; then
            log "已回退到 $cfg（首选 $preferred 不可用）"
        fi
        exit 0
    fi
done

log "所有候选都启动失败：${candidates[*]}"
log "排查：1) 本日志里 qs 自己打出的 ERROR（关键字 unavailable / is not installed / Failed to load）"
log "      2) docs/troubleshooting.md「栏里某个组件凭空消失」与 QML 检查命令"
exit 1
