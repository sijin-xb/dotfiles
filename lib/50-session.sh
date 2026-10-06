# ============================================================
# 会话选择与字体开关（原 §2 尾部）
# 三选一会话（end4pc / caelestia / dms）与 FONTS 交互。
# ============================================================
# ---------- 会话选择：合成器 + 桌面 Shell（三选一） ----------
# 三套组合各自对应一套配置：
#   1) end4-pC   Hyprland + quickshell（end4-PC 底盘，pctrade/end4-pC）
#                入口 ~/.config/hypr/hyprland.lua + ~/.config/quickshell/end4-pC
#   2) caelestia Hyprland + caelestia shell（caelestia-dots/shell）
#                shell 本体 clone 到 ~/.config/quickshell/caelestia
#   3) dms       niri + DankMaterialShell（DMS，niri 专属桌面 shell）
#                入口 ~/.config/niri/config.kdl，DMS 配置在 ~/.config/DankMaterialShell
#
# ⚠ Caelestia QML 插件（end4-pC 与 caelestia 都要，见 [4a/7]）统一
#   ~/src/caelestia-plugin-src 取源码、out-of-source 编译到 ~/src/caelestia-build，
#   由 fish/config.fish 与 start_quickshell.sh 两处读取 QML2_IMPORT_PATH 加载，
#   换位置要同步改那两处。
#
# 可交互选择，也可用环境变量预设：SESSION=caelestia ./install.sh install
# 兼容旧变量：COMPOSITOR=niri 等价 SESSION=dms，COMPOSITOR=hyprland 等价 SESSION=end4pc
SESSION="${SESSION:-}"        # end4pc | caelestia | dms
COMPOSITOR="${COMPOSITOR:-}"  # hyprland | niri（由 SESSION 派生，部署过滤/卸载仍用它）
QS_SHELL="${QS_SHELL:-}"      # end4-pC | caelestia | dms（由 SESSION 派生）

# 字体是否随安装部署：1=装 / 0=跳过 / 空=执行时询问。
# 不再无条件塞给用户系统字体（200MB+ 的 AUR 字体链 + 改 /etc/fonts），
# 想脚本化就 FONTS=0 ./install.sh install。
FONTS="${FONTS:-}"
FONTS_ASKED=0                 # 1 = 已经问过/已定，choose_fonts 不再重复问

# SESSION → COMPOSITOR + QS_SHELL。
# COMPOSITOR 仍被部署过滤 / 卸载范围 / 完成指引使用，所以即使有了 SESSION 也要
# 把它派生出来，不能只留一个变量。
# ⚠ 未知值不静默吞掉：环境变量拼错（如 SESSION=niri）以前会静默落到 end4pc，
#   装完才发现会话不对。现在显式警告并回退默认。
session_to_parts() {
    case "$SESSION" in
        caelestia) COMPOSITOR=hyprland; QS_SHELL=caelestia ;;
        dms)       COMPOSITOR=niri;     QS_SHELL=dms ;;
        end4pc)    COMPOSITOR=hyprland; QS_SHELL=end4-pC ;;
        *)
            [[ -n "$SESSION" ]] && warn "未知的 SESSION 预设值 '$SESSION'（合法：end4pc / caelestia / dms），按默认 end4pc 处理"
            SESSION=end4pc; COMPOSITOR=hyprland; QS_SHELL=end4-pC ;;
    esac
}

choose_session() {
    # 环境变量预设：SESSION 优先；没给 SESSION 时回退到旧的 COMPOSITOR
    if [[ -z "$SESSION" && -n "$COMPOSITOR" ]]; then
        case "$COMPOSITOR" in
            niri) SESSION=dms ;;
            *)    SESSION=end4pc ;;
        esac
    fi
    if [[ -n "$SESSION" ]]; then
        session_to_parts
        echo "    会话（环境变量预设）: $SESSION  →  合成器 $COMPOSITOR + shell $QS_SHELL"
        return 0
    fi
    echo
    echo "  选择要安装的会话（合成器 + 桌面 Shell）："
    echo "    1) Hyprland + end4-pC    quickshell（end4-PC 底盘），本仓库主配置"
    echo "    2) Hyprland + caelestia  caelestia shell（clone + 编译 QML 插件）"
    echo "    3) niri + DMS            DankMaterialShell（niri 专属桌面 shell）"
    local ans=""
    printf '  请输入 1/2/3 [默认 1]: '
    read_answer ans
    case "$ans" in
        2|caelestia|Caelestia)    SESSION=caelestia ;;
        3|dms|DMS|niri|Niri|NIRI) SESSION=dms ;;
        *)                        SESSION=end4pc ;;
    esac
    session_to_parts
    echo "    会话: $SESSION → 合成器 $COMPOSITOR + shell $QS_SHELL"
}

# ---------- 字体开关（FONTS=1 装 / 0 跳过 / 空=询问） ----------
fonts_enabled() { [[ "${FONTS:-1}" == "1" ]]; }

fonts_label() {
    if fonts_enabled; then printf '安装推荐字体'; else printf '跳过（不改动系统字体）'; fi
}

fonts_toggle() {
    if fonts_enabled; then FONTS=0; else FONTS=1; fi
    FONTS_ASKED=1
}

# 只问一次：FONTS 预设 → 非 tty 兜底 → 交互询问。
# 问过就把 FONTS_ASKED 置 1，TUI 与 cmd_install 共用同一个选择，不会问两遍。
choose_fonts() {
    if ((FONTS_ASKED)); then return 0; fi
    FONTS_ASKED=1
    case "${FONTS,,}" in
        1|y|yes|true)  FONTS=1; echo "    字体: 安装推荐字体（FONTS 预设）"; return 0 ;;
        0|n|no|false)  FONTS=0; echo "    字体: 跳过，不改动系统字体（FONTS 预设）"; return 0 ;;
    esac
    # 非交互（管道 / 重定向 / 后台执行）不能停下来问，默认装、显式 FONTS=0 可关。
    if [[ ! -t 0 ]]; then
        FONTS=1
        echo "    字体: 非交互运行，默认安装（FONTS=0 可跳过）"
        return 0
    fi
    local ans=""
    printf '    安装推荐字体？（MiSans / Maple Mono NF / 霞鹜文楷 / Noto CJK，约 200MB）[Y/n] '
    read_answer ans
    case "${ans,,}" in
        n|no) FONTS=0; echo "    字体: 跳过，不改动系统字体" ;;
        *)    FONTS=1; echo "    字体: 安装推荐字体" ;;
    esac
}

# 会话推断（原在 lib/83-cmd-status.sh，status 迁到 Python 后挪过来 ——
# doctor / deps 仍在 bash 侧共用它）。
# 会话来源：优先读部署时写下的 deployed-session —— 那才代表**机器现状**；
# 环境变量只是「这次想装什么」，没有部署记录时才退回它推断。
# 副作用：会把 QS_SHELL / COMPOSITOR 设成当前生效值，后续函数（manifest_path
# 等）依赖它们，所以每个命令开头都要先调一次。
status_resolve_session() {
    local sp; sp="$(session_path)"
    if [[ -s "$sp" ]]; then
        IFS='|' read -r QS_SHELL COMPOSITOR < "$sp"
    else
        session_to_parts
    fi
}

status_session_label() {
    case "${QS_SHELL:-}:${COMPOSITOR:-}" in
        end4-pC:hyprland)  printf 'end4pc（Hyprland + quickshell end4-PC）' ;;
        caelestia:hyprland) printf 'caelestia（Hyprland + caelestia shell）' ;;
        dms:niri)          printf 'dms（niri + DankMaterialShell）' ;;
        *)                 printf '%s + %s' "${QS_SHELL:-未知}" "${COMPOSITOR:-未知}" ;;
    esac
}
