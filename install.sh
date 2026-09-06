#!/usr/bin/env bash
# ============================================================
# sijin-xb's dotfiles 一键安装（仅限 Arch Linux 系，如 CachyOS）
# ------------------------------------------------------------
# 不依赖 chezmoi，纯 bash 自部署：
#   dot_ 前缀目录  → $HOME 下的隐藏目录（dot_config → ~/.config）
#   executable_ 前缀文件 → 剥前缀 + 恢复执行位
# quickshell 三级回退：已装 → 二进制仓库 → AUR → 源码编译（全自动）
# 覆盖有差异的旧文件前会备份到 ~/.local/state/dotfiles-backup/
# 重复运行安全（幂等）。
# ============================================================
set -euo pipefail

REPO_URL="https://github.com/sijin-xb/dotfiles.git"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="$HOME/.local/state/dotfiles-backup"

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

[[ -f /etc/arch-release ]] || die "本安装器仅支持 Arch Linux 系发行版（CachyOS / Arch 等）。"
[[ ${EUID} -eq 0 ]] && die "请勿用 root 运行（makepkg/AUR 步骤需要普通用户）。"
have pacman || die "找不到 pacman。"

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
backup_dir="$BACKUP_ROOT/$(date '+%Y%m%d-%H%M%S')"
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

# ---------- [5/6] 拼音搜索 venv ----------
say "[5/6] 拼音搜索环境"
VENV="$HOME/.local/state/quickshell/.venv"
if [[ ! -x "$VENV/bin/python" ]]; then
    mkdir -p "$HOME/.local/state/quickshell"
    python -m venv "$VENV"
fi
"$VENV/bin/pip" install --upgrade --quiet pypinyin dbus-python \
    || warn "venv 依赖安装失败——启动器的 app 中文名拼音搜索暂不可用，其余功能不受影响"

# ---------- [6/6] 完成 ----------
say "[6/6] 完成！接下来的步骤："
cat <<'EOF'
  1. 注销并重新登录，会话选择 "Hyprland"
     （配置入口 ~/.config/hypr/hyprland.lua，Quickshell 随会话自启）
  2. 中文输入：fcitx5 + rime（SUPER+F1 可重启输入法）
  3. 键位速览：
       SUPER+T      终端召唤（居中浮动，再按隐藏）
       SUPER+S      scratchpad
       SUPER        启动器（支持中文拼音搜索）
  4. 桌宠 / 桌面歌词开关：设置 → 桌面 → 小部件
  5. fish 设为默认 shell（可选）: chsh -s "$(command -v fish)"
EOF
