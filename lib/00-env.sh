# ============================================================
# 常量与路径（原 §0）
# 只放全局变量，引导最先加载。SRC 不在这里 —— 它必须由引导算，
# lib/ 下 BASH_SOURCE[0] 指向的是本目录而不是仓库根。
# ============================================================
REPO_URL="https://github.com/sijin-xb/dotfiles.git"
RICE_VERSION="v2.0"
BACKUP_ROOT="$HOME/.local/state/dotfiles-backup"
SNAP_ROOT="$BACKUP_ROOT/snapshots"
STATE_DIR="$BACKUP_ROOT/state"
PRE_INSTALL_PREFIX="pre-install"
PRE_ROLLBACK_PREFIX="pre-rollback"

# ── 自举（单文件运行）──────────────────────────────────────────────────
# 本脚本的**部署源**是仓库里的 dot_config/**，所以正常用法是「仓库里的
# install.sh」。但也可以只把 install.sh 这一个文件捞下来就跑（curl | bash），
# 这时它必须自己去把仓库拉一份 —— 见 ensure_repo()。
#
# 仓库缓存位置固定，不放临时目录：install / update 会反复用它，
# 放临时目录等于每次都重新 clone（几十 MB）。
REPO_URL="${DOTFILES_REPO_URL:-https://github.com/sijin-xb/dotfiles.git}"
REPO_CACHE="${DOTFILES_SRC_DIR:-$HOME/.local/share/dotfiles-src}"

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
