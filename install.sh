#!/usr/bin/env bash
# ============================================================
# sijin-xb's dotfiles（Rice 版本: v2.0）
# 单体脚本：安装 / 卸载 / 回档 / 恢复 / 存档打包 / TUI
# ------------------------------------------------------------
# 不依赖 chezmoi，纯 bash 自部署：
#   dot_ 前缀目录  → $HOME 下的隐藏目录（dot_config → ~/.config）
#   executable_ 前缀文件 → 剥前缀 + 恢复执行位
# quickshell 三级回退：已装 → 二进制仓库 → AUR → 源码编译（全自动）
# 覆盖有差异的旧文件前会备份到 ~/.local/state/dotfiles-backup/
# 重复运行安全（幂等）。
#
# 子命令：
#   ./install.sh              → 进入 TUI 二级菜单
#   ./install.sh --tui        → 同上
#   ./install.sh install      → 一键 7 步安装
#   ./install.sh rollback     → 回档到最近一次 install 之前
#   ./install.sh restore      → 从回档前快照恢复 rice 配置
#   ./install.sh archive      → 打包存档（-o PATH 自定义输出，--delete 打包后清理源文件）
#   ./install.sh uninstall    → 卸载 rice（可选是否存档）
#   ./install.sh -h | --help  → 打印帮助
# ============================================================
set -euo pipefail

# ============================================================
# 0. 常量 / 路径
# ============================================================
REPO_URL="https://github.com/sijin-xb/dotfiles.git"
RICE_VERSION="v2.0"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="$HOME/.local/state/dotfiles-backup"
SNAP_ROOT="$BACKUP_ROOT/snapshots"
STATE_DIR="$BACKUP_ROOT/state"
PRE_INSTALL_PREFIX="pre-install"
PRE_ROLLBACK_PREFIX="pre-rollback"

# 快照 / 存档涉及的源路径清单（SNAP_PATHS 18 项 + EXTRA_ARCHIVE_PATHS 3 项）
# 缺失的路径在 tar 时会跳过，不报错
SNAP_PATHS=(
    ".config/hypr"
    ".config/niri"
    # DMS 插件（wallpaperCarousel 静态壁纸轮播 / mpvpaper 视频壁纸 /
    # cavaVisualizer）。只含 plugins 子目录，不含 settings.json ——
    # 后者有机型相关配置（显示器、栏布局），跨机还原会出问题。
    ".config/DankMaterialShell/plugins"
    # 两个 quickshell shell：end4-PC 底盘差异层 + caelestia 本体。
    # 按 SESSION 只会存在一个，缺失的那个 tar 时自动跳过。
    ".config/quickshell/end4-pC"
    ".config/quickshell/caelestia"
    ".config/fish"
    ".config/kitty"
    ".config/foot"
    ".config/fuzzel"
    ".config/mako"
    ".config/nvim"
    ".config/btop"
    ".config/fastfetch"
    ".config/alacritty"
    ".config/matugen"
    ".config/illogical-impulse"
    ".config/mimeapps.list"
    ".config/scripts"
    ".config/mpd"
)
EXTRA_ARCHIVE_PATHS=(
    ".local/state/quickshell"
    ".local/state/dotfiles-backup"
    ".cache/quickshell"
)

# ============================================================
# 1. 输出 / 工具函数
# ============================================================
say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m ->\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m错误:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
in_sync_db() { LC_ALL=C pacman -Si "$1" >/dev/null 2>&1; }
aur_helper() { if have paru; then echo paru; elif have yay; then echo yay; else echo ""; fi; }

aur_install() {
    local helper; helper=$(aur_helper)
    case "$helper" in
        paru) paru -S --needed --noconfirm "$1" ;;
        yay)  yay -S --needed --noconfirm "$1" ;;
        *)    return 1 ;;
    esac
}


ensure_dirs() {
    mkdir -p "$BACKUP_ROOT" "$SNAP_ROOT" "$STATE_DIR"
}

session_warning_if_running() {
    # Hyprland 与 niri 都查：文件覆盖发生在两套合成器共用配置的机器上，
    # 正跑着的哪个会话都可能被覆盖到。
    if have hyprctl && [[ -n $(hyprctl instances 2>/dev/null || true) ]]; then
        warn "检测到 Hyprland 会话正在运行，建议在 TTY 或其他 Wayland 会话下执行文件覆盖操作，避免进程同时写入导致不一致。继续执行，但后果自负。"
    elif pgrep -x niri >/dev/null 2>&1; then
        warn "检测到 niri 会话正在运行，建议在 TTY 或其他 Wayland 会话下执行文件覆盖操作，避免进程同时写入导致不一致。继续执行，但后果自负。"
    fi
}

# 通用交互确认：返回 0=yes, 1=no, 2=back（调用方决定 back 语义）
# 用法：if confirm "继续？"; then ... fi
#       或：confirm "继续？" "允许返回(b键)" && case $? in 2) return;; esac
confirm() {
    local prompt="${1:-是否继续？}" allow_back="${2:-}"
    local ans
    local opts="[y/N]"
    [[ -n $allow_back ]] && opts="[y/N/b(返回)]"
    printf '%s %s ' "$prompt" "$opts"
    IFS= read -r ans
    case "$ans" in
        y|Y|yes|YES|Yes) return 0 ;;
        b|B) [[ -n $allow_back ]] && return 2 ;;
        *) return 1 ;;
    esac
}

now_ts() { date '+%Y%m%d-%H%M%S'; }

# 从 state 文件读取快照绝对路径；读不到返回 1
read_state() {
    local key="$1"
    local f="$STATE_DIR/$key"
    [[ -f $f ]] && {
        local line; line="$(<"$f")"
        [[ -n $line && -f "$line" ]] && { echo "$line"; return 0; }
    }
    return 1
}

write_state() {
    local key="$1" snap_path="$2"
    ensure_dirs
    echo "$snap_path" > "$STATE_DIR/$key"
    # 附带一个时间戳行方便人看
    { echo "# $(date -Iseconds)"; echo "$snap_path"; } > "$STATE_DIR/${key}.withtime"
}

# ============================================================
# 2. 快照核心：snapshot_current / apply_snapshot_from_state
# ============================================================

# $1 = 快照前缀 (pre-install / pre-rollback)
# 写入 state 文件：使用传入的前缀作为 key（如 current / before-rollback）
# $2 = 写入的 state key（可选；不提供就不落 state）
snapshot_current() {
    local prefix="$1"
    local state_key="${2:-}"
    ensure_dirs
    local ts; ts=$(now_ts)
    local snap_path="$SNAP_ROOT/${prefix}-${ts}.tar.gz"
    local tmp_list; tmp_list="$(mktemp)"
    local p rel
    # 筛选真实存在的路径，相对 $HOME
    for p in "${SNAP_PATHS[@]}"; do
        [[ -e "$HOME/$p" ]] && printf '%s\n' "$p" >> "$tmp_list"
    done
    if [[ ! -s $tmp_list ]]; then
        warn "快照：没有任何 rice 路径存在，跳过创建快照"
        rm -f "$tmp_list"
        return 1
    fi
    say "创建快照 [${prefix}] → $(basename "$snap_path")（$(wc -l < "$tmp_list") 个顶级路径）"
    tar --numeric-owner -pzcf "$snap_path" -C "$HOME" --files-from="$tmp_list" 2>/dev/null \
        || tar --numeric-owner -pzcf "$snap_path" -C "$HOME" --files-from="$tmp_list"
    rm -f "$tmp_list"
    [[ -n $state_key ]] && write_state "$state_key" "$snap_path"
    say "快照完成，大小：$(du -h "$snap_path" | cut -f1)"
    return 0
}

apply_snapshot_from_state() {
    local state_key="$1" allow_back="${2:-}"
    local snap_path
    if ! snap_path="$(read_state "$state_key")"; then
        warn "找不到可用的快照（state/$state_key 丢失或快照文件不存在）"
        return 1
    fi
    local nfiles
    # grep -c 在计数为 0 时仍会打印 "0" 但返回 1，直接 || echo 0 会得到两行
    nfiles="$(tar -tzf "$snap_path" 2>/dev/null | grep -v '/$' | wc -l)"
    session_warning_if_running
    echo "----------------------------------------------------------------------"
    echo "  快照文件 : $(basename "$snap_path")"
    echo "  创建时间 : $(stat -c '%y' "$snap_path" 2>/dev/null || unknown)"
    echo "  覆盖目标 : $HOME（只覆盖快照内包含的约 ${nfiles} 个文件，不会删除快照外的文件）"
    echo "----------------------------------------------------------------------"
    case "$allow_back" in
        back) local _r; confirm "确认从该快照覆盖写入 $HOME？" "allow_back"; _r=$?; ((_r==2)) && return 2; ((_r==0)) || return 1;;
        *)    confirm "确认从该快照覆盖写入 $HOME？" || return 1;;
    esac
    say "开始提取 $(basename "$snap_path") ..."
    tar --numeric-owner -pzxf "$snap_path" -C "$HOME"
    say "已提取完成（约 ${nfiles} 个文件）"
    return 0
}

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
    local ans
    read -r -p "  请输入 1/2/3 [默认 1]: " ans || true
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
    IFS= read -r ans || true
    case "${ans,,}" in
        n|no) FONTS=0; echo "    字体: 跳过，不改动系统字体" ;;
        *)    FONTS=1; echo "    字体: 安装推荐字体" ;;
    esac
}

# 依据 $COMPOSITOR 给出需要装的**官方仓库**包（合成器本体 + 对应 xdg-desktop-portal）。
# ⚠ niri 的本体不在这里：本机用的是 AUR 的 fork（见 compositor_aur_pkgs），
#   官方仓库这边只留 portal。
compositor_pkgs() {
    case "$COMPOSITOR" in
        niri) echo "xdg-desktop-portal-gnome" ;;
        *)    echo "hyprland xdg-desktop-portal-hyprland" ;;
    esac
}

# 合成器本体的 AUR 包（官方仓库那侧只放 portal / 依赖）。
#
#   niri → niri-shorin-fork-git：SHORiN-KiWATA/niri。本仓库的 niri 配置依赖
#          它独有的几项，换成上游 niri 或 losnoco 的 niri-spicy-git 都会因
#          未知配置项**拒绝加载整份配置**：
#            - magnifier / adjust-magnifier-zoom / toggle-magnifier
#            - grid-overview（及 grid-overview-open-close、ignore-grid-overview、
#              toggle-grid-overview）—— 「窗口总览」就是它
#            - cursor 的 shake-to-enlarge
#            - screen-cast-picker（配色节点，matugen 模板里也有一份）
#            - 单独一个 Mod 键的绑定（轻触 Super → 启动器）
#          它 provides niri / conflicts niri，与官方 niri、niri-bin、
#          niri-spicy-git 都不能共存 —— 换装前先卸掉旧的那个。
#
# ⚠ 换分支时要同步改这里，并按上面的清单增删 dot_config/niri/** 里的节点，
#   改完务必 `niri validate`。
compositor_aur_pkgs() {
    case "$COMPOSITOR" in
        niri) echo "niri-shorin-fork-git" ;;
        *)    echo "" ;;
    esac
}

# 各 shell 专属的 AUR 包（通用 AUR 包见 [2/7] 的固定列表）。
#
# ⚠ libcava / qt6-m3shapes-git **不是 caelestia 专属**：
#   - libcava           → Caelestia QML 插件编译依赖（pkg_check_modules Cava）
#   - qt6-m3shapes-git  → 锁屏形变动画（MaterialShape）的运行时依赖
#   end4-pC 的锁屏就是从 caelestia vendor 来的（modules/ii/lock/caelestia/**），
#   同时依赖这两者。历史上只在 caelestia 分支装，导致 end4-pC 用户既装不了
#   插件（锁屏 import Caelestia.Config 失败）也缺 MaterialShape。
#   现在放到 [2/7] 的公共 AUR 列表里（见 base_aur_pkgs），不再按 shell 分支。
#
#   dms:  DankMaterialShell 本体 + niri 集成包。用 -git 而不是稳定版：
#         DMS 迭代很快，稳定版往往落后几个小版本，而 niri 侧的
#         config.kdl / dms/binds.kdl 是按新版写的（键位、ipc 目标会对不上）。
#
#         nirius   → niri 的配套工具。niri/binds.kdl 里有 4 个键位直接 spawn 它：
#                    Mod+Ctrl+G `nirius toggle-follow-mode`
#                    Mod+Shift+Q/O/W `nirius focus --app-id <QQ|opencode|wechat>`
#                    缺了这几个键位就是「按了没反应」，且 niri 不会报错。
#         awww-git → niri 侧的壁纸后端。scripts/niri_set_overview_blur_dark_bg.sh
#                    里 WALLPAPER_BACKEND="awww"、scripts/matugen-update.sh 用
#                    `awww query` 取当前壁纸；install.sh 只装了 mpvpaper（视频
#                    壁纸），静态壁纸后端以前一直是空的。
#                    ⚠ 包名是 awww-git：AUR 上没有叫 awww 的包。
shell_aur_pkgs() {
    case "$QS_SHELL" in
        caelestia) echo "" ;;
        dms)       echo "dms-shell-git dms-shell-niri nirius awww-git" ;;
        *)         echo "" ;;
    esac
}

# **所有** quickshell 会话（end4-pC / caelestia）都需要的 AUR 包。
# dms 走 niri + DankMaterialShell，不用 quickshell，因此跳过。
# 见上面 shell_aur_pkgs 的说明：这两者服务于 Caelestia 插件 / 锁屏，与具体
# 选哪个 quickshell shell 无关。
base_aur_pkgs() {
    case "$QS_SHELL" in
        dms) echo "" ;;
        *)   echo "libcava qt6-m3shapes-git" ;;
    esac
}

# 各 shell 专属的 pacman 包（官方仓库）。
#
# ⚠ 同 shell_aur_pkgs：`aubio` / `libqalculate` / `libpipewire` / `lm_sensors` /
#   `fftw` / `spirv-tools` 是 **Caelestia 插件编译与运行的依赖**
#   （plugin/CMakeLists.txt 里 pkg_check_modules 要求 libqalculate / aubio /
#   libpipewire，缺一个 CMake 直接 FATAL_ERROR），而 end4-pC 也编这个插件。
#   所以它们进了 [2/7] 的公共列表（见 base_pacman_pkgs），不在这里按分支给。
#
#   dms:  gpu-screen-recorder —— DMS quickCapture 插件录屏**带声音**的前提，
#         默认键位 Ctrl+Alt+R（见 dot_config/niri/dms/binds.kdl）。不装也能录，
#         但会回退到 wf-recorder（CPU 编码、纯画面无声音）；插件按
#         command -v 探测，装了就自动优先用它。
shell_pacman_pkgs() {
    case "$QS_SHELL" in
        caelestia) echo "" ;;
        dms)       echo "gpu-screen-recorder" ;;
        *)         echo "" ;;
    esac
}

# **所有** quickshell 会话（end4-pC / caelestia）都需要的官方仓库包。
# 即 Caelestia 插件的编译 / 运行依赖。dms 不编插件，跳过。
base_pacman_pkgs() {
    case "$QS_SHELL" in
        dms) echo "" ;;
        *)   echo "aubio libpipewire libqalculate lm_sensors fftw spirv-tools" ;;
    esac
}

# 按 $COMPOSITOR / $QS_SHELL 过滤 SNAP_PATHS，输出到 stdout（一行一个）。
#
# 只用于**删除类**操作（uninstall / archive --delete）：卸载时不该把机器上
# 另一套合成器、或另一套桌面 shell 的既有配置一起删掉。
# 快照（snapshot）和打包（archive）**不用**它——那两步是备份，多带无妨，
# 而且 pre-install 快照发生在 choose_session 之前，过滤它反而会让
# rollback 少恢复东西。
active_snap_paths() {
    local p
    for p in "${SNAP_PATHS[@]}"; do
        if [[ "${INSTALL_BOTH_COMPOSITORS:-0}" == "1" ]]; then
            printf '%s\n' "$p"
            continue
        fi
        if [[ $p == .config/niri ]]; then
            if [[ "$COMPOSITOR" == "niri" ]]; then printf '%s\n' "$p"; fi
        elif [[ $p == .config/hypr ]]; then
            if [[ "$COMPOSITOR" != "niri" ]]; then printf '%s\n' "$p"; fi
        # ⚠ quickshell 的两个 shell 也要分开：end4-PC 与 caelestia 在
        #   ~/.config/quickshell/ 下各占一个目录，卸载其中一套不该顺手删掉
        #   另一套（以前这里只按合成器过滤，两套 shell 都被算进删除范围）。
        #   QS_SHELL 为空 = 没指定，保持旧行为（两个都算）。
        #   值 `both` = 用户在 uninstall_shell_scope 里明确选了"两套都删"。
        elif [[ $p == .config/quickshell/end4-pC ]]; then
            if [[ -z ${QS_SHELL:-} || "$QS_SHELL" == "end4-pC" || "$QS_SHELL" == "both" ]]; then
                printf '%s\n' "$p"
            fi
        elif [[ $p == .config/quickshell/caelestia ]]; then
            if [[ -z ${QS_SHELL:-} || "$QS_SHELL" == "caelestia" || "$QS_SHELL" == "both" ]]; then
                printf '%s\n' "$p"
            fi
        else
            printf '%s\n' "$p"
        fi
    done
}

# 卸载时的删除范围。COMPOSITOR 已设定（例如本次跑过 install，或用了
# COMPOSITOR=niri ./install.sh uninstall）就直接用；用户已在 TUI 卸载页选过
# 「两套都删」（INSTALL_BOTH_COMPOSITORS=1）时同样视为已定，否则交互询问。
#
# ⚠ 第三条早退条件不能省：TUI 的 detail_uninstall 渲染时会先问一次范围，
#   选「两套都删」只会置 INSTALL_BOTH_COMPOSITORS=1（COMPOSITOR 保持为空），
#   随后 cmd_uninstall 会再调一次本函数 —— 没有这条就会对同一个问题问两遍。
uninstall_compositor_scope() {
    if [[ -n ${COMPOSITOR:-} || "${INSTALL_BOTH_COMPOSITORS:-0}" == "1" ]]; then
        return 0
    fi
    echo
    echo "  要删除哪套合成器的配置？"
    echo "    1) 两套都删    ~/.config/hypr + ~/.config/niri"
    echo "    2) 只删 Hyprland  ~/.config/hypr"
    echo "    3) 只删 niri      ~/.config/niri"
    local ans
    IFS= read -r -p "  请输入 1/2/3 [默认 1]: " ans || true
    case "$ans" in
        2) COMPOSITOR=hyprland ;;
        3) COMPOSITOR=niri ;;
        *) INSTALL_BOTH_COMPOSITORS=1 ;;
    esac
}

# 删除类操作的 shell 范围。与 uninstall_compositor_scope 同一套思路：
# QS_SHELL 已设定（环境变量预设，或本次 install 派生过）就直接用；否则询问。
#
# ⚠ 必要性：~/.config/quickshell/end4-pC 与 ~/.config/quickshell/caelestia
#   是两个独立目录，机器上可能同时存在（例如以前试过 caelestia 又换回
#   end4-PC）。不做这个区分的话，卸载 end4-PC 会把 caelestia 的配置一起删掉。
#   选 3 时置为字面量 both —— active_snap_paths 认这个值。
uninstall_shell_scope() {
    if [[ -n ${QS_SHELL:-} ]]; then
        return 0
    fi
    echo
    echo "  要删除哪套桌面 shell 的 quickshell 配置？"
    echo "    1) 只删 end4-PC    ~/.config/quickshell/end4-pC"
    echo "    2) 只删 caelestia  ~/.config/quickshell/caelestia"
    echo "    3) 两套都删"
    local ans
    IFS= read -r -p "  请输入 1/2/3 [默认 1]: " ans || true
    case "$ans" in
        2) QS_SHELL=caelestia ;;
        3) QS_SHELL=both ;;
        *) QS_SHELL=end4-pC ;;
    esac
    echo "    shell 范围: $QS_SHELL"
}

# 依据 $COMPOSITOR 判断仓库内某个相对路径是否**跳过部署**。
#
# 两套合成器配置都在本仓库里（dot_config/hypr/** 与 dot_config/niri/**）。
# 早期版本在 [5/7] 部署时无差别全部 cp 到 $HOME —— 也就是说选了 Hyprland 的人
# 也会被覆盖掉 ~/.config/niri，选择 niri 的人同理被覆盖 ~/.config/hypr。
# 现在默认只部署选中的那套，另一套完全不动（连备份都不做，因为根本不碰）。
#
# 想两套都部署（例如机器上两个合成器都要用）：
#     INSTALL_BOTH_COMPOSITORS=1 ./install.sh install
#
# 返回 0 = 跳过，1 = 正常部署
skip_by_compositor() {
    if [[ "${INSTALL_BOTH_COMPOSITORS:-0}" == "1" ]]; then
        return 1
    fi
    local rel="$1"
    if [[ "$COMPOSITOR" == "niri" ]]; then
        if [[ $rel == dot_config/hypr/* ]]; then return 0; fi
    else
        if [[ $rel == dot_config/niri/* ]]; then return 0; fi
    fi
    return 1
}

# 依据 $QS_SHELL 判断仓库内某个相对路径是否**跳过部署**。
#
# 三个 shell 的差异层在仓库里的位置不同：
#   end4-pC   → dot_config/quickshell/end4-pC/**（本仓库跟踪的差异层）
#   caelestia → shell 本体由 [4b/7] clone 到 ~/.config/quickshell/caelestia；
#               仓库里的 dot_config/quickshell/caelestia/ 只是它的覆盖层
#   dms       → dot_config/DankMaterialShell/**（插件）
# 选了 caelestia 就不该把 end4-pC 的差异层覆盖上去（反之亦然）；DMS 插件只在选
# dms 时部署；illogical-impulse 是 end4-PC 的配置目录，非 end4-pC 时也跳过。
#
# 返回 0 = 跳过，1 = 正常部署
skip_by_shell() {
    local rel="$1"
    case "$QS_SHELL" in
        caelestia)
            # 不部署 end4-PC 差异层与 DMS 插件；caelestia 自己的定制层（若仓库里有）允许
            [[ $rel == dot_config/quickshell/end4-pC/* ]] && return 0
            [[ $rel == dot_config/DankMaterialShell/* ]] && return 0
            [[ $rel == dot_config/illogical-impulse/* ]] && return 0
            ;;
        dms)
            [[ $rel == dot_config/quickshell/* ]] && return 0
            [[ $rel == dot_config/illogical-impulse/* ]] && return 0
            ;;
        end4-pC)
            [[ $rel == dot_config/quickshell/caelestia/* ]] && return 0
            [[ $rel == dot_config/DankMaterialShell/* ]] && return 0
            ;;
    esac
    return 1
}

# 自检 end4-PC 底盘是否**完整**（不只是"入口文件在"）。
#
# ⚠ 清单里**只能放底盘（pctrade/end4-PC）真的提供**的落点。
#   这里以前还列了 4 项 modules/ii/dashboard-caelestia/**：
#
#       modules/ii/dashboard-caelestia/dashboard/Content.qml
#       modules/ii/dashboard-caelestia/components/filedialog/FileDialog.qml
#       modules/ii/dashboard-caelestia/components/controls/ButtonBase.qml
#       modules/ii/dashboard-caelestia/shim/qmldir
#
#   但上游 modules/ii/ 下**根本没有 dashboard-caelestia 这个目录**
#   （本仓库自己的定制层，IslandHost.qml 直接 import
#    "../modules/ii/dashboard-caelestia/components/filedialog"，由 [5/7] 部署）。
#   于是自检永远判"缺"→ 重拉上游也补不上 → 在 [4/7] 报
#   "底盘拉取后仍缺少 …" 直接 die，安装永远走不完。
#
#   改清单前先核一遍（有 = 底盘提供，才可以列进来）：
#     gh api repos/pctrade/end4-PC/contents/<路径>
#
# 输出：完整 → 无输出且返回 1；残缺 → 打印**第一个**缺失项并返回 0。
# ⚠ 返回 1 表示"完整"，调用方用 `x="$(end4pc_base_missing || true)"` 取值，
#   `|| true` 不能省（赋值语句的退出码取自命令替换结果）。
end4pc_base_missing() {
    local dst="${1:-$HOME/.config/quickshell/end4-pC}"
    local rel
    # 下面每一项都按上面的办法核过：上游确实提供，缺了才说明 clone 残缺。
    for rel in \
        shell.qml \
        modules/common/Config.qml \
        modules/common/Appearance.qml \
        services \
        scripts/colors/switchwall.sh
    do
        [[ -e "$dst/$rel" ]] || { printf '%s' "$rel"; return 0; }
    done
    return 1
}

# 精确自检：clone 里有的每个文件，dst 里都该有。
#
# 这才是"cp 半途而废 / 磁盘写满"的**准确**判据 —— 只需要拿 clone 当基准，
# 上游以后加文件、删目录都不用来改这里（硬编码清单会腐烂，见上面那次事故）。
# ⚠ 必须在删掉临时 clone 目录**之前**调用。
# 输出同 end4pc_base_missing：完整 → 无输出且返回 1。
base_tree_missing() {
    local src="$1" dst="$2" rel f
    [[ -d "$src" ]] || { printf '（clone 目录不存在：%s）' "$src"; return 0; }
    # ⚠ 这里刻意**不用** `< <(find …)` 进程替换：它依赖 /dev/fd，容器 / 精简
    #   chroot 里可能不存在，一旦不可用整段判据会静默失效 —— 而这是"完整性"
    #   的最后一道闸，失效就等于放行半残的树。改用临时清单文件。
    local listf; listf="$(mktemp)"
    find "$src" -type f -print0 > "$listf" 2>/dev/null
    while IFS= read -r -d '' f; do
        rel="${f#"$src"/}"
        [[ -e "$dst/$rel" ]] && continue
        printf '%s' "$rel"
        rm -f "$listf"
        return 0
    done < "$listf"
    rm -f "$listf"
    return 1
}

# 把 clone 出来的目录合并进目标目录，**不带 .git**。
#
# ⚠ 为什么必须剥掉 .git（以前两处 `cp -a "$src/." "$dst/"` 都漏了）
# ------------------------------------------------------------------
# 1) ~/.config/quickshell 是**运行时配置命名空间**，不是放源码的地方。
#    [5/7] 的部署循环自己就写着 `.git/*) continue`（跳过仓库元数据），
#    说明 .git 本就不属于这里 —— 唯独漏了 clone 合并这两处。塞进去的是
#    一个十几 MB 的 pack，既没有任何用处，还会被 [0/7] 的快照/归档整包打包。
# 2) 更糟的是它会让安装**永久卡死**：一旦这个 .git 的属主或权限不允许当前
#    用户写入，重跑时 cp 会在 .git/objects/pack/ 上 EACCES 并半途而废，
#    底盘只拷进去一半 → 下次自检判"不完整"→ 又重拉 → 又在同一个位置失败。
#    报错指向 .git，看起来像权限问题，真因却是"压根不该拷"。
merge_clone_into() {
    local src="$1" dst="$2"
    rm -rf "$src/.git"
    mkdir -p "$dst"
    cp -a "$src/." "$dst/" \
        || die "合并 $src → $dst 失败（检查磁盘空间，以及 $dst 及其子目录的属主是否为当前用户）"
}

# 清掉历史上被上面那步误拷进来的 .git（它从来没被用过，可以安全删除）。
# 属主是 root 时普通用户删不掉（要对 .git/objects/pack 有写权限），这时
# 提示手工命令而不是假装成功 —— 留着它不影响 shell 运行，但会一直占空间。
cleanup_stray_git() {
    local dst="$1"
    [[ -e "$dst/.git" ]] || return 0
    if rm -rf "$dst/.git" 2>/dev/null; then
        echo "    已清理历史遗留的 .git（clone 元数据，不属于配置目录）"
    else
        warn "无法删除 $dst/.git（属主可能不是当前用户）"
        warn "  它没有任何用处，可手动清理：sudo rm -rf '$dst/.git'"
    fi
}

# 判断某个**目标相对路径**（相对 $HOME，如 .config/hypr/hyprland/colors.lua）
# 是否命中 $SRC/.chezmoiignore。命中则输出处理方式，未命中输出空：
#   keep   精确路径条目   → 目标已存在时**不覆盖**
#   skip   glob / 目录条目 → 一律跳过
#
# 为什么要读 chezmoi 的忽略清单
# ----------------------------
# install.sh 与 chezmoi 部署同一份源树，规则必须一致。漏读的后果是**用仓库里的
# 旧快照覆盖运行时生成物** —— 最典型的是 .config/hypr/hyprland/colors.lua：
# 那是 matugen 按当前壁纸生成的，仓库里那份只是某次提交时的调色板。实测差异：
#     仓库  active_border = "rgba(90d5aeAA)"
#     实机  active_border = "rgba(feb0d3AA)"
# 也就是说，每重跑一次安装就把用户配色打回旧值。仓库 .chezmoiignore 的注释
# 本身就写着「install.sh 直接遍历源目录复制…不读取本文件」，这条就是要补的差。
#
# 语义与 chezmoi 对齐：
#   · 精确路径   → 只在目标**不存在**时部署（新机器仍拿到一份可用默认值）
#   · glob / 目录 → 一律跳过（缓存、字节码、插件 git 元数据、UI 写回的配置）
chezmoi_ignore_kind() {
    local target="$1"
    local ignore_file="$SRC/.chezmoiignore"
    local line pat tp
    [[ -f $ignore_file ]] || return 0
    while IFS= read -r line || [[ -n $line ]]; do
        pat="${line%%#*}"                                  # 去注释
        pat="${pat#"${pat%%[![:space:]]*}"}"               # 去首空白
        pat="${pat%"${pat##*[![:space:]]}"}"               # 去尾空白
        [[ -z $pat ]] && continue
        if [[ $pat == */ ]]; then                          # 目录
            [[ $target == "$pat"* ]] && { printf 'skip'; return 0; }
            continue
        fi
        if [[ $pat == *'**'* ]]; then                      # **/X → 任意深度的 X
            tp="${pat##*\*\*/}"
            [[ $target == $tp || $target == */"$tp" || $target == */"$tp"/* ]] \
                && { printf 'skip'; return 0; }
            continue
        fi
        if [[ $pat == *'*'* ]]; then                       # 单层 glob
            # shellcheck disable=SC2254
            case "$target" in $pat) printf 'skip'; return 0 ;; esac
            continue
        fi
        [[ $target == "$pat" ]] && { printf 'keep'; return 0; }
    done < "$ignore_file"
    return 0
}

# 部署单个源文件到 $HOME（[5/7] 的循环体）。
#
# $1 = 源文件绝对路径
# $2 = 目标目录（绝对路径，已含 $HOME 前缀）
# $3 = 目标文件名（含 chezmoi 属性前缀）
#
# 依赖调用方设置的全局量：
#   $backup_dir  有差异的旧文件备份根
#   $backed      备份计数（本函数自增）
#
# 抽成独立函数是为了**能脱离 pacman / AUR / 网络单独测**：这段逻辑以前内联在
# [5/7] 的 while 里，只能靠跑一遍完整安装来验证，而完整安装要 sudo。
deploy_one_file() {
    local f="$1" dir="$2" base="$3"

    # ── chezmoi 属性前缀 ────────────────────────────────────────────
    # 本脚本直接遍历源目录复制，不经过 chezmoi，所以得自己认这些前缀；
    # 漏认的后果是**把前缀当成文件名的一部分部署出去**（静默故障：
    # 文件在、名字错、程序读不到）。
    #   executable_ → 剥前缀 + chmod +x
    #   private_    → 剥前缀 + chmod 600
    #                 （fcitx5 的 config / conf/*.conf 用它；fcitx5 会写回
    #                   这些文件，权限不对会改不动）
    #   symlink_    → 剥前缀 + 建符号链接，文件**内容**就是链接目标
    #                 （systemd/user/symlink_mako.service 内容为 /dev/null，
    #                   用来屏蔽系统 mako 服务，避免和 quickshell 的
    #                   通知服务抢 org.freedesktop.Notifications）
    # ⚠ create_ **不在此列**，必须保持字面文件名：chezmoi 的 create_ 语义是
    #   「不存在才创建」并会剥前缀，但 hyprland/services/init.lua 里写的是
    #   require("hyprland/services/create_custom_config")，剥成
    #   custom_config.lua 反而 require 不到 —— .chezmoiignore 里记的就是
    #   这个冲突。所以这里只认上面三个。
    # 前缀可以叠加（private_executable_xxx），所以用循环而不是 if。
    local execbit=0 private=0 symlink=0
    while :; do
        case "$base" in
            executable_*) base="${base#executable_}"; execbit=1 ;;
            private_*)    base="${base#private_}";    private=1 ;;
            symlink_*)    base="${base#symlink_}";    symlink=1 ;;
            *) break ;;
        esac
    done

    mkdir -p "$dir"

    # ── .chezmoiignore：与 chezmoi 对齐（见 chezmoi_ignore_kind 的说明）──
    # 必须在备份/写入之前判断：否则既会白备份，又会把运行时生成物
    # （matugen 配色等）用仓库旧快照覆盖掉。
    local target_rel
    if [[ "$dir" == "$HOME" ]]; then target_rel="$base"; else target_rel="${dir#"$HOME"/}/$base"; fi
    case "$(chezmoi_ignore_kind "$target_rel")" in
        skip)
            ignored_skip=$((ignored_skip + 1))
            return 0
            ;;
        keep)
            # 运行时生成物且目标已存在：保留用户当前值，不动也不备份
            if [[ -e "$dir/$base" || -L "$dir/$base" ]]; then
                ignored_keep=$((ignored_keep + 1))
                return 0
            fi
            ;;
    esac

    # 有差异才备份。符号链接不能直接 cmp（会跟随链接比到目标文件，
    # 比如 mako.service -> /dev/null 会变成拿 /dev/null 的内容去比），
    # 得比链接本身。
    if [[ -e "$dir/$base" || -L "$dir/$base" ]]; then
        local differs=0
        if [[ -L "$dir/$base" ]]; then
            [[ "$(readlink "$dir/$base")" == "$(head -n1 "$f")" ]] || differs=1
        elif [[ -f "$dir/$base" ]]; then
            cmp -s "$f" "$dir/$base" || differs=1
        else
            differs=1
        fi
        if ((differs)); then
            mkdir -p "$backup_dir/$dir"
            # -a 而不是 -p：备份符号链接时要保留链接本身，不能解引用
            cp -a "$dir/$base" "$backup_dir/$dir/$base"
            backed=$((backed + 1))
        fi
    fi

    if ((symlink)); then
        ln -sfn "$(head -n1 "$f")" "$dir/$base"
    else
        cp "$f" "$dir/$base"
        if ((execbit)); then chmod +x "$dir/$base"; fi
        if ((private)); then chmod 600 "$dir/$base"; fi
    fi
}

# ============================================================
# 3. 安装（7 步流程，封装进 cmd_install）
# ============================================================
cmd_install() {
    # install 不接收位置参数；多打了参数（如 install niri）多半是想表达
    # SESSION —— 提醒正确的用法，静默忽略会让人以为参数生效了。
    if (($#)); then
        warn "install 不接受参数，已忽略: $*（选会话请用 SESSION=dms|caelestia|end4pc $0 install）"
    fi
    [[ -f /etc/arch-release ]] || die "本安装器仅支持 Arch Linux 系发行版（CachyOS / Arch 等）。"
    [[ ${EUID} -eq 0 ]] && die "请勿用 root 运行（makepkg/AUR 步骤需要普通用户）。"
    have pacman || die "找不到 pacman。"

    ensure_dirs
    session_warning_if_running

    # 关键：在部署之前先保存原始配置快照（回档的基础）
    say "[0/7] 安装前自动保存当前配置快照（回档用）"
    snapshot_current "$PRE_INSTALL_PREFIX" current || warn "创建 pre-install 快照失败（可继续安装，但 rollback 将不可用）"

    # ---------- [1/7] 基础工具 + 会话依赖（一次 pacman 搞定） ----------
    say "[1/7] 安装基础工具与会话依赖"
    # 合成器本体与 portal 由 choose_session 的结果决定，单独追加到最后
    choose_session
    choose_fonts
    PACMAN_PKGS=(
        git base-devel github-cli
        # starship：fish 默认提示符（config.fish 里 starship init fish | source），
        # matugen 还有 templates/starship.toml 取色模板。缺了就是
        # 「有 ~/.config/starship.toml、提示符却是原生 fish」这类静默故障。
        starship
        kitty jq fish fuzzel
        grim wl-clipboard wtype playerctl
        fcitx5 fcitx5-rime fcitx5-configtool
        # xorg-xcursorgen：generate_cursor_theme.py 把重着色后的 SVG 重编成
        #   XCursor 主题的工具（librsvg 的 rsvg-convert 负责前半段渲染）。
        #   缺了同样卡死光标生成，报错只有一句 "required tool missing"。
        xorg-xcursorgen
        cliphist easyeffects hypridle hyprlock
        gnome-keyring
        python
        # procps-ng 提供 ps 命令，仪表盘系统页的进程列表依赖它
        # （base 组已含，这里显式声明以防万一被精简掉）
        procps-ng
        # psmisc 提供 killall。hypr 的 CTRL+SUPER+R（重启 quickshell）是
        # hl.exec_cmd("killall ydotool qs quickshell; qs -c $qsConfig &")，
        # 这是真调用不是注释；killall 属 psmisc，与 procps-ng 的 pkill/pgrep
        # 不是一个包，别指望顺带带入。
        psmisc
        # libnotify 提供 notify-send：19 个配置文件靠它上报结果与报错
        # （switchwall 配色、截图、录屏、随机壁纸、强制关窗……）。
        # 缺了不只是"少个气泡"——模糊壁纸脚本把它写进 DEPENDENCIES，
        # 缺失时直接 exit 1，连"缺依赖"这件事都报不出来。
        libnotify
        # imagemagick 提供 magick：与上面同一个脚本的 DEPENDENCIES 里和
        # notify-send 并列，负责总览模糊底图的高斯模糊与填充着色（IMG_BLUR_*
        # / IMG_COLORIZE_*），缺了同样 exit 1。
        imagemagick
        # ffmpeg：视频缩略图 / 动态取色（DMS 的 mpvpaper 视频壁纸插件依赖它）。
        # 通用工具，别的 shell 也可能用到，保留在基础列表。
        ffmpeg
        # wf-recorder：屏幕录制。end4-PC 的录屏实现（scripts/videos/record.sh）
        # 直接调它，RegionSelection 也用 `pidof wf-recorder` 判断录制状态；
        # dms 用 gpu-screen-recorder，多装一个不碍事。
        wf-recorder
        # wget：fish 的 `wget` 包装函数（下载进度上报灵动岛，见
        # dot_config/fish/functions/wget.fish）内部是 `command wget`，
        # 缺了那个函数直接失效。脚本自身只用 curl，以前一直靠依赖顺带带入。
        wget
        # songrec（Shazam 客户端）：end4-PC 的音乐识别
        # （scripts/musicRecognition/recognize-music.sh 硬依赖，翻译表里也写了
        #   「请确保你已安装 songrec」）。在官方仓库 extra 里。
        songrec
        # 登录管理器：SDDM（主题用 Catppuccin Mocha，见 docs/login-screen.md）
        # 注意：若机器上用的是 plasmalogin（KDE 新版 DM），两者可共存，
        # 切换只需 systemctl disable/enable，见文档。
        sddm
        # ---- Neovim 生态 ----
        # 配置在 dot_config/nvim/（LazyVim）。**编辑器本体必须在这里显式声明**：
        # 之前只跟踪了配置、没跟踪包，新机器装完是「有配置、没编辑器」，
        # 而且 install.sh 不会报任何错——和字体漏装是同一类静默故障。
        # ripgrep / fd：Telescope 找文件与全局搜索的后端，缺了会静默回退到更慢的 find。
        # fzf：fish 的 fzf 绑定，以及 telescope-fzf-native 的构建基础。
        # lazygit：<leader>gg 的前提，缺了那个键位根本不存在（LazyVim 有 executable 守卫）。
        # tree-sitter-cli：手动编译/调试语法解析器用。
        neovim ripgrep fd fzf lazygit tree-sitter-cli
        # neovide：nvim 的 GUI 前端。字体对齐 kitty，
        # 见 dot_config/neovide/config.toml。
        neovide
        # quickshell 源码编译工具链（三级回退时使用，平时不碍事）
        cmake ninja
        qt6-base qt6-declarative qt6-wayland qt6-5compat qt6-shadertools qt6-svg
        wayland-protocols
    )
    # 追加合成器相关包（niri 或 hyprland + 对应 portal）
    # shellcheck disable=SC2207
    PACMAN_PKGS+=($(compositor_pkgs))
    say "    合成器相关包: $(compositor_pkgs)"
    # 追加 shell 专属包（dms 的录屏工具；caelestia / end4-pC 无）
    local _shell_pkgs; _shell_pkgs="$(shell_pacman_pkgs)"
    if [[ -n "$_shell_pkgs" ]]; then
        # shellcheck disable=SC2207
        PACMAN_PKGS+=($_shell_pkgs)
        say "    $QS_SHELL 专属包: $_shell_pkgs"
    fi
    # 追加 quickshell 会话公共包（Caelestia 插件编译 / 运行依赖）。
    # ⚠ end4-pC 也编这个插件（锁屏硬依赖），所以不在 shell 分支里。
    local _base_pkgs; _base_pkgs="$(base_pacman_pkgs)"
    if [[ -n "$_base_pkgs" ]]; then
        # shellcheck disable=SC2207
        PACMAN_PKGS+=($_base_pkgs)
        say "    Caelestia 插件依赖: $_base_pkgs"
    fi
    # 字体包是可选项（见 choose_fonts）：不想被塞 200MB+ 的字体链就 FONTS=0。
    #   ttf-jetbrains-mono-nerd  kitty 终端的 Nerd 图标
    #   noto-fonts-cjk           按语言切换 CJK 字形的全部地区变体（JP/KR/TC/HK），
    #                            装包本身会自动 fc-cache
    #   adobe-source-han-sans-cn 思源黑体 CN：不再走 fontconfig 别名，但 GTK
    #                            settings.ini 与 fcitx5 classicui.conf 硬编码了它
    if fonts_enabled; then
        # shellcheck disable=SC2207
        PACMAN_PKGS+=(ttf-jetbrains-mono-nerd ttf-nerd-fonts-symbols
                      noto-fonts noto-fonts-cjk noto-fonts-emoji
                      adobe-source-han-sans-cn-fonts)
        say "    字体（pacman）: Nerd Mono / Noto CJK / 思源黑体"
    else
        say "    字体: 已跳过（FONTS=0），不安装任何系统字体包"
    fi
    # 默认只安装缺失的包，不做全系统升级（避免在你没准备时滚动整个系统）。
    # 需要全量升级时：FULL_UPGRADE=1 ./install.sh install
    if [[ "${FULL_UPGRADE:-0}" == "1" ]]; then
        say "    FULL_UPGRADE=1：执行全系统升级（pacman -Syu）"
        "${SUDO:-sudo}" pacman -Syu --needed --noconfirm "${PACMAN_PKGS[@]}" \
            || die "全系统升级失败。常见原因是镜像未同步或密钥过期：先手动执行 sudo pacman -Syu && sudo pacman -S archlinux-keyring 后重试。"
    else
        "${SUDO:-sudo}" pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}" \
            || die "依赖安装失败。若提示找不到包，先手动执行 sudo pacman -Syu 更新软件库后重试。"
    fi

    # ---------- [2/7] AUR 包（通用 + 所选 shell 专属） ----------
    say "[2/7] AUR 依赖"
    if ! have yay && ! have paru; then
        say "    未找到 AUR helper，引导安装 yay（编译约 1-2 分钟，需要 base-devel）"
        tmpdir="$(mktemp -d)"
        git clone --depth=1 https://aur.archlinux.org/yay.git "$tmpdir/yay" \
            || die "克隆 yay 失败（检查网络后重试；也可先手动安装 paru/yay，装好后重跑会跳过本步）"
        (cd "$tmpdir/yay" && makepkg -si --noconfirm) \
            || die "yay 编译/安装失败，见上方输出。手动装好 paru 或 yay 后重跑即可跳过本步。"
        rm -rf "$tmpdir"
    fi
    # 通用 AUR 包：
    #   matugen                壁纸 → Material 3 全局取色
    #   mpvpaper               视频壁纸
    #   walker                 Hyprland 侧的启动器/剪贴板前端。三处都依赖它：
    #                            hypr/custom/keybinds.lua  SUPER+V → `walker -m clipboard`
    #                            hypr/hyprland/rules.lua   layer rule（namespace="walker"）
    #                            matugen/config.toml       [templates.walker] → ~/.config/walker/themes/matugen
    #                          缺了就是「SUPER+V 按了没反应」+ walker 主题目录不存在。
    # catppuccin-sddm-theme-mocha：SDDM 登录界面主题（Qt6，需 SDDM 走 Wayland）
    # qt6-svg / qt6-declarative / qt5-quickcontrols2 是它的依赖，AUR 包会带入。
    # catppuccin-cursors-mocha：光标主题模板源。generate_cursor_theme.py 以
    #   catppuccin-mocha-pink-cursors 为底、按 matugen 主色重着色生成
    #   ~/.local/share/icons/Matugen-Cursors（环境里 XCURSOR_THEME 引用的就是它）。
    #   缺了脚本直接 "generation failed"，光标永远回退默认。
    AUR_PKGS=(matugen mpvpaper walker catppuccin-sddm-theme-mocha catppuccin-cursors-mocha)
    # 字体链（可选，见 choose_fonts；偏好链在 ~/.config/fontconfig/fonts.conf）：
    #   otf-misans             sans-serif 默认（MiSans）
    #   maplemononormal-nf-cn  monospace 默认（自带 Nerd 图标 + 中文）
    #   ttf-lxgw-wenkai-screen serif 回退链第二位
    #   ttf-lxgw-wenkai-tc     繁中衬线（lang=zh-tw / zh-hk 时启用）
    #   ttf-lxgw-wenkai        楷体，供硬编码霞鹜文楷的组件回退
    # ⚠ AUR 包名不规则：上游 README 写的 ttf-maplemononormal-nf-cn 并不存在，
    #   实际是 maplemononormal-nf-cn（无 ttf- 前缀）。
    if fonts_enabled; then
        AUR_PKGS+=(otf-misans maplemononormal-nf-cn
                   ttf-lxgw-wenkai ttf-lxgw-wenkai-screen ttf-lxgw-wenkai-tc)
        say "    字体（AUR）  : MiSans / Maple Mono NF / 霞鹜文楷三兄弟"
    fi
    # 追加合成器本体的 AUR 包（见 compositor_aur_pkgs：
    #   niri → niri-shorin-fork-git，hyprland → 官方仓库已装，无）
    local _comp_aur; _comp_aur="$(compositor_aur_pkgs)"
    if [[ -n "$_comp_aur" ]]; then
        # fork 声明 conflicts niri，所以官方 niri / niri-bin / niri-spicy-git
        # 在的话 AUR helper 会因冲突直接失败（且 --noconfirm 下无法自动确认卸载）。
        # 这里只提示不代劳：卸载合成器会停掉当前会话，得你自己决定时机。
        # 用 -Rdd 是为了不连带卸掉依赖 niri 的 dms-shell-niri。
        local _conflict
        for _conflict in niri niri-bin niri-spicy-git; do
            if pacman -Q "$_conflict" >/dev/null 2>&1; then
                warn "已装 $_conflict，与 $_comp_aur 冲突（conflicts niri）"
                say "    先卸掉再继续：sudo pacman -Rdd $_conflict"
                say "    （-Rdd 跳过依赖检查，避免连带卸掉 dms-shell-niri）"
            fi
        done
        # shellcheck disable=SC2207
        AUR_PKGS+=($_comp_aur)
        say "    合成器本体（AUR）: $_comp_aur"
    fi
    # 追加 shell 专属 AUR 包（见 shell_aur_pkgs：
    #   caelestia → 无（与 end4-pC 共用公共列表）
    #   dms       → dms-shell-git dms-shell-niri）
    # shellcheck disable=SC2207
    AUR_PKGS+=($(shell_aur_pkgs))
    # quickshell 会话公共 AUR 包（libcava / qt6-m3shapes-git）。
    # ⚠ end4-pC 也需要：Caelestia 插件编译 + 锁屏 MaterialShape 形变动画。
    # shellcheck disable=SC2207
    AUR_PKGS+=($(base_aur_pkgs))
    for p in "${AUR_PKGS[@]}"; do
        if pacman -Q "$p" >/dev/null 2>&1; then
            echo "    已安装: $p"
        elif aur_install "$p"; then
            echo "    AUR 安装成功: $p"
        else
            warn "$p 安装失败（不影响其余功能，可稍后手动安装）"
        fi
    done
    have fcitx5 || warn "fcitx5 未就绪，中文输入暂不可用（fcitx5-rime 依赖应已带入）"

    # ---------- [3/7] quickshell 三级回退 ----------
    say "[3/7] quickshell"
    install_quickshell() {
        if have qs; then
            echo "    已安装: $(qs --version 2>/dev/null | head -1)"
            return 0
        fi
        if in_sync_db quickshell; then
            echo "    从二进制仓库安装"
            "${SUDO:-sudo}" pacman -S --needed --noconfirm quickshell && return 0
        fi
        if [[ -n $(aur_helper) ]] && aur_install quickshell-git; then
            echo "    已从 AUR 安装 quickshell-git"
            return 0
        fi
        echo "    从源码编译（tag v0.3.1，需要几分钟）"
        "${SUDO:-sudo}" pacman -S --needed --noconfirm cmake ninja qt6-base qt6-declarative qt6-wayland qt6-5compat qt6-shadertools qt6-svg wayland-protocols
        local src; src="$(mktemp -d)"
        git clone --depth=1 --branch v0.3.1 https://github.com/outfoxxed/quickshell.git "$src" \
            || git clone --depth=1 https://github.com/outfoxxed/quickshell.git "$src" \
            || die "克隆 quickshell 源码失败（检查网络后重试；也可以从 GitHub Releases 手动下载二进制放进 PATH）"
        cmake -S "$src" -B "$src/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
            || die "quickshell CMake 配置失败，见上方输出（通常是缺 Qt6 组件）。"
        cmake --build "$src/build" --parallel \
            || die "quickshell 编译失败，见上方输出。"
        "${SUDO:-sudo}" cmake --install "$src/build" \
            || die "quickshell 安装到 /usr/local 失败，见上方输出。"
        rm -rf "$src"
    }
    install_quickshell
    have qs || die "quickshell 安装失败，请检查上方输出。"

    # ---------- [4/7] 桌面 Shell（按 choose_session 的结果三选一） ----------
    say "[4/7] 桌面 Shell（$QS_SHELL）"

    # ---------- [4a/7] Caelestia QML 插件（end4-pC 与 caelestia 都需要） ----------
    #
    # ⚠ 这不是 caelestia 专属步骤 —— 它是 end4-pC 的硬前置。
    #
    # end4-pC 差异层里的锁屏（modules/ii/lock/caelestia/**）是从
    # caelestia-dots/shell 原样 vendor 过来的，其中 **56 个文件**写着
    # `import Caelestia.Config`（Tokens.anim.* / AnimCurves）。QML 的
    # `import <模块>` 是硬依赖：模块解析不到时，该文件里的类型全部 unavailable，
    # 错误沿
    #     CaelestiaLockSurface → Lock → IllogicalImpulseFamily → shell.qml
    # 一路上抛，最终 `qs -c end4-pC` 直接 "Failed to load configuration"，
    # 表现为**登录后桌面残缺或只剩光标**。
    #
    # 历史写法是按 $QS_SHELL 分支决定编不编这个插件（只在 caelestia 分支编），
    # 于是选 end4-pC 的机器永远拿不到插件 —— 这就是本次要修的 bug。
    #
    # 插件 QML 源码在 caelestia-dots/shell 仓库的 plugin/ 下；本仓库的覆盖层
    # （dot_config/quickshell/caelestia/）提供汉化 po 与改过的 CMakeLists。
    # 所以这里无论如何都要：拿到源码 → 应用覆盖层 → out-of-source 编译到
    # $HOME/src/caelestia-build。
    #
    # ── 存放规则（单一事实来源，改这里要连带改下面这张表的所有读者）──────
    #
    #   | 用途                | 路径                              | 谁写      | 进快照/归档 |
    #   |---------------------|-----------------------------------|-----------|-------------|
    #   | 编译源码（构建输入）| ~/src/caelestia-plugin-src        | [4a/7]    | 否          |
    #   | 编译产物（QML 模块）| ~/src/caelestia-build/qml         | [4a/7]    | 否          |
    #   | 覆盖层（仓库内）    | dot_config/quickshell/caelestia/  | 仓库      | —           |
    #   | end4-PC shell 配置  | ~/.config/quickshell/end4-pC      | [4b/7]+[5/7] | 是       |
    #   | caelestia shell 配置| ~/.config/quickshell/caelestia    | [4b/7]+[5/7] | 是       |
    #
    # 两条硬规则：
    #   1. **源码与产物都在 $HOME/src，不在 $HOME/.config/quickshell 下。**
    #      后者是 quickshell 的配置命名空间（quickshell 按
    #      `<config>/quickshell/<名字>/shell.qml` 发现配置），往里放 clone 等于
    #      凭空多出一套可运行的 shell（`qs -c caelestia`），而且会被
    #      SNAP_PATHS / EXTRA_ARCHIVE_PATHS 整包打进快照与归档。
    #      旧版本正是把源码放在 ~/.config/quickshell/caelestia（复用 caelestia
    #      shell 的 clone），既污染命名空间，又让"哪些文件是配置、哪些是构建
    #      输入"彻底糊在一起。
    #   2. **只有 ~/src/caelestia-build/qml 会被 QML2_IMPORT_PATH 指向。**
    #      读者只有两处：fish/config.fish（手动跑 qs）与
    #      hyprland/scripts/start_quickshell.sh（会话自启）。
    #      换位置要同步改那两处 —— 以前注释里还写着 execs.lua，早就不存在了。
    install_caelestia_plugin() {
        local src="$HOME/src/caelestia-plugin-src"
        local build="$HOME/src/caelestia-build"

        # 1) 插件源码来源：浅克隆一份独立的源码树。只用到 plugin/ 子目录
        #    （编译时由 -DENABLE_MODULES=plugin 限定，见第 3 步），
        #    不需要 caelestia 的 shell 本体。
        if [[ ! -d "$src/plugin" ]]; then
            say "    克隆 caelestia 源码（为编译 Caelestia QML 插件）"
            mkdir -p "$(dirname "$src")"
            git clone --depth=1 https://github.com/caelestia-dots/shell.git "$src" \
                || die "克隆 caelestia-dots/shell 失败（Caelestia 插件源码，检查网络后重试）。"
        else
            echo "    已存在插件源码: $src/plugin"
        fi

        # 2) 本地覆盖层（汉化 po / 改过的 CMakeLists）。
        #    ⚠ 必须在编译前应用：晚一步这些文件赶不上这次编译，翻译会静默不生效。
        local overlay="$SRC/dot_config/quickshell/caelestia"
        local ovl_hash=""
        if [[ -d "$overlay" ]]; then
            while IFS= read -r -d '' rel; do
                mkdir -p "$src/$(dirname "${rel#./}")"
                cp -a "$overlay/$rel" "$src/${rel#./}"
            done < <(cd "$overlay" && find . -type f -print0)
            ovl_hash="$(cd "$overlay" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16)"
            echo "    已应用 caelestia 覆盖层（$(cd "$overlay" && find . -type f | wc -l) 个文件）"
        fi

        # 3) 编译。幂等：已有 .so 产物**且覆盖层没变**才跳过 —— 否则改了
        #    po/CMakeLists 却不重编，会静默停留在旧版本。
        local stamp="$build/.overlay-stamp"
        if compgen -G "$build/qml/Caelestia/*.so" >/dev/null \
            && [[ -f "$stamp" && "$(cat "$stamp")" == "$ovl_hash" ]]; then
            echo "    已编译: $build/qml（覆盖层无变化）"
            return 0
        fi

        # 3a) 构建目录与源码路径必须配对。
        #     CMakeCache.txt 里记着 CMAKE_HOME_DIRECTORY（= 上次 -S 的源码目录）。
        #     源码位置换过（旧版本是 ~/.config/quickshell/caelestia）之后直接复用
        #     旧构建目录，CMake 会拿缓存里的老路径去找 CMakeLists —— 表现为
        #     "配置失败" 或更糟：配置通过、链接到已删除的目标文件。
        #     检测到不匹配就整个清掉重配。这也是"编译流程与存放规则一致"的一部分：
        #     源码路径是这条链的单一事实来源，改它必须连带作废旧构建。
        if [[ -f "$build/CMakeCache.txt" ]]; then
            local _cached_src
            _cached_src="$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "$build/CMakeCache.txt" | head -1)"
            if [[ -n "$_cached_src" && "$_cached_src" != "$src" ]]; then
                warn "构建目录的源码路径已变（$_cached_src → $src），清空后重新配置"
                rm -rf "$build"
            fi
        fi

        have cmake && have ninja || die "缺少 cmake/ninja，无法编译 Caelestia 插件（end4-pC 锁屏硬依赖）。"
        # 上游 CMakeLists 对 git 有硬依赖：`git describe --tags` 拿 VERSION、
        # `git rev-parse HEAD` 拿 GIT_REVISION，任一为空就 FATAL_ERROR 中断安装。
        # shallow clone 默认没有 tag；源码若是被拷进来的（无 .git）两个都拿不到。
        # 所以两个变量都由这里显式算出并传入，CMakeLists 的 git 调用就走不到了。
        ( cd "$src" && git fetch --tags --depth=1 --quiet 2>/dev/null ) || true
        local _cv="" _rev=""
        _cv="$(cd "$src" && git describe --tags --abbrev=0 2>/dev/null || true)"
        _rev="$(cd "$src" && git rev-parse HEAD 2>/dev/null || true)"
        [[ -z "$_cv" ]] && _cv="0.0.0"
        [[ -z "$_rev" ]] && _rev="unknown"
        say "    编译 Caelestia QML 插件（约 1-3 分钟），version=$_cv rev=${_rev:0:7}"
        # ⚠ -DENABLE_MODULES=plugin 是必须的，不是优化：
        #   上游根 CMakeLists 默认 ENABLE_MODULES="extras;plugin;shell"，
        #   其中 shell 会 add_subdirectory 整个 caelestia shell 应用
        #   （assets/components/modules/services/utils）。我们要的只是 QML 模块
        #   （Caelestia.Config / .Services / .Components / .Images / .Models /
        #   .Blobs / .I18n），它们全在 plugin/ 下，与 shell/ 无依赖关系。
        #   不限定的话会白编一个用不到的桌面 shell，多花几分钟，还多一堆
        #   只有 shell 才需要的依赖。
        local _cmake_args=(
            -S "$src" -B "$build" -G Ninja
            -DCMAKE_BUILD_TYPE=RelWithDebInfo
            -DENABLE_MODULES=plugin
            -DVERSION="${_cv#v}" -DGIT_REVISION="$_rev"
        )
        cmake "${_cmake_args[@]}" \
            || die "Caelestia 插件 CMake 配置失败，见上方输出。"
        cmake --build "$build" --parallel \
            || die "Caelestia 插件编译失败，见上方输出。手动重试：cmake ${_cmake_args[*]} && cmake --build $build"

        # 3b) 产物自检。没有它的话，一次"看起来成功但没产出"的编译会把 stamp
        #     写下去，下一轮直接被当成"已编译"跳过 —— 插件对 qs 而言永远不存在，
        #     而且是静默的。
        if ! compgen -G "$build/qml/Caelestia/*.so" >/dev/null; then
            die "编译结束但 $build/qml/Caelestia/*.so 不存在 —— 插件没有真正产出，见上方 cmake 输出。"
        fi
        printf '%s\n' "$ovl_hash" > "$stamp"
        echo "    编译完成: $build/qml（由 fish/config.fish 与 start_quickshell.sh 自动加载）"
    }

    # end4-PC 底盘（end-4 illogical-impulse 定制 fork，pctrade/end4-PC）：
    # 本仓库只跟踪差异层（dot_config/quickshell/end4-pC），底盘本体从这里拉。
    # 完整性自检见顶层函数 end4pc_base_missing()（放在顶层是为了能单独测）。
    install_end4pc_shell() {
        local dst="$HOME/.config/quickshell/end4-pC"
        # 无条件先清：即使底盘判定为"完整"而提前 return，历史上误拷进来的
        # .git 也该走（它从来没被用过，只会占空间并被快照整包打包）。
        cleanup_stray_git "$dst"
        # ⚠ 命令替换里 set -e 不生效，但赋值语句的退出码取自替换结果，
        #   所以 `|| true` 不能省：end4pc_base_missing 返回 1（=完整）时
        #   会让 `missing=...` 整体非零退出。
        local missing=""
        if [[ -e "$dst/shell.qml" ]]; then
            missing="$(end4pc_base_missing || true)"
            if [[ -z "$missing" ]]; then
                echo "    已存在且完整: $dst"
                return 0
            fi
            warn "底盘不完整（缺少 $missing），重新拉取一份覆盖"
            warn "  旧目录已在 [0/7] 的 pre-install 快照里（$SNAP_ROOT），"
            warn "  需要还原时跑：./install.sh rollback"
        fi
        say "    拉取 quickshell 底盘 (pctrade/end4-PC)"
        # 注意：不能直接 clone 进 $dst —— 目录已存在且非空时 git clone 会失败，
        # 而 set -e 会让整个安装中断。先克隆到临时目录再合并进去。
        local tmp; tmp="$(mktemp -d)"
        if git clone --depth=1 https://github.com/pctrade/end4-pC.git "$tmp/end4-PC"; then
            merge_clone_into "$tmp/end4-PC" "$dst"
            # 覆盖完立刻自检：网络中断 / 磁盘满都可能让 cp 半途而废，
            # 别让用户拿到一个"看起来装好了"的残缺树。
            # ⚠ 基准是刚 clone 下来的那份（而不是硬编码清单），并且必须在
            #   `rm -rf "$tmp"` 之前取值。
            missing="$(base_tree_missing "$tmp/end4-PC" "$dst" || true)"
        else
            rm -rf "$tmp"
            die "拉取 quickshell 底盘失败（检查网络后重试，或手动 clone 到 $dst）"
        fi
        rm -rf "$tmp"
        if [[ -n "$missing" ]]; then
            die "底盘拉取后仍缺少 $missing —— 请检查网络与磁盘空间后重跑。"
        fi
        echo "    底盘完整"
    }

    # caelestia shell：本体 clone（QML 插件由 [4a/7] install_caelestia_plugin 统一处理）。
    #
    # ⚠ 这是**唯一**应该出现在 ~/.config/quickshell/ 下的东西，且只在选了
    #   caelestia 时才 clone。[4a/7] 现在把插件源码放在 $HOME/src，不再顺带
    #   往这里塞 clone，所以本体得自己拉。
    install_caelestia_shell() {
        local dst="$HOME/.config/quickshell/caelestia"
        # 同 install_end4pc_shell：先清掉可能存在的历史遗留 .git
        cleanup_stray_git "$dst"
        if [[ -f "$dst/shell.qml" ]]; then
            echo "    已存在: $dst"
            return 0
        fi
        say "    拉取 caelestia shell 本体"
        # 同 end4-PC：目录可能已存在且非空，先克隆到临时目录再合并。
        local tmp; tmp="$(mktemp -d)"
        if git clone --depth=1 https://github.com/caelestia-dots/shell.git "$tmp/shell"; then
            merge_clone_into "$tmp/shell" "$dst"
        else
            rm -rf "$tmp"
            die "拉取 caelestia shell 失败（检查网络后重试，或手动 clone 到 $dst）"
        fi
        rm -rf "$tmp"
        [[ -f "$dst/shell.qml" ]] || die "caelestia shell 本体仍然缺失：$dst/shell.qml"
        echo "    已拉取: $dst"
    }

    install_shell() {
        case "$QS_SHELL" in
            caelestia) install_caelestia_shell ;;
            dms)       echo "    DMS 由 AUR 安装（dms-shell-git + dms-shell-niri），无需额外部署" ;;
            *)         install_end4pc_shell ;;
        esac
    }
    # ⚠ 顺序：插件必须先于 shell 本体处理（end4-pC 的锁屏硬依赖它，见 [4a/7]）。
    #    dms 不走 quickshell，跳过 —— 不给纯 niri 用户多拉一份 caelestia 源码。
    if [[ "$QS_SHELL" != "dms" ]]; then
        install_caelestia_plugin
    fi
    install_shell

    # ---------- [5/7] 部署 dotfiles ----------
    say "[5/7] 部署配置文件"
    backup_dir="$BACKUP_ROOT/$(now_ts)"
    installed=0; backed=0; skipped=0; skipped_shell=0
    ignored_skip=0; ignored_keep=0
    while IFS= read -r -d '' f; do
        rel="${f#"$SRC"/}"
        case "$rel" in
            .git/*|install.sh|README.md|LICENSE) continue ;;
            dot_*) out="$HOME/.${rel#dot_}" ;;
            *) continue ;;
        esac
        # 只部署选中的那套合成器配置；另一套一个字节都不碰
        # （见 skip_by_compositor 的说明，INSTALL_BOTH_COMPOSITORS=1 可两套都装）
        if skip_by_compositor "$rel"; then
            skipped=$((skipped + 1))
            continue
        fi
        # 只部署选中 shell 的差异层（见 skip_by_shell）
        if skip_by_shell "$rel"; then
            skipped_shell=$((skipped_shell + 1))
            continue
        fi
        base="${out##*/}"; dir="${out%/*}"
        deploy_one_file "$f" "$dir" "$base"
        installed=$((installed + 1))
    done < <(find "$SRC" -type f -print0)
    say "已部署 $installed 个文件；$backed 个有差异的旧文件备份于 $backup_dir"
    if ((ignored_skip || ignored_keep)); then
        echo "    按 .chezmoiignore 跳过 $ignored_skip 个（缓存/字节码/插件元数据/UI 写回的配置）；"
        echo "    $ignored_keep 个运行时生成物已存在，保留当前值不覆盖（matugen 配色等）。"
        echo "    想强制用仓库快照覆盖它们：先删掉目标文件再重跑安装。"
    fi
    if ((skipped)); then
        if [[ "$COMPOSITOR" == "niri" ]]; then other=hypr; else other=niri; fi
        warn "已跳过 $skipped 个文件：未选择的另一套合成器 ~/.config/$other 原样保留，一个字节都没动。"
        warn "  想两套都部署：INSTALL_BOTH_COMPOSITORS=1 ./install.sh install"
    fi
    if ((skipped_shell)); then
        warn "已跳过 $skipped_shell 个文件：不属于所选 shell（$QS_SHELL）的差异层原样保留。"
    fi

    # ---------- [6/7] 拼音搜索环境与歌词缓存 ----------
    say "[6/7] 运行环境与歌词缓存"
    # 霞鹜臻楷 GB：serif 别名首选字体，AUR 没有对应包，只能从上游 GitHub Release
    # 取。放在 fc-cache 之前，装完当次就能进缓存；已存在则跳过（不重复下载 17MB）。
    # 与字体链绑定（见 choose_fonts）：FONTS=0 时一个字节都不下。
    if fonts_enabled; then
        lxgw_zhenkai="$HOME/.local/share/fonts/LXGWZhenKaiGB-Regular.ttf"
        if [[ ! -e "$lxgw_zhenkai" ]]; then
            mkdir -p "$HOME/.local/share/fonts"
            if have curl && curl -fsSL --retry 3 -o "$lxgw_zhenkai" \
                https://github.com/lxgw/LxgwZhenKai/releases/download/v0.825/LXGWZhenKaiGB-Regular.ttf; then
                echo "    已下载霞鹜臻楷 GB（serif 首选字体）"
            else
                rm -f "$lxgw_zhenkai"
                warn "霞鹜臻楷 GB 下载失败；serif 会回退到霞鹜文楷屏幕阅读版"
            fi
        fi
    fi

    # 字体缓存：pacman 装字体包时本身有 hook 会自动跑，这里再显式兜底一次，
    # 让用户手动放进 ~/.local/share/fonts/ 的字体在重跑脚本后也能生效。
    # 跳过字体时也跑：不动配置，只刷新缓存，对已有字体无副作用。
    if have fc-cache; then
        fc-cache -f >/dev/null 2>&1 || true
        echo "    字体缓存已刷新（fc-cache -f）"
    fi
    # 文泉驿的系统级配置（65-wqy-zenhei.conf）编号 65，晚于用户配置的
    # 50-user.conf 加载，会用 <prefer> 把文泉驿 / DejaVu 顶到
    # serif / sans-serif / monospace 最前面，压制 ~/.config/fontconfig 的设置。
    # 现在 sans-serif / serif / monospace 都有明确首选（MiSans / 霞鹜臻楷 / Maple Mono），
    # 文泉驿属于更低质量的兜底，去掉它。
    # 失败不影响安装。
    # ⚠ 只在装了推荐字体时才动：FONTS=0 时文泉驿是系统里唯一的中文兜底，
    #   禁掉会让中文衬线/无衬线直接掉回默认字体，比不动更糟。
    # ⚠ 这里曾经是 `rm -f`：删掉系统文件不可逆，而且 /etc 是**整机共享**的，
    #   隔壁 niri/DMS 那套会话、甚至其它用户都会跟着变 —— 安装脚本只该管
    #   自己的 $HOME。改成改名禁用：fontconfig 只加载 `*.conf`，
    #   后缀一变就不再生效，文件仍在，一条命令就能恢复。
    wqy_conf="/etc/fonts/conf.d/65-wqy-zenhei.conf"
    if fonts_enabled && [[ -e $wqy_conf ]]; then
        if "${SUDO:-sudo}" mv -f "$wqy_conf" "$wqy_conf.disabled-by-dotfiles" 2>/dev/null; then
            have fc-cache && fc-cache -f >/dev/null 2>&1 || true
            echo "    已禁用 /etc/fonts/conf.d/65-wqy-zenhei.conf（避免劫持 serif/中文字体）"
            echo "    恢复：sudo mv $wqy_conf.disabled-by-dotfiles $wqy_conf"
        else
            warn "未能禁用 65-wqy-zenhei.conf（需要 root）；serif 别名可能仍被文泉驿占用"
        fi
    fi
    mkdir -p "$HOME/.cache/quickshell/kugou_lyrics"
    VENV="$HOME/.local/state/quickshell/.venv"
    if [[ ! -x "$VENV/bin/python" ]]; then
        mkdir -p "$HOME/.local/state/quickshell"
        python -m venv "$VENV" \
            || die "创建 Python venv 失败（$VENV）。检查 python 是否完整（pacman -Q python）与磁盘是否可写。"
    fi
    # pypinyin            → 启动器的 app 中文名拼音搜索
    # dbus-python         → 同上（走 D-Bus 拿窗口/应用信息）
    # kde-material-you-colors → KDE/Qt 取色。switchwall.sh 会调
    #   matugen/templates/kde/kde-material-you-colors-wrapper.sh，而那个 wrapper
    #   第 70 行是 `command -v kde-material-you-colors || 跳过` —— 它是个 **pip 包**
    #   不是系统包，以前 venv 里没装，于是 KDE/Qt 配色每次都被静默跳过
    #   （日志里只有一句 "not installed in venv, skipping"，很容易漏掉）。
    "$VENV/bin/pip" install --upgrade --quiet pypinyin dbus-python kde-material-you-colors \
        || warn "venv 依赖安装失败——启动器的 app 中文名拼音搜索、KDE/Qt 取色会受影响，其余功能不受影响"

    # 图标主题：文件夹图标由 matugen 的 [templates.gtk-folder] 每次换壁纸
    # 自动重新着色（生成到 ~/.local/share/icons/Adwaita-Matugen-{A,B}）。
    # 这里只负责触发一次，让新机器装完就有主题，不用等用户手动换壁纸。
    # switchwall.sh 是 end4-PC 底盘里的脚本，只有选了 end4-pC 才有；
    # caelestia / DMS 各自在首次换壁纸时触发 matugen，不需要这里代劳。
    if [[ "$QS_SHELL" == "end4-pC" && -f "$HOME/.config/illogical-impulse/config.json" ]]; then
        nohup bash "$HOME/.config/quickshell/end4-pC/scripts/colors/switchwall.sh" --noswitch \
            >/dev/null 2>&1 &
        echo "    已触发一次 matugen 渲染（后台执行，图标主题会随之生成）"
    fi

    # ---------- [7/7] 完成 ----------
    say "[7/7] 完成！接下来的步骤："
    # 第 1 步与所选合成器相关，单独输出
    if [[ "$COMPOSITOR" == "niri" ]]; then
        echo "  1. 注销并重新登录，会话选择 \"niri\""
        echo "     （配置入口 ~/.config/niri/config.kdl；DMS 由 niri 的"
        echo "      spawn-at-startup 自启，登录界面为 plasmalogin）"
    else
        echo "  1. 注销并重新登录，会话选择 \"Hyprland\""
        echo "     （配置入口 ~/.config/hypr/hyprland.lua，Quickshell 随会话自启）"
    fi
    cat <<'EOF'
  2. 中文输入：fcitx5 + rime（SUPER+F1 可重启输入法）
  3. 键位速览：
       SUPER+L      锁屏
       SUPER+T      终端召唤（居中浮动，再按隐藏）
       SUPER+S      scratchpad
       SUPER        启动器（支持中文拼音搜索）
  4. 桌面歌词开关：设置 → 桌面 → 小部件
     （桌面歌词已解耦，自动适配 KA Music / Spotify / 浏览器等任意播放器）
  5. fish 设为默认 shell（可选）: chsh -s "$(command -v fish)"
EOF
    # 第 6 条按所选 shell 输出（三套各不相同）
    case "$QS_SHELL" in
        caelestia)
            cat <<'EOF'
  6. Caelestia QML 插件：已编译到 ~/src/caelestia-build/qml，
     由会话自启（start_quickshell.sh 注入 QML2_IMPORT_PATH）与 fish config.fish 自动加载。
EOF
            ;;
        dms)
            cat <<'EOF'
  6. DMS（DankMaterialShell）：由 niri 自启，配置在 ~/.config/DankMaterialShell，
     键位见 ~/.config/niri/dms/binds.kdl，插件在 ~/.config/DankMaterialShell/plugins。
EOF
            ;;
        *)
            cat <<'EOF'
  6. Caelestia QML 插件：已编译到 ~/src/caelestia-build/qml（end4-PC 锁屏
     （Caelestia 风格）硬依赖它），由 start_quickshell.sh 与 fish config.fish
     通过 QML2_IMPORT_PATH 自动加载。
     end4-PC 岛屿 + 仪表盘：栏中央那颗胶囊，点一下从 Bar 里生长成面板，
     Home / System / Weather / GitHub 四页。
     想增删：设置 → 栏 → 组件列表里的「Island」（删掉即整座岛隐藏）。
     命令行：qs -c end4-pC ipc call islanddashboard toggle
     锁屏依赖的 Caelestia QML 插件已编译到 ~/src/caelestia-build/qml，
     手动跑 qs 前请先在 fish 里开个新终端（config.fish 自动注入
     QML2_IMPORT_PATH），或 export QML2_IMPORT_PATH=~/src/caelestia-build/qml。
     ⚠ 插件缺失时 shell 不再整体起不来：面板族里的 Lock / IslandHost 已改成
       运行时创建（panelFamilies/CaelestiaPluginProbe.qml 探针），只会少锁屏
       与灵动岛，其余面板照常。qs 输出里搜「Caelestia QML 插件不可用」确认。
EOF
            ;;
    esac
    cat <<'EOF'
  7. 键盘按键显示（可选，默认关闭）：需要读 /dev/input/event*，把当前用户
     加进 input 组后重新登录，再到 设置 → 桌面 → 按键显示 打开开关：
       sudo usermod -aG input "$USER"
     用 id -nG 确认组已生效。没加组也能装，只是开关打开后读不到按键。
  8. 图标主题：文件夹图标由 matugen 自动着色（换壁纸时重渲），
     主题名为 Adwaita-Matugen-A / Adwaita-Matugen-B（交替）。
     想手动换：设置 → 外观 → 图标主题。
EOF
}

# ============================================================
# 4. 回档 / 恢复 / 卸载 / 存档
# ============================================================

cmd_rollback() {
    ensure_dirs
    if ! read_state current >/dev/null; then
        die "还没有 pre-install 快照，请先至少运行一次 ./install.sh install 来生成回档基线。"
    fi
    say "回档：先保存当前 rice 状态（restore 功能要用到）..."
    snapshot_current "$PRE_ROLLBACK_PREFIX" before-rollback || warn "pre-rollback 快照失败，restore 将不可用"
    apply_snapshot_from_state current "allow_back" || {
        case $? in
            2) say "已取消，返回。" ;;
            *) die "回档失败，见上方输出。" ;;
        esac
    }
    say "回档完成。如果想再回到回档之前的 rice 状态，运行：./install.sh restore"
}

cmd_restore() {
    ensure_dirs
    if ! read_state before-rollback >/dev/null; then
        die "没有找到 pre-rollback 快照：还没执行过 rollback？或者快照文件已被手动删除？（不执行任何文件操作，退出）"
    fi
    apply_snapshot_from_state before-rollback "allow_back" || {
        case $? in
            2) say "已取消，返回。" ;;
            *) die "恢复失败，见上方输出。" ;;
        esac
    }
    say "恢复完成：配置已还原为回档前的 rice 状态。"
}

# cmd_archive：打包存档
# 支持参数：-o PATH  --delete
cmd_archive() {
    local out_path="" do_delete=0
    while (($#)); do
        case "$1" in
            -o)
                # -o 必须带路径：set -u 下直接取 $2 会因未绑定变量裸崩
                [[ $# -ge 2 ]] || die "archive: -o 需要一个输出路径参数，例如：$0 archive -o ~/backup.tar.gz"
                out_path="$2"; shift 2 ;;
            -o=*) out_path="${1#-o=}"; shift ;;
            --delete) do_delete=1; shift ;;
            --help|-h) print_help; return 0 ;;
            *) warn "archive 未知参数: $1（已忽略）"; shift ;;
        esac
    done
    [[ -z $out_path ]] && out_path="$HOME/dotfiles-archive-$(now_ts).tar.gz"
    # 输出目录必须已存在且可写：tar 不会自动建父目录，等到 tar 报错再查会难懂得多
    local out_dir; out_dir="$(dirname "$out_path")"
    [[ -d $out_dir ]] || die "输出目录不存在：$out_dir（先创建目录，或用 -o 指定别的路径）"
    [[ -w $out_dir ]] || die "输出目录不可写：$out_dir"
    ensure_dirs

    # 组装完整归档路径集 = SNAP_PATHS + EXTRA_ARCHIVE_PATHS
    local all_paths=()
    local p
    for p in "${SNAP_PATHS[@]}"; do all_paths+=("$p"); done
    for p in "${EXTRA_ARCHIVE_PATHS[@]}"; do all_paths+=("$p"); done

    local tmp_list; tmp_list="$(mktemp)"
    local total_size=0
    for p in "${all_paths[@]}"; do
        if [[ -e "$HOME/$p" ]]; then
            printf '%s\n' "$p" >> "$tmp_list"
            local sz; sz="$(du -sk "$HOME/$p" 2>/dev/null | awk '{print $1}')"
            [[ -n ${sz:-} ]] && total_size=$((total_size + sz))
        fi
    done
    if [[ ! -s $tmp_list ]]; then
        warn "没有可打包的 rice 相关文件，退出。"
        rm -f "$tmp_list"
        return 1
    fi
    local total_h
    total_h="$(numfmt --to=iec "${total_size}K" 2>/dev/null || echo "${total_size} KB")"
    echo "----------------------------------------------------------------------"
    echo "  将打包 $(wc -l < "$tmp_list") 个顶级路径，总大小约：${total_h}"
    echo "  源路径清单（缺省自动跳过）："
    for p in "${all_paths[@]}"; do
        [[ -e "$HOME/$p" ]] && printf '     \033[1;32m✓\033[0m ~/%s\n' "$p" || printf '     \033[1;33m·\033[0m ~/%s （缺失，跳过）\n' "$p"
    done
    echo "  输出文件：$out_path"
    echo "----------------------------------------------------------------------"
    confirm "确认开始打包？" || return 0

    # 打包：包含一个 MANIFEST.txt
    local tmpdir; tmpdir="$(mktemp -d)"
    local manifest="$tmpdir/MANIFEST.txt"
    {
        echo "# sijin-xb's dotfiles archive MANIFEST"
        echo "用户名      : ${USER:-unknown}"
        echo "时间戳      : $(date -Iseconds)"
        echo "主机名      : $(hostname 2>/dev/null || unknown)"
        echo "Rice 版本  : $RICE_VERSION"
        echo "打包命令行  : $0 $*"
        echo
        echo "源路径清单（相对 \$HOME）："
        for p in "${all_paths[@]}"; do
            [[ -e "$HOME/$p" ]] && echo "  [PRESENT]  $p" || echo "  [MISSING]  $p"
        done
        echo
        echo "归档内实际包含的文件列表（前 50 项）："
        sort "$tmp_list" | head -50
    } > "$manifest"
    say "打包中 ..."
    # 把 MANIFEST.txt 放根目录，然后再把 rice 文件从 $HOME 加进来
    (
        cd "$tmpdir"
        tar --numeric-owner -pzcf "$out_path" "MANIFEST.txt"
    )
    # 追加 rice 文件
    tar --numeric-owner -pzrf "$out_path" -C "$HOME" --files-from="$tmp_list" 2>/dev/null \
        || {
            # 追加失败（一些 tar 版本对 -r 和 -z 组合兼容差）就回退到重新整包
            rm -f "$out_path"
            cp "$manifest" "$HOME/.ARCHIVE-MANIFEST.tmp"
            printf '.ARCHIVE-MANIFEST.tmp\n' > "$tmp_list.manifest"
            cat "$tmp_list" >> "$tmp_list.manifest"
            tar --numeric-owner -pzcf "$out_path" -C "$HOME" --files-from="$tmp_list.manifest"
            rm -f "$HOME/.ARCHIVE-MANIFEST.tmp" "$tmp_list.manifest"
        }
    rm -rf "$tmpdir" "$tmp_list"
    say "打包完成 → $out_path ($(du -h "$out_path" | cut -f1))"

    if ((do_delete)); then
        echo
        # 打包带全部（备份从宽），删除只删范围内（另一套合成器配置原样保留）
        uninstall_compositor_scope
        local del_paths=()
        mapfile -t del_paths < <(active_snap_paths)
        for p in "${EXTRA_ARCHIVE_PATHS[@]}"; do del_paths+=("$p"); done
        warn "--delete 模式：以下 rice 管理路径将在确认后删除（其他用户文件绝不触碰）："
        for p in "${del_paths[@]}"; do
            if [[ -e "$HOME/$p" ]]; then
                printf '     rm -rf ~/%s  (%s)\n' "$p" "$(du -sh "$HOME/$p" 2>/dev/null | cut -f1)"
            fi
        done
        confirm "⚠️  真的要删除吗？此操作不可恢复！" || { say "已取消删除。"; return 0; }
        for p in "${del_paths[@]}"; do
            if [[ -e "$HOME/$p" ]]; then
                rm -rf "$HOME/$p"
                echo "     已删除 ~/$p"
            fi
        done
        say "--delete 清理完成。建议注销重新登录。"
    fi
}

# 卸载：先让用户选"是否顺便存档"，然后存档 → 执行 --delete（可选）
cmd_uninstall() {
    ensure_dirs
    echo "卸载 rice 配置：建议先打包存档作为备份。"
    local do_archive=1
    confirm "是否先打包存档？" || do_archive=0
    ((do_archive)) && {
        local archive_path="$HOME/dotfiles-archive-uninstall-$(now_ts).tar.gz"
        cmd_archive -o "$archive_path" || warn "存档失败，将继续执行卸载（无备份）"
    }
    # 只删本次范围内的合成器 / shell 配置，其余原样保留（见 active_snap_paths 说明）
    uninstall_compositor_scope
    uninstall_shell_scope
    confirm "确认删除 rice 相关路径？（合成器与 shell 配置只删上述范围；不会删除其他个人文件）" || return 0
    local paths=() p
    mapfile -t paths < <(active_snap_paths)
    for p in "${paths[@]}" "${EXTRA_ARCHIVE_PATHS[@]}"; do
        if [[ -e "$HOME/$p" ]]; then
            rm -rf "$HOME/$p"
            echo "     已删除 ~/$p"
        fi
    done
    say "卸载完成。如果你还想保留 quickshell/hyprland 程序本身，请使用 pacman -Rns 手动卸载。"
}

# ============================================================
# 5. 帮助打印（CLI 层）
# ============================================================
print_help() {
    cat <<EOF
sijin-xb's dotfiles 自部署脚本 —— Rice 版本: ${RICE_VERSION}

核心特性：桌面歌词逐字卡拉OK ·
         拼音搜索启动器 · SUPER+T 终端召唤 · matugen Material 3 全局取色

用法：
  $0                    进入 TUI 二级菜单（推荐新手）
  $0 --tui              同上
  $0 install            一键安装（7 步）
                          默认不滚动系统；FULL_UPGRADE=1 $0 install 则执行 pacman -Syu

环境变量：
  SESSION=end4pc|caelestia|dms
                             选择要安装的会话（合成器 + 桌面 Shell），三选一：
                             · end4pc   → Hyprland + quickshell（end4-PC 底盘）
                                          默认；配置入口 ~/.config/hypr/hyprland.lua
                                          + ~/.config/quickshell/end4-pC
                             · caelestia → Hyprland + caelestia shell
                                          shell clone 到 ~/.config/quickshell/caelestia
                             ⚠ end4pc 与 caelestia 都会把 Caelestia QML 插件
                             编译到 ~/src/caelestia-build（end4-PC 的锁屏硬依赖
                             import Caelestia.Config），dms 不需要。
                             · dms      → niri + DankMaterialShell（DMS）
                                          配置入口 ~/.config/niri/config.kdl
                             设定后跳过交互提问，适合脚本/无人值守重装。
                             例：SESSION=caelestia ./install.sh install
                             未设置时会在 [1/7] 步交互询问。
                             ⚠ 只部署**选中的那套**：合成器与 shell 的另一套
                             都不碰，避免覆盖机器上已有的配置。
  COMPOSITOR=niri|hyprland   [兼容旧写法] 等价于 SESSION=dms / SESSION=end4pc。
  INSTALL_BOTH_COMPOSITORS=1 两套合成器配置都部署（默认只部署选中的那套）。
                              机器上同时用 Hyprland 和 niri 时用它。
  FONTS=0|1                   是否安装推荐字体（pacman 字体包 + AUR 字体链 +
                              霞鹜臻楷 GB 下载 + 移除 65-wqy-zenhei.conf）。
                              · 不设置：执行到时交互询问 [Y/n]
                              · FONTS=0：一个字体包都不碰，适合已有字体方案的机器
                              · FONTS=1：跳过询问直接装（等价旧行为）
                              · 非交互执行（管道 / 重定向）时无法询问，兜底为 1
                              TUI 的「执行安装」页按 f 可随时切换。
  FULL_UPGRADE=1             安装时执行 pacman -Syu 全系统升级（默认只装缺失项）
  $0 rollback           回档：还原到最近一次 install 之前的状态
                           （执行前会自动保存 pre-rollback 快照供 restore 用）
  $0 restore            恢复：回档后，还原回 rollback 之前的 rice 状态
  $0 archive [-o TAR.GZ] [--delete]
                        打包存档 rice 所有配置/数据/状态文件到 ~/dotfiles-archive-<时间戳>.tar.gz
                          -o PATH     自定义输出路径
                          --delete     打包成功后清理源文件（可用于彻底卸载前备份）
  $0 uninstall          卸载 rice（询问是否先存档 → 删除源路径）
  $0 -h, --help         显示本帮助

环境要求：
  · Arch Linux 系（/etc/arch-release 必须存在）
  · Wayland 会话；安装目标为 Hyprland 或 niri + 对应桌面 Shell
    （Hyprland + quickshell end4-PC / Hyprland + caelestia / niri + DMS）
  · 普通用户执行（不要 root），需有 sudo 权限用于 pacman

目录说明：
  · ~/.config/hypr/hyprland.lua     Hyprland 配置入口
  ·     custom/general.lua          用户差异层（blur / 阴影等高级参数放这里）
  ·     hyprland/shellOverrides/    quickshell 设置面板写入的值（优先级最高）
  · ~/.config/quickshell/end4-pC/   quickshell 底盘 + 本仓库的差异层（end4pc）
  · ~/.config/quickshell/caelestia/ caelestia shell 本体（caelestia）
  · ~/.config/niri/config.kdl       niri 配置入口（dms）
  · ~/.local/state/dotfiles-backup/  回档 / 卸载存档 / 备份目录

FAQ：
  1) 回档后想回到 rice？ → 运行 $0 restore
  2) 存档默认位置？       → ~/dotfiles-archive-YYYYMMDD-HHMMSS.tar.gz
  3) 面板模糊太浓？       → quickshell 设置 → Hyprland：模糊半径 10→8，活动不透明度 82→88

EOF
}

# ============================================================
# 6. TUI 二级菜单（Welcome / Splash / Main / Detail / Help）
# ============================================================

# TUI 颜色（tput fallback：失败就跳过）
tc() { tput "$@" 2>/dev/null || true; }
TC_BOLD="$(tc bold)"; TC_RESET="$(tc sgr0)"
TC_RED="$(tc setaf 1)"; TC_GREEN="$(tc setaf 2)"
TC_YELLOW="$(tc setaf 3)"; TC_BLUE="$(tc setaf 4)"; TC_MAG="$(tc setaf 5)"; TC_CYAN="$(tc setaf 6)"
# 行内高亮用的背景色。以前只在详情页写 `${TC_BG_BLACK:-}`，这里却从来没定义过，
# 于是那个"注意事项"提示永远没有底色（=静默失效）。一并补上。
TC_BG_BLACK="$(tc setab 0)"

tui_clear() { clear 2>/dev/null || printf '\n\n\n\n'; }

# 逐字符打印分隔线：
# 旧实现用 `tr ' ' "$ch"`，在多字节 locale 下 tr 按字节替换，
# '─'(E2 94 80) 会被拆成 3 个字节分别映射，产生非法 UTF-8 乱码。
# ⚠ 宽度不能用 ${COLUMNS:-80}：bash 只在**交互式** shell 里维护 COLUMNS，
#   脚本里通常为空 → 分隔线永远是 80 格，宽终端上短一截、窄终端上折行。
#   改成向终端问一次（tput cols），问不到（重定向 / 非 tty）才退回 80。
draw_line() {
    local ch="${1:--}" w="${COLUMNS:-0}" i
    if (( w <= 0 )); then w="$(tput cols 2>/dev/null || echo 0)"; fi
    if (( w <= 0 )); then w=80; fi
    for ((i=0; i<w; i++)); do printf '%s' "$ch"; done
    printf '\n'
}

# 打印一个带标题的分隔框；参数：标题
# 旧实现用 cut -c$((...+${#title}))，${#title} 是字节数而 cut -c 也按字节切，
# 中文标题会被从多字节字符中间切开产生乱码。这里改为不填满整行，避免截断。
draw_header() {
    local title="${1:-}"
    printf '%s=== %s ===%s\n' "${TC_BOLD}${TC_GREEN}" "$title" "${TC_RESET}"
}

# 欢迎页 / Splash
show_splash() {
    tui_clear
    draw_header "sijin-xb's dotfiles · Rice ${RICE_VERSION}"
    cat <<'EOF'

          _____ _ _   _           _        _ _         __  _  ____
         / ____(_) | (_)         | |      (_) |       /_ |/ |/ ___|
        | (___  _| |_ _ _ __   __| |_ __   _| | ___    | || | |
         \___ \| | __| | '_ \ / _` | '_ \ | | |/ _ \   | || | |
         ____) | | |_| | | | | (_| | | | || | | (_) |  | || | |___
        |_____/|_|\__|_|_| |_|\__,_|_| |_|/ |_|\___/   |_||_|\____|
                                           _/ |
                                          |__/

        Arch Linux · Hyprland / niri · Quickshell / DMS

EOF
    draw_header "✨ 核心特性"
    printf '  %s%s%1s 桌面歌词%s             逐字计时（酷狗 KRC），自动适配任意 MPRIS 播放器\n' "${TC_BOLD}" "${TC_GREEN}" "·" "${TC_RESET}"
    printf '  %s%s%1s 拼音搜索启动器%s     支持中文拼音搜索 + 窗口缩略图悬浮信息卡\n' "${TC_BOLD}" "${TC_YELLOW}" "·" "${TC_RESET}"
    printf '  %s%s%1s 终端召唤%s             SUPER+T 居中浮动，状态保留（kitty-quake）\n'   "${TC_BOLD}" "${TC_BLUE}" "·" "${TC_RESET}"
    printf '  %s%s%1s Material 3 取色%s     matugen 壁纸→全局配色（11+ 应用联动）\n'        "${TC_BOLD}" "${TC_RED}" "·" "${TC_RESET}"
    echo
    draw_header "🖥️  适配环境"
    printf '  OS       : Omarchy / CachyOS / Arch Linux / EndeavourOS（需要 /etc/arch-release）\n'
    printf '  会话     : Wayland · Hyprland + end4-PC / caelestia，或 niri + DMS\n'
    printf '  GPU 建议 : Intel 核显 UHD 620+ / AMD Vega 3+ / NVIDIA（需开启 modeset）\n'
    echo
    printf '%s按任意键进入主菜单 ...%s' "${TC_BOLD}${TC_YELLOW}" "${TC_RESET}"
    IFS= read -r -n 1 -s || true
    echo
}

show_help() {
    tui_clear
    draw_header "帮助 / 使用说明"
    echo
    echo "【① 适配环境】"
    echo "  · OS: Omarchy / CachyOS / Arch / EndeavourOS（/etc/arch-release 必须存在）"
    echo "  · 会话: Wayland · Hyprland（end4-PC / caelestia）或 niri（DMS）"
    echo "  · 建议 GPU: ≥ Intel UHD 620（模糊 + 壁纸视差要一点 GPU 算力）"
    echo
    echo "【② 键位速览】"
    echo "  SUPER         启动器（中文拼音搜索 + 窗口缩略图信息卡）"
    echo "  SUPER+T       终端召唤（居中浮动半透明，再按隐藏）"
    echo "  SUPER+S       Scratchpad（临时工作区）"
    echo "  SUPER+L       锁屏（Quickshell LockSurface / caelestia lock）"
    echo "  SUPER+F1      重启 fcitx5 输入法（rime 卡住时用）"
    echo "  SUPER+ESC     打开 quickshell 设置面板"
    echo "  SUPER+方向键  切换工作区 / 移动窗口焦点（配合 SHIFT 则移动窗口）"
    echo
    echo "【③ 目录说明】"
    echo "  ~/.config/hypr/hyprland.lua            Hyprland 配置总入口"
    echo "    ├── hyprland/   默认模板层（由 quickshell/上游管理，建议只读）"
    echo "    ├── custom/     用户差异层（blur / shadow 细项在 custom/general.lua）"
    echo "    └── shellOverrides/main.lua    由 quickshell 设置面板写入，优先级最高"
    echo "  ~/.config/quickshell/end4-pC/         quickshell 底盘 + 差异层（end4-PC）"
    echo "  ~/.config/quickshell/caelestia/       caelestia shell 本体（仅 caelestia）"
    echo "  ~/src/caelestia-plugin-src/           Caelestia QML 插件源码（编译用）"
    echo "  ~/src/caelestia-build/qml/            插件编译产物（QML2_IMPORT_PATH）"
    echo "  ~/.config/niri/config.kdl             niri 配置入口（DMS）"
    echo "  ~/.local/state/dotfiles-backup/       备份根（snapshots/ + state/）"
    echo
    echo "【④ 常见问题 FAQ】"
    echo "  Q: 回档后想再换回 rice？"
    echo "  A: 执行 ./install.sh restore（rollback 前自动保存的 pre-rollback 快照会被还原）"
    echo "  Q: 卸载存档放在哪？"
    echo "  A: 默认 \$HOME/dotfiles-archive-时间戳.tar.gz；可用 -o 自定义"
    echo "  Q: 面板模糊效果太浓 / 太淡？"
    echo "  A: quickshell 设置 → 配置文件 → Hyprland：模糊半径(10→8/12)，"
    echo "     活动不透明度(82→更高更清晰或更低更通透)；细项在 ~/.config/hypr/custom/general.lua"
    echo
    printf '%s按任意键返回主菜单%s' "${TC_BOLD}${TC_YELLOW}" "${TC_RESET}"
    IFS= read -r -n 1 -s || true
    echo
}

# 二级详情页模板：输入标题 + 说明段 + 当前状态渲染函数名 + 动作函数名
# 但为了避免 bash 里"传递函数名又保持可读"，直接用 4 个独立函数保持简单

detail_install() {
    local cont=y
    while [[ $cont == y ]]; do
        tui_clear
        draw_header "菜单 1/4 · 执行安装（7 步流程）"
        echo
        cat <<'EOF'
【功能说明】
  从零部署 sijin-xb's dotfiles：
    [1/7] pacman 基础依赖（hyprland / kitty / fish / fcitx5 / cmake ...）
          niri 本体不在这里，走 [2/7] 的 AUR fork 包 niri-shorin-fork-git
          默认只装缺失项；FULL_UPGRADE=1 ./install.sh install 可全系统升级
    [2/7] AUR 包（niri 本体 niri-shorin-fork-git / matugen / mpvpaper
          + Caelestia 插件依赖（libcava / qt6-m3shapes-git，end4-pC 也需要）
          + 所选 shell 专属包 + 引导 yay）
    [3/7] quickshell 三级回退（已装→仓库→AUR→源码编译）
    [4/7] 桌面 Shell：
          [4a] Caelestia QML 插件 —— end4-pC 与 caelestia 都编（锁屏硬依赖
               import Caelestia.Config，跳过会导致 shell 加载失败）
          [4b] shell 本体：end4-PC 拉底盘 / caelestia clone
               （dms 无此步，DMS 由 [2/7] 的 AUR 包提供）
    [5/7] dot_ 前缀 → $HOME 部署（按会话过滤）；有差异的旧文件自动备份
    [6/7] 拼音搜索 Python venv + pypinyin / dbus-python
    [7/7] 输出后续指引（注销重新登录 · fish chsh · 键位速览）
  · 开始前自动保存 pre-install 快照（./install.sh rollback 的基线）
  · 幂等：重复 2 次结果一致（已在的包/文件跳过）

【当前状态】
EOF
        echo "  · 用户         : ${USER:-unknown}"
        echo "  · \$HOME       : $HOME"
        # 以前这里写的是 `echo ✓' 满足'`，引号错位只是碰巧能跑；而且只报"是不是
        # Arch 系"、不报**是哪个发行版**，Omarchy 上看着像是没被识别。改为读
        # os-release 打印真实名字。
        local osname="未知"
        [[ -r /etc/os-release ]] && osname="$( . /etc/os-release && printf '%s' "${PRETTY_NAME:-${ID:-未知}}" )"
        if [[ -f /etc/arch-release ]]; then
            echo "  · 发行版检测   : ✓ $osname（Arch 系）"
        else
            echo "  · 发行版检测   : ✗ $osname（非 Arch 系，本脚本将拒绝运行）"
        fi
        # sudo 可用性单独一行说明：有 sudo 用 sudo（可用 SUDO 环境变量覆盖），
        # 没有则明确告知装不了，别再输出一串字面量。
        if have sudo; then
            echo "  · sudo 可用?   : ✓（将使用 \${SUDO:-sudo} 提权执行 pacman）"
        else
            echo "  · sudo 可用?   : ✗（找不到 sudo，[1/7] 依赖安装会失败）"
        fi
        echo "  · 已存在的 rice 路径数:"
        local cnt=0 p
        # 注意：不能用 `[[ ... ]] && cnt=$((cnt+1))` 作为 for 体最后一条命令，
        # 最后一次 [[ ]] 失败会让 for 返回 1，配合 set -e 直接杀掉整个脚本。
        for p in "${SNAP_PATHS[@]}"; do
            if [[ -e "$HOME/$p" ]]; then cnt=$((cnt+1)); fi
        done
        echo "                 : $cnt / ${#SNAP_PATHS[@]}（新机器通常为 0~2；现有 rice 安装通常 ≥ 10）"
        [[ -r "$STATE_DIR/current" ]] && echo "  · 上次快照基线 : $(<"$STATE_DIR/current")" || echo "  · 快照基线     : 尚未安装过，本次运行将生成 rollback 可用基线"
        # 字体开关：env FONTS 有预设就沿用，否则默认「装」，按 f 切换。
        # 这里顺手把 FONTS_ASKED 置 1，下面 ( cmd_install ) 里的 choose_fonts
        # 才不会再问第二遍（子 shell 会继承 FONTS 与 FONTS_ASKED）。
        if [[ -z $FONTS ]]; then FONTS=1; fi
        FONTS_ASKED=1
        echo "  · 字体安装     : $(fonts_label)（按 f 切换）"
        echo
        printf '%s 注意事项%s：默认只装缺失依赖（首次可能 5-15 分钟）；quickshell 源码编译 5-15 分钟；Caelestia 插件编译 1-3 分钟（end4-pC / caelestia 都要）。\n' "${TC_BOLD}${TC_YELLOW}${TC_BG_BLACK:-}" "${TC_RESET}"
        echo
        # 二次确认 + 字体开关 + 返回
        # 这里不复用 confirm_3way：安装页要多给一个 f 键做字体切换，
        # 换选项就得重绘本页（外层 while 重新循环）。
        local ans=""
        printf '%s确认开始执行安装？%s [y=开始 / f=切换字体 / b=返回主菜单] ' \
            "${TC_BOLD}${TC_YELLOW}" "${TC_RESET}"
        IFS= read -r ans || ans="b"
        case "$ans" in
            y|Y|yes|YES|Yes)
                # 用子 shell 包裹：cmd_install 内部的 die 只会退出子 shell，
                # 不会再连带把 TUI 一起 exit 掉（之前界面"卡死"的根因之一）。
                local rc=0
                set +e; ( cmd_install ); rc=$?; set -e
                ((rc != 0)) && warn "安装返回码 ${rc}（详情见上方输出）" || true
                tui_clear
                read -r -p "按回车返回主菜单 ..." _ || true
                cont=n ;;
            f|F) fonts_toggle; continue ;;
            b|B) cont=n ;;
            *)   read -r -p "已取消，按回车返回主菜单 ..." _ || true; cont=n ;;
        esac
    done
}

detail_uninstall() {
    local cont=y
    while [[ $cont == y ]]; do
        tui_clear
        draw_header "菜单 2/4 · 执行卸载（可选存档）"
        echo
        cat <<'EOF'
【功能说明】
  移除 rice 相关的配置/数据文件（可选先打包存档）：
    1) 可选：打包存档为 dotfiles-archive-uninstall-时间戳.tar.gz
    2) 删除 ~/.config/hypr 或 niri / quickshell / DankMaterialShell / fish / kitty / matugen ... 等 rice 管理目录
    3) 不删除 ~/ 下其他非 rice 用户文件
  · 系统程序（hyprland / qs / pacman 安装的二进制）保留，如需清理请自行 pacman -Rns

【当前状态】
EOF
        # 这里问一次删除范围，cmd_uninstall 在同一 shell 里沿用，不会重复提问
        uninstall_compositor_scope
        local paths=() p
        mapfile -t paths < <(active_snap_paths)
        local cnt=0
        for p in "${paths[@]}" "${EXTRA_ARCHIVE_PATHS[@]}"; do
            if [[ -e "$HOME/$p" ]]; then cnt=$((cnt+1)); fi
        done
        echo "  · 将会删除的顶级路径数（存在才删）: $cnt"
        local tsize=0
        for p in "${paths[@]}" "${EXTRA_ARCHIVE_PATHS[@]}"; do
            if [[ -e "$HOME/$p" ]]; then
                local sz; sz="$(du -sk "$HOME/$p" 2>/dev/null | awk '{print $1}')"
                [[ -n ${sz:-} ]] && tsize=$((tsize + sz))
                printf '     rm -rf ~/%s (%s)\n' "$p" "$(du -sh "$HOME/$p" 2>/dev/null | cut -f1)"
            fi
        done
        echo "  · 估算释放空间: $(numfmt --to=iec "${tsize}K" 2>/dev/null || echo ${tsize}KB)"
        echo
        case "$(confirm_3way '确认进入卸载流程？')" in
            0) local rc=0
               set +e; ( cmd_uninstall ); rc=$?; set -e
               ((rc != 0)) && warn "卸载返回码 ${rc}（详情见上方输出）" || true
               tui_clear
               read -r -p "按回车返回主菜单 ..." _ || true
               cont=n ;;
            2) cont=n ;;
            *) read -r -p "已取消，按回车返回主菜单 ..." _ || true; cont=n ;;
        esac
    done
}

detail_rollback() {
    local cont=y
    while [[ $cont == y ]]; do
        tui_clear
        draw_header "菜单 3/4 · 执行回档（还原到上次 install 之前）"
        echo
        cat <<'EOF'
【功能说明】
  把系统配置还原到"最近一次 ./install.sh install 之前"的状态。
  步骤：
    1) 先保存当前配置为 pre-rollback 快照（供 restore 功能用）
    2) 读取 state/current → 解包 pre-install 快照覆盖进 $HOME
  · 只覆盖快照内包含的文件，不会删除快照外的用户文件。

【当前状态】
EOF
        local snap=""
        # ⚠ 原来这里写的是 `read_state ... || true`，把退出码抹成 0，
        # 导致下面的 else（"基线快照不存在"）成了死分支，快照缺失时照样往下走。
        if snap="$(read_state current 2>/dev/null)"; then
            local nfiles
            # grep -c 计数为 0 时会自己打印 "0" 但返回 1 —— 用 || true 压退出码
            # 即可，不能写 || echo 0（会追加第二行，变量值变成 "0\n0"）。
            nfiles="$(tar -tzf "$snap" 2>/dev/null | grep -cv '/$' || true)"
            echo "  · 基线快照   : $(basename "$snap")"
            echo "  · 创建时间   : $(stat -c '%y' "$snap" 2>/dev/null || unknown)"
            echo "  · 约含文件数 : ${nfiles}"
            echo "  · 快照大小   : $(du -h "$snap" | cut -f1)"
        else
            echo "  ⚠  基线快照不存在：请先至少运行一次 install（TUI 菜单 1）生成基线。"
            echo "     rollback 目前不可执行。"
        fi
        if [[ -r "$STATE_DIR/before-rollback" ]]; then
            echo "  · restore 基线: 已存在（之前做过回档，可用 restore 撤销回档）"
        else
            echo "  · restore 基线: 不存在"
        fi
        echo
        if [[ -z $snap ]]; then
            read -r -p "按回车返回主菜单 ..." _ || true; cont=n
        else
            case "$(confirm_3way '确认执行回档？')" in
                0) local rc=0
                   set +e; ( cmd_rollback ); rc=$?; set -e
                   ((rc != 0)) && warn "回档返回码 ${rc}（详情见上方输出）" || true
                   tui_clear
                   read -r -p "按回车返回主菜单 ..." _ || true
                   cont=n ;;
                2) cont=n ;;
                *) read -r -p "已取消，按回车返回主菜单 ..." _ || true; cont=n ;;
            esac
        fi
    done
}

detail_archive() {
    local cont=y out_path=""
    while [[ $cont == y ]]; do
        tui_clear
        draw_header "菜单 4/4 · 卸载存档打包"
        echo
        cat <<'EOF'
【功能说明】
  将 rice 相关的全部配置 / 数据 / 状态 / 备份统一打包为 tar.gz：
    ① 全部 rice 配置路径（hypr / niri / quickshell / DankMaterialShell / fish / nvim ...）
    ② ~/.local/state/quickshell/ （venv / 生成的颜色 / 状态）
    ③ ~/.local/state/dotfiles-backup/ （旧备份 / snapshots / state）
    ④ ~/.cache/quickshell/ （歌词缓存 / 通知等）
  · 包内附带 MANIFEST.txt（用户名 / 时间戳 / 源路径清单）
  · 可选：打包后清理源文件（等于卸载 + 存档合二为一）

【当前可用参数】
EOF
        [[ -z $out_path ]] && out_path="$HOME/dotfiles-archive-$(now_ts).tar.gz"
        # 旧实现 read -r -i ... 依赖 readline，未加 -e 时行为未定义/报错。
        # 改为手动提示 + 空则保留默认值。
        printf '  · 输出文件 [%s]: ' "$out_path"
        local _ans=""
        IFS= read -r _ans || true
        [[ -n "$_ans" ]] && out_path="$_ans" || true
        local p cnt=0 tsize=0
        for p in "${SNAP_PATHS[@]}" "${EXTRA_ARCHIVE_PATHS[@]}"; do
            if [[ -e "$HOME/$p" ]]; then
                cnt=$((cnt+1))
                local sz; sz="$(du -sk "$HOME/$p" 2>/dev/null | awk '{print $1}')"
                [[ -n ${sz:-} ]] && tsize=$((tsize+sz))
            fi
        done
        echo "  · 包含顶级路径: $cnt / $(( ${#SNAP_PATHS[@]} + ${#EXTRA_ARCHIVE_PATHS[@]} ))"
        echo "  · 估算打包大小: $(numfmt --to=iec "${tsize}K" 2>/dev/null || echo ${tsize}KB)"
        echo
        local dodel=0
        if confirm "打包完成后是否删除源文件（相当于先备份再卸载）？"; then dodel=1; fi
        echo
        case "$(confirm_3way '确认开始打包存档？')" in
            0) local rc=0
               if ((dodel)); then
                   set +e; ( cmd_archive -o "$out_path" --delete ); rc=$?; set -e
               else
                   set +e; ( cmd_archive -o "$out_path" ); rc=$?; set -e
               fi
               ((rc != 0)) && warn "打包返回码 ${rc}（详情见上方输出）" || true
               tui_clear
               read -r -p "按回车返回主菜单 ..." _ || true
               cont=n ;;
            2) cont=n ;;
            *) read -r -p "已取消，按回车返回主菜单 ..." _ || true; cont=n ;;
        esac
    done
}

# 三向确认：输出 0=yes / 1=no / 2=back（调用方用 case "$(confirm_3way ...)" 取值）
# ⚠ 两个坑，改之前先看这里：
#   1) 必须 echo 数字，不能只 return —— 调用方是 $( )，只捕获 stdout，
#      用 return 的话 $( ) 恒为空串，case 永远落到 *) 分支（= 按什么键都是取消）。
#   2) 提示必须写 stderr —— $( ) 连 stdout 一起吞，提示写 stdout 用户永远看不见，
#      表现就是「按了没反应」。
confirm_3way() {
    local prompt="${1:-确认？}" ans
    printf '%s [y/N/b(返回主菜单)] ' "$prompt" >&2
    IFS= read -r ans || ans=""
    case "$ans" in
        y|Y|yes|YES|Yes) printf '0' ;;
        b|B)             printf '2' ;;
        *)               printf '1' ;;
    esac
}

main_menu_loop() {
    while true; do
        tui_clear
        draw_header "主菜单 · sijin-xb's dotfiles ${RICE_VERSION}"
        echo
        printf '  %s[1]%s  执行安装\n'      "${TC_BOLD}${TC_GREEN}" "${TC_RESET}"
        printf '  %s[2]%s  执行卸载（可先存档）\n' "${TC_BOLD}${TC_RED}"   "${TC_RESET}"
        printf '  %s[3]%s  执行回档（还原到上次 install 之前）\n' "${TC_BOLD}${TC_YELLOW}" "${TC_RESET}"
        printf '  %s[4]%s  卸载存档打包\n'      "${TC_BOLD}${TC_BLUE}"  "${TC_RESET}"
        echo
        printf '  %s[h]%s  帮助 / 环境 · 键位 · 目录 · FAQ\n' "${TC_BOLD}${TC_MAG}" "${TC_RESET}"
        printf '  %s[q]%s  退出脚本\n'             "${TC_BOLD}"        "${TC_RESET}"
        draw_line '─'
        local sel=""
        printf '请选择: '
        # stdin EOF（例如被管道/重定向）时不要用 set -e 杀掉脚本，优雅退出
        if ! IFS= read -r sel; then
            echo
            echo "输入结束，退出。"
            return 0
        fi
        case "$sel" in
            1) detail_install ;;
            2) detail_uninstall ;;
            3) detail_rollback ;;
            4) detail_archive ;;
            h|H|help) show_help ;;
            q|Q|quit|exit) echo "再见 👋"; return 0 ;;
            *) printf '%s无效选项，请按 1/2/3/4 / h / q%s\n' "${TC_RED}" "${TC_RESET}"
               sleep 0.3 ;;
        esac
    done
}

enter_tui() {
    if [[ ! -t 0 ]]; then
        warn "标准输入不是终端，无法进入 TUI。请直接使用子命令：$0 install | rollback | restore | archive | uninstall"
        warn "（如果你在管道里调用 ./install.sh 想走 TUI，那是不行的）"
        exit 1
    fi
    show_splash
    main_menu_loop
}

# ============================================================
# 7. 入口：CLI 参数 → 分发
# ============================================================
main() {
    if (($#==0)); then
        enter_tui
        return 0
    fi
    case "$1" in
        --tui)       enter_tui ;;
        -h|--help)   print_help ;;
        install)     shift; cmd_install "$@" ;;
        rollback)    shift; cmd_rollback "$@" ;;
        restore)     shift; cmd_restore "$@" ;;
        archive)     shift; cmd_archive "$@" ;;
        uninstall)   shift; cmd_uninstall "$@" ;;
        *)           printf '\033[1;31m错误:\033[0m 未知子命令: %s\n' "$1" >&2
                     echo "运行 $0 --help 查看用法。" >&2
                     exit 2 ;;
    esac
}

main "$@"
