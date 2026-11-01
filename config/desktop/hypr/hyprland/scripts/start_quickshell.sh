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
#   2. `$qsConfig` 指向一个**加载不起来**的 shell（入口在、但所需模块缺失）
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
#   * 日志：~/.local/state/dotfiles/quickshell-startup.log

set -uo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
LOG="$STATE_DIR/quickshell-startup.log"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
QS_DIR="$CONFIG_HOME/quickshell"
HEALTH_TIMEOUT_SEC="${QS_HEALTH_TIMEOUT_SEC:-15}"
PROBE_TIMEOUT_SEC="${QS_PROBE_TIMEOUT_SEC:-3}"
FALLBACK_SHELL="end4-pC"
MAX_LOG_BYTES=524288

mkdir -p "$STATE_DIR"

# --- 0) Caelestia QML 插件（Caelestia.Config / Caelestia.Services ...） ---
#
# ⚠ 这一条是**必需**的，不是可选优化。
#
# end4-pC 差异层里的锁屏（modules/ii/lock/caelestia/**）是从
# caelestia-dots/shell 原样 vendor 过来的，其中 56 个文件写着
# `import Caelestia.Config`。QML 的 `import <模块>` 是硬依赖：模块解析不到时
# 该文件里的类型全部 unavailable，错误沿
#     CaelestiaLockSurface → Lock → IllogicalImpulseFamily → shell.qml
# 一路上抛，最终 qs 直接 "Failed to load configuration"，
# 表现为**登录后桌面 Shell 起不来**。
#
# 插件的 .so 由 install.sh 的 [4a/7] 编译到 ~/src/caelestia-build/qml，
# 源码在 ~/src/caelestia-plugin-src（**不在** ~/.config/quickshell/ 下：
# 那里是 quickshell 的配置命名空间，放 clone 会凭空多出一套可运行的 shell，
# 也会被快照/归档整包打进去）。
# 这里把产物目录注入 QML2_IMPORT_PATH —— 之前本脚本的注释声称「脚本负责
# QML2_IMPORT_PATH」，但正文从未设置过它，插件对 qs 而言始终不存在。
#
# 目录不存在时不注入（保持原行为：不污染其它 Qt 程序），但会记一条日志，
# 因为那种情况下 end4-pC 的锁屏必然加载失败。
CAELESTIA_QML="${CAELESTIA_QML_PATH:-$HOME/src/caelestia-build/qml}"
CAELESTIA_SRC="${CAELESTIA_SRC_PATH:-$HOME/src/caelestia-plugin-src}"
if [[ -d $CAELESTIA_QML ]]; then
    export QML2_IMPORT_PATH="$CAELESTIA_QML${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"
fi

# 日志轮转：超过 512 KiB 只留最后 1024 行
if [[ -f $LOG ]] && [[ $(wc -c <"$LOG") -gt $MAX_LOG_BYTES ]]; then
    tail -n 1024 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

log() { printf '%s [qs] %s\n' "$(date '+%F %T')" "$*" >>"$LOG"; }

if [[ -d $CAELESTIA_QML ]]; then
    log "注入 QML2_IMPORT_PATH=$QML2_IMPORT_PATH"
else
    log "警告：$CAELESTIA_QML 不存在，Caelestia 插件未编译。"
    log "      end4-pC 锁屏依赖 import Caelestia.Config，缺它会导致 shell 加载失败。"
    log "      修复：重跑 install.sh（[4a/7] 会编译），或手动编译："
    log "            cmake -S $CAELESTIA_SRC -B \$HOME/src/caelestia-build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo \\"
    log "                  -DENABLE_MODULES=plugin -DVERSION=0.0.0 -DGIT_REVISION=unknown"
    log "            cmake --build \$HOME/src/caelestia-build"
fi

# --- 1) 候选顺序：首选（$qsConfig）→ end4-pC ---
preferred="${qsConfig:-}"
if [[ -z $preferred ]]; then
    preferred="$FALLBACK_SHELL"
    log "环境变量 qsConfig 为空，按 $FALLBACK_SHELL 处理"
fi

candidates=("$preferred")
[[ $preferred == "$FALLBACK_SHELL" ]] || candidates+=("$FALLBACK_SHELL")

log "开始启动：首选=$preferred 候选=${candidates[*]}"

# 启动前自检：shell 入口引用了 Caelestia 插件，但插件没编译 —— 这是已知的
# 致命组合（见本文件开头 [0] 的说明），提前报清楚，别让它退化成
# 「加载失败」这种没有指向性的错误。
preflight_caelestia_dep() {
    local cfg="$1"
    local lock_surface="$QS_DIR/$cfg/modules/ii/lock/caelestia/CaelestiaLockSurface.qml"
    # 只有用 Caelestia 风格锁屏（即 vendor 了 caelestia 锁屏）的 shell 才受影响
    [[ -f $lock_surface ]] || return 0
    [[ -d $CAELESTIA_QML ]] && return 0
    log "自检失败：$cfg 的锁屏 $(basename "$lock_surface") 依赖 Caelestia 插件，"
    log "          但 $CAELESTIA_QML 不存在。qs 会报 module \"Caelestia.Config\" is not installed。"
    log "          修复：重跑 install.sh，或手动编译："
    log "            cmake -S $CAELESTIA_SRC -B \$HOME/src/caelestia-build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo \\"
    log "                  -DENABLE_MODULES=plugin -DVERSION=0.0.0 -DGIT_REVISION=unknown"
    log "            cmake --build \$HOME/src/caelestia-build"
    return 1
}

# 启动一个候选；成功返回 0，失败返回 1（失败原因已写日志）
start_shell() {
    local cfg="$1"
    local entry="$QS_DIR/$cfg/shell.qml"

    if [[ ! -f $entry ]]; then
        log "跳过 $cfg：入口不存在（$entry）"
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
    # 已知致命前置缺失（插件没编译）不用再试 —— 试了必然失败，
    # 只会白白消耗 HEALTH_TIMEOUT_SEC 秒并留下误导性的日志。
    preflight_caelestia_dep "$cfg" || continue
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
