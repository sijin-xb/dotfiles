#!/usr/bin/env bash
# ============================================================
# sijin-xb's dotfiles（Rice 版本: v2.0 液态玻璃版）
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
#   ./install.sh install      → 一键 6 步安装
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
RICE_VERSION="v2.0 液态玻璃版"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="$HOME/.local/state/dotfiles-backup"
SNAP_ROOT="$BACKUP_ROOT/snapshots"
STATE_DIR="$BACKUP_ROOT/state"
PRE_INSTALL_PREFIX="pre-install"
PRE_ROLLBACK_PREFIX="pre-rollback"

# 快照 / 存档涉及的源路径清单（spec FR-4.0 的 18 项 + 存档额外 4 项）
# 缺失的路径在 tar 时会跳过，不报错
SNAP_PATHS=(
    ".config/hypr"
    ".config/quickshell/end4-pC"
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
    if have hyprctl && [[ -n $(hyprctl instances 2>/dev/null || true) ]]; then
        warn "检测到 Hyprland 会话正在运行，建议在 TTY 或其他 Wayland 会话下执行文件覆盖操作，避免进程同时写入导致不一致。继续执行，但后果自负。"
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
    nfiles="$(tar -tzf "$snap_path" 2>/dev/null | grep -cv '/$' || echo 0)"
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

# ============================================================
# 3. 安装（原 6 步流程，封装进 cmd_install）
# ============================================================
cmd_install() {
    [[ -f /etc/arch-release ]] || die "本安装器仅支持 Arch Linux 系发行版（CachyOS / Arch 等）。"
    [[ ${EUID} -eq 0 ]] && die "请勿用 root 运行（makepkg/AUR 步骤需要普通用户）。"
    have pacman || die "找不到 pacman。"

    ensure_dirs
    session_warning_if_running

    # 关键：在部署之前先保存原始配置快照（回档的基础）
    say "[0/6] 安装前自动保存当前配置快照（回档用）"
    snapshot_current "$PRE_INSTALL_PREFIX" current || warn "创建 pre-install 快照失败（可继续安装，但 rollback 将不可用）"

    # ---------- [1/6] 基础工具 + 会话依赖（一次 pacman 搞定） ----------
    say "[1/6] 安装基础工具与会话依赖"
    PACMAN_PKGS=(
        git base-devel github-cli
        hyprland kitty jq fish fuzzel
        grim wl-clipboard wtype playerctl
        fcitx5 fcitx5-rime fcitx5-configtool
        cliphist easyeffects hypridle hyprlock
        xdg-desktop-portal-hyprland gnome-keyring
        python
        # quickshell 源码编译工具链（三级回退时使用，平时不碍事）
        cmake ninja
        qt6-base qt6-declarative qt6-wayland qt6-5compat qt6-shadertools qt6-svg
        wayland-protocols
    )
    "${SUDO:-sudo}" pacman -Syu --needed --noconfirm "${PACMAN_PKGS[@]}"

    # ---------- [2/6] AUR 包（matugen / mpvpaper / 补丁版 fcitx5） ----------
    say "[2/6] AUR 依赖"
    if ! have yay && ! have paru; then
        say "引导安装 yay（AUR helper）"
        tmpdir="$(mktemp -d)"
        git clone --depth=1 https://aur.archlinux.org/yay.git "$tmpdir/yay"
        (cd "$tmpdir/yay" && makepkg -si --noconfirm)
        rm -rf "$tmpdir"
    fi
    for p in matugen mpvpaper; do
        if pacman -Q "$p" >/dev/null 2>&1; then
            echo "    已安装: $p"
        elif aur_install "$p"; then
            echo "    AUR 安装成功: $p"
        else
            warn "$p 安装失败（不影响其余功能，可稍后手动安装）"
        fi
    done
    have fcitx5 || warn "fcitx5 未就绪，中文输入暂不可用（fcitx5-rime 依赖应已带入）"

    # ---------- [3/6] quickshell 三级回退 ----------
    say "[3/6] quickshell"
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
            || git clone --depth=1 https://github.com/outfoxxed/quickshell.git "$src"
        cmake -S "$src" -B "$src/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local
        cmake --build "$src/build" --parallel
        "${SUDO:-sudo}" cmake --install "$src/build"
        rm -rf "$src"
    }
    install_quickshell
    have qs || die "quickshell 安装失败，请检查上方输出。"

    # ---------- [4/6] 部署 dotfiles ----------
    say "[4/6] 部署配置文件"
    # quickshell 底盘（end-4 illogical-impulse 定制 fork）：本仓库只跟踪差异层
    QS_BASE="$HOME/.config/quickshell/end4-pC"
    if [[ ! -f "$QS_BASE/shell.qml" ]]; then
        say "拉取 quickshell 底盘 (pctrade/end4-pC)"
        git clone --depth=1 https://github.com/pctrade/end4-pC.git "$QS_BASE"
    fi
    backup_dir="$BACKUP_ROOT/$(now_ts)"
    installed=0; backed=0
    while IFS= read -r -d '' f; do
        rel="${f#"$SRC"/}"
        case "$rel" in
            .git/*|install.sh|README.md|LICENSE) continue ;;
            dot_*) out="$HOME/.${rel#dot_}" ;;
            *) continue ;;
        esac
        base="${out##*/}"; dir="${out%/*}"
        execbit=0
        if [[ $base == executable_* ]]; then
            base="${base#executable_}"
            execbit=1
        fi
        mkdir -p "$dir"
        if [[ -f "$dir/$base" ]] && ! cmp -s "$f" "$dir/$base"; then
            mkdir -p "$backup_dir/$dir"
            cp -p "$dir/$base" "$backup_dir/$dir/$base"
            backed=$((backed + 1))
        fi
        cp "$f" "$dir/$base"
        if ((execbit)); then chmod +x "$dir/$base"; fi
        installed=$((installed + 1))
    done < <(find "$SRC" -type f -print0)
    say "已部署 $installed 个文件；$backed 个有差异的旧文件备份于 $backup_dir"

    # ---------- [5/6] 拼音搜索环境与歌词缓存 ----------
    say "[5/6] 运行环境与歌词缓存"
    mkdir -p "$HOME/.cache/quickshell/kugou_lyrics"
    VENV="$HOME/.local/state/quickshell/.venv"
    if [[ ! -x "$VENV/bin/python" ]]; then
        mkdir -p "$HOME/.local/state/quickshell"
        python -m venv "$VENV"
    fi
    "$VENV/bin/pip" install --upgrade --quiet pypinyin dbus-python kde-material-you-colors \
        || warn "venv 依赖安装失败——启动器的 app 中文名拼音搜索与 Qt 配色暂不可用，其余功能不受影响"

    # ---------- [6/6] 完成 ----------
    say "[6/6] 完成！接下来的步骤："
    cat <<'EOF'
  1. 注销并重新登录，会话选择 "Hyprland"
     （配置入口 ~/.config/hypr/hyprland.lua，Quickshell 随会话自启）
  2. 中文输入：fcitx5 + rime（SUPER+F1 可重启输入法）
  3. 键位速览：
       SUPER+L      锁屏（Quickshell LockSurface：MPRIS 媒体控制 + 专辑封面 + 电源）
       SUPER+T      终端召唤（居中浮动，再按隐藏）
       SUPER+S      scratchpad
       SUPER        启动器（支持中文拼音搜索）
  4. 桌宠 / 桌面歌词开关：设置 → 桌面 → 小部件
     （桌面歌词已解耦，自动适配 KA Music / Spotify / 浏览器等任意播放器）
  5. fish 设为默认 shell（可选）: chsh -s "$(command -v fish)"
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
            -o) out_path="$2"; shift 2 ;;
            -o=*) out_path="${1#-o=}"; shift ;;
            --delete) do_delete=1; shift ;;
            --help|-h) print_help; return 0 ;;
            *) warn "archive 未知参数: $1（已忽略）"; shift ;;
        esac
    done
    [[ -z $out_path ]] && out_path="$HOME/dotfiles-archive-$(now_ts).tar.gz"
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
        warn "--delete 模式：以下 rice 管理路径将在确认后删除（其他用户文件绝不触碰）："
        for p in "${all_paths[@]}"; do
            if [[ -e "$HOME/$p" ]]; then
                printf '     rm -rf ~/%s  (%s)\n' "$p" "$(du -sh "$HOME/$p" 2>/dev/null | cut -f1)"
            fi
        done
        confirm "⚠️  真的要删除吗？此操作不可恢复！" || { say "已取消删除。"; return 0; }
        for p in "${all_paths[@]}"; do
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
    local do_archive=1 do_delete=1
    confirm "是否先打包存档？" || do_archive=0
    ((do_archive)) && {
        local archive_path="$HOME/dotfiles-archive-uninstall-$(now_ts).tar.gz"
        cmd_archive -o "$archive_path" || warn "存档失败，将继续执行卸载（无备份）"
    }
    confirm "确认删除 rice 相关路径？（~/.config/hypr、quickshell 等；不会删除其他个人文件）" || return 0
    local p
    for p in "${SNAP_PATHS[@]}" "${EXTRA_ARCHIVE_PATHS[@]}"; do
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

核心特性：液态玻璃毛玻璃效果 · Bongo Cat 桌宠 · 桌面歌词逐字卡拉OK ·
         拼音搜索启动器 · SUPER+T 终端召唤 · matugen Material 3 全局取色

用法：
  $0                    进入 TUI 二级菜单（推荐新手）
  $0 --tui              同上
  $0 install            一键安装（6 步）
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
  · Wayland 会话；安装目标为 Hyprland + quickshell (end4-pC)
  · 普通用户执行（不要 root），需有 sudo 权限用于 pacman

目录说明：
  · ~/.config/hypr/hyprland.lua     Hyprland 配置入口
  ·     custom/general.lua          用户差异层（液态玻璃高级参数放这里）
  ·     hyprland/shellOverrides/    quickshell 设置面板写入的值（优先级最高）
  · ~/.config/quickshell/end4-pC/   quickshell 底盘 + 本仓库的差异层
  · ~/.local/state/dotfiles-backup/  回档 / 卸载存档 / 备份目录

FAQ：
  1) 回档后想回到 rice？ → 运行 $0 restore
  2) 存档默认位置？       → ~/dotfiles-archive-YYYYMMDD-HHMMSS.tar.gz
  3) 液态玻璃太浓？       → quickshell 设置 → Hyprland：模糊半径 10→8，活动不透明度 82→88

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

tui_clear() { clear 2>/dev/null || printf '\n\n\n\n'; }

draw_line() {
    local ch="${1:--}" w="${COLUMNS:-80}"
    printf '%*s\n' "$w" '' | tr ' ' "$ch"
}

# 打印一个带标题的分隔框；参数：标题
draw_header() {
    local title="${1:-}"
    printf '%s%s%s ' "${TC_BOLD}${TC_GREEN}" "=== ${title}" "${TC_RESET}"
    draw_line '=' | cut -c$((1 + ${#title} + 6))-
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

        Arch Linux · Hyprland · Quickshell · 液态玻璃 v2.0

EOF
    draw_header "✨ 核心特性"
    printf '  %s%s%1s 液态玻璃毛玻璃效果%s   阴影代替边框，柔和光晕 + vibrancy 色彩染色\n'  "${TC_BOLD}" "${TC_CYAN}" "·" "${TC_RESET}"
    printf '      (quickshell 面板推荐: 模糊半径 10 / 活动不透明度 82 / 非活动 68)\n'
    printf '  %s%s%1s Bongo Cat 桌宠%s       系统状态换心情、拎起甩动有惯性、落点持久化\n' "${TC_BOLD}" "${TC_MAG}" "·" "${TC_RESET}"
    printf '  %s%s%1s 桌面歌词%s             MoeKoe Music 逐字卡拉OK + 猫猫嘴型同步\n'      "${TC_BOLD}" "${TC_GREEN}" "·" "${TC_RESET}"
    printf '  %s%s%1s 拼音搜索启动器%s     支持中文拼音搜索 + 窗口缩略图悬浮信息卡\n' "${TC_BOLD}" "${TC_YELLOW}" "·" "${TC_RESET}"
    printf '  %s%s%1s 终端召唤%s             SUPER+T 居中浮动，状态保留（kitty-quake）\n'   "${TC_BOLD}" "${TC_BLUE}" "·" "${TC_RESET}"
    printf '  %s%s%1s Material 3 取色%s     matugen 壁纸→全局配色（11+ 应用联动）\n'        "${TC_BOLD}" "${TC_RED}" "·" "${TC_RESET}"
    echo
    draw_header "🖥️  适配环境"
    printf '  OS       : CachyOS / Arch Linux / EndeavourOS（需要 /etc/arch-release）\n'
    printf '  会话     : Wayland · Hyprland + Quickshell (end4-pC)\n'
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
    echo "  · OS: CachyOS / Arch / EndeavourOS（/etc/arch-release 必须存在）"
    echo "  · 会话: Wayland · Hyprland · Quickshell (end4-pC)"
    echo "  · 建议 GPU: ≥ Intel UHD 620（模糊+桌宠要一点 GPU 算力）"
    echo
    echo "【② 键位速览】"
    echo "  SUPER         启动器（中文拼音搜索 + 窗口缩略图信息卡）"
    echo "  SUPER+T       终端召唤（居中浮动半透明，再按隐藏）"
    echo "  SUPER+S       Scratchpad（临时工作区）"
    echo "  SUPER+L       锁屏（Quickshell：MPRIS 媒体控制 + 专辑封面 + 电源按钮）"
    echo "  SUPER+F1      重启 fcitx5 输入法（rime 卡住时用）"
    echo "  SUPER+ESC     打开 quickshell 设置面板"
    echo "  SUPER+方向键  切换工作区 / 移动窗口焦点（配合 SHIFT 则移动窗口）"
    echo
    echo "【③ 目录说明】"
    echo "  ~/.config/hypr/hyprland.lua            Hyprland 配置总入口"
    echo "    ├── hyprland/   默认模板层（由 quickshell/上游管理，建议只读）"
    echo "    ├── custom/     用户差异层（液态玻璃 blur/shadow 细项在 custom/general.lua）"
    echo "    └── shellOverrides/main.lua    由 quickshell 设置面板写入，优先级最高"
    echo "  ~/.config/quickshell/end4-pC/         quickshell 底盘 + 差异层"
    echo "  ~/.local/state/dotfiles-backup/       备份根（snapshots/ + state/）"
    echo
    echo "【④ 常见问题 FAQ】"
    echo "  Q: 回档后想再换回 rice？"
    echo "  A: 执行 ./install.sh restore（rollback 前自动保存的 pre-rollback 快照会被还原）"
    echo "  Q: 卸载存档放在哪？"
    echo "  A: 默认 \$HOME/dotfiles-archive-时间戳.tar.gz；可用 -o 自定义"
    echo "  Q: 液态玻璃效果太浓 / 太淡？"
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
        draw_header "菜单 1/4 · 执行安装（6 步流程）"
        echo
        cat <<'EOF'
【功能说明】
  从零部署 sijin-xb's dotfiles：
    [1/6] pacman -Syu 基础依赖（hyprland / kitty / fish / fcitx5 / cmake ...）
    [2/6] AUR 包（matugen / mpvpaper + 引导 yay 不存在时的安装）
    [3/6] quickshell 三级回退（已装→仓库→AUR→源码编译）
    [4/6] dot_ 前缀 → $HOME 部署；有差异的旧文件自动备份
    [5/6] 拼音搜索 Python venv + pypinyin / dbus-python
    [6/6] 输出后续指引（注销重新登录 · fish chsh · 键位速览）
  · 开始前自动保存 pre-install 快照（./install.sh rollback 的基线）
  · 幂等：重复 2 次结果一致（已在的包/文件跳过）

【当前状态】
EOF
        echo "  · 用户         : ${USER:-unknown}"
        echo "  · \$HOME       : $HOME"
        echo "  · Arch 系检测  : $( [[ -f /etc/arch-release ]] && echo ✓' 满足' || echo ✗' 不满足（本脚本将拒绝运行）' )"
        echo "  · sudo 可用?   : $( have sudo && echo ✓ || echo ✗；将使用 \${SUDO:-sudo} )"
        echo "  · 已存在的 rice 路径数:"
        local cnt=0 p
        for p in "${SNAP_PATHS[@]}"; do [[ -e "$HOME/$p" ]] && cnt=$((cnt+1)); done
        echo "                 : $cnt / ${#SNAP_PATHS[@]}（新机器通常为 0~2；现有 rice 安装通常 ≥ 10）"
        [[ -r "$STATE_DIR/current" ]] && echo "  · 上次快照基线 : $(<"$STATE_DIR/current")" || echo "  · 快照基线     : 尚未安装过，本次运行将生成 rollback 可用基线"
        echo
        printf '%s 注意事项%s：首次运行 pacman -Syu 可能需要 10-30 分钟；quickshell 源码编译 5-15 分钟。\n' "${TC_BOLD}${TC_YELLOW}${TC_BG_BLACK:-}" "${TC_RESET}"
        echo
        # 二次确认 + 返回
        case "$(confirm_3way '确认开始执行安装？')" in
            0) cmd_install; read -r -p "完成，按回车返回主菜单 ..." _; cont=n ;;
            2) cont=n ;;
            *) read -r -p "已取消，按回车返回主菜单 ..." _; cont=n ;;
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
    2) 删除 ~/.config/hypr / quickshell/end4-pC / fish / kitty / matugen ... 等 rice 管理目录
    3) 不删除 ~/ 下其他非 rice 用户文件
  · 系统程序（hyprland / qs / pacman 安装的二进制）保留，如需清理请自行 pacman -Rns

【当前状态】
EOF
        local cnt=0 p
        for p in "${SNAP_PATHS[@]}" "${EXTRA_ARCHIVE_PATHS[@]}"; do [[ -e "$HOME/$p" ]] && cnt=$((cnt+1)); done
        echo "  · 将会删除的顶级路径数（存在才删）: $cnt"
        local tsize=0
        for p in "${SNAP_PATHS[@]}" "${EXTRA_ARCHIVE_PATHS[@]}"; do
            if [[ -e "$HOME/$p" ]]; then
                local sz; sz="$(du -sk "$HOME/$p" 2>/dev/null | awk '{print $1}')"
                [[ -n ${sz:-} ]] && tsize=$((tsize + sz))
                printf '     rm -rf ~/%s (%s)\n' "$p" "$(du -sh "$HOME/$p" 2>/dev/null | cut -f1)"
            fi
        done
        echo "  · 估算释放空间: $(numfmt --to=iec "${tsize}K" 2>/dev/null || echo ${tsize}KB)"
        echo
        case "$(confirm_3way '确认进入卸载流程？')" in
            0) cmd_uninstall; read -r -p "完成，按回车返回主菜单 ..." _; cont=n ;;
            2) cont=n ;;
            *) read -r -p "已取消，按回车返回主菜单 ..." _; cont=n ;;
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
        if snap="$(read_state current 2>/dev/null || true)"; then
            local nfiles
            nfiles="$(tar -tzf "$snap" 2>/dev/null | grep -cv '/$' || echo 0)"
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
            read -r -p "按回车返回主菜单 ..." _; cont=n
        else
            case "$(confirm_3way '确认执行回档？')" in
                0) cmd_rollback; read -r -p "完成，按回车返回主菜单 ..." _; cont=n ;;
                2) cont=n ;;
                *) read -r -p "已取消，按回车返回主菜单 ..." _; cont=n ;;
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
    ① 16 项 rice 配置路径（hypr / quickshell end4-pC / fish / kitty / nvim ...）
    ② ~/.local/state/quickshell/ （venv / 生成的颜色 / 状态）
    ③ ~/.local/state/dotfiles-backup/ （旧备份 / snapshots / state）
    ④ ~/.cache/quickshell/ （歌词缓存 / 通知等）
  · 包内附带 MANIFEST.txt（用户名 / 时间戳 / 源路径清单）
  · 可选：打包后清理源文件（等于卸载 + 存档合二为一）

【当前可用参数】
EOF
        [[ -z $out_path ]] && out_path="$HOME/dotfiles-archive-$(now_ts).tar.gz"
        printf '  · 输出文件: '; IFS= read -r -i "$out_path" out_path
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
            0) if ((dodel)); then cmd_archive -o "$out_path" --delete; else cmd_archive -o "$out_path"; fi
               read -r -p "完成，按回车返回主菜单 ..." _; cont=n ;;
            2) cont=n ;;
            *) read -r -p "已取消，按回车返回主菜单 ..." _; cont=n ;;
        esac
    done
}

# 三向确认：返回 0=yes / 1=no / 2=back
confirm_3way() {
    local prompt="${1:-确认？}" ans
    printf '%s [y/N/b(返回主菜单)] ' "$prompt"
    IFS= read -r ans
    case "$ans" in y|Y|yes|YES|Yes) return 0;; b|B) return 2;; *) return 1;; esac
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
        IFS= read -r sel
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
