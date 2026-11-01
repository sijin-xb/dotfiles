# ============================================================
# 常量与路径。引导最先加载。
# SRC 不在这里：lib/ 下 BASH_SOURCE[0] 指向本目录，仓库根必须由引导算。
# ============================================================
REPO_URL="https://github.com/sijin-xb/dotfiles.git"
# 版本号单一来源：仓库根的 VERSION 文件，bash 与 dotctl 都读它。
RICE_VERSION="$(cat "$SRC/VERSION" 2>/dev/null || echo v2.0)"
BACKUP_ROOT="$HOME/.local/state/dotfiles-backup"
SNAP_ROOT="$BACKUP_ROOT/snapshots"
STATE_DIR="$BACKUP_ROOT/state"
PRE_INSTALL_PREFIX="pre-install"
PRE_ROLLBACK_PREFIX="pre-rollback"

# ── 自举（单文件运行）──────────────────────────────────────────────────
# 部署源是仓库里的 config/**。也可以只下载 install.sh 就跑（curl | bash），
# 这时它自己 clone 仓库，见 ensure_repo()。
#
# 缓存位置固定，不放临时目录：install / update 会反复用，临时目录等于每次重 clone。
REPO_URL="${DOTFILES_REPO_URL:-https://github.com/sijin-xb/dotfiles.git}"
REPO_CACHE="${DOTFILES_SRC_DIR:-$HOME/.local/share/dotfiles-src}"

# 快照 / 存档涉及的源路径清单（SNAP_PATHS 18 项 + EXTRA_ARCHIVE_PATHS 3 项）
# 缺失的路径在 tar 时会跳过，不报错
SNAP_PATHS=(
    ".config/hypr"
    ".config/niri"
    # DMS 插件。只含 plugins，不含 settings.json：
    # 后者有显示器与栏布局这类机型相关配置，跨机还原会出问题。
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
