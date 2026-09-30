#!/usr/bin/env bash
#
# 把 material_colors.scss 应用到 Qt / Kvantum 应用。
#
# 链路：
#   switchwall.sh → generate_colors_material.py → material_colors.scss
#                                                      │
#                                   本脚本 ─────────────┘
#                                     ├─ 复制 Kvantum 的 Colloid 基底 kvconfig → MaterialAdw.kvconfig
#                                     └─ adwsvg.py / adwsvgDark.py 按 scss 重着色 MaterialAdw.svg
#
# 调用方：switchwall.sh 的 post_process（受 appearance.wallpaperTheming.enableQtApps 控制）。
#
# 设计约束：
#   * 这是配色链路的**最后一环**，缺依赖时只降级 + 提示，不让整轮取色失败。
#   * 所有失败都要给出可直接复制的补救命令，不要只说「失败了」。

set -u

QUICKSHELL_CONFIG_NAME="end4-pC"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SCSS_FILE="$STATE_DIR/user/generated/material_colors.scss"
TARGET_DIR="$XDG_CONFIG_HOME/Kvantum/MaterialAdw"
TARGET_NAME="MaterialAdw"

# Colloid 基底主题可能落在两处，按 Kvantum 自己的搜索顺序找：
#   1) $XDG_CONFIG_HOME/Kvantum/Colloid  —— 用 Colloid-kde 的 install.sh 以普通用户装
#   2) /usr/share/Kvantum/Colloid        —— 装 AUR 包 plasma6-themes-colloid-git
COLLOID_SEARCH_DIRS=(
    "$XDG_CONFIG_HOME/Kvantum/Colloid"
    "/usr/share/Kvantum/Colloid"
)
COLLOID_DIR=""

# 不读 stdin：本脚本由 switchwall.sh 在后台拉起，stdin 可能是常开管道。
exec </dev/null

log() { printf '[materialQT] %s\n' "$*" >&2; }

fail() {
    log "$1"
    notify-send -a "Wallpaper switcher" -c "im.error" "Qt 配色未应用" "$1" >/dev/null 2>&1 || true
    exit 0   # 降级退出：配色链路的其它环节不该被这里拖垮
}

get_light_dark() {
    local current_mode
    current_mode="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")"
    if [[ "$current_mode" == "prefer-dark" ]]; then
        echo "dark"
    else
        echo "light"
    fi
}

# 前置检查：把「缺什么、怎么补」一次性说清楚
preflight() {
    if [[ ! -s "$SCSS_FILE" ]]; then
        fail "material_colors.scss 不存在或为空（$SCSS_FILE）。
        根因通常是 generate_colors_material.py 在 --termscheme 路径上抛异常，
        switchwall.sh 的 '> 文件' 重定向已经把它截成 0 字节。
        手动验证：source \$ILLOGICAL_IMPULSE_VIRTUAL_ENV/bin/activate && \\
          python3 $CONFIG_DIR/scripts/colors/generate_colors_material.py \\
          --color '#513c73' --termscheme $CONFIG_DIR/scripts/colors/terminal/scheme-base.json"
    fi

    if ! command -v kvantummanager >/dev/null 2>&1; then
        fail "未安装 Kvantum，Qt 应用无法读取 MaterialAdw 主题。
        安装：sudo pacman -S kvantum kvantum-qt5"
    fi

    local d
    for d in "${COLLOID_SEARCH_DIRS[@]}"; do
        if [[ -d "$d" ]]; then
            COLLOID_DIR="$d"
            break
        fi
    done

    if [[ -z "$COLLOID_DIR" ]]; then
        fail "缺少 Kvantum 的 Colloid 基底主题（找过：${COLLOID_SEARCH_DIRS[*]}）。
        MaterialAdw 是它的重着色副本，没有基底就无从生成。
        安装：yay -S plasma6-themes-colloid-git
        装完应存在 /usr/share/Kvantum/Colloid/ColloidDark.kvconfig。"
    fi
}

apply_qt() {
    preflight

    mkdir -p "$TARGET_DIR"

    local lightdark base_kv svg_script
    lightdark="$(get_light_dark)"

    if [[ "$lightdark" == "light" ]]; then
        base_kv="$COLLOID_DIR/Colloid.kvconfig"
        svg_script="$SCRIPT_DIR/adwsvg.py"
    else
        base_kv="$COLLOID_DIR/ColloidDark.kvconfig"
        svg_script="$SCRIPT_DIR/adwsvgDark.py"
    fi

    if [[ ! -f "$base_kv" ]]; then
        fail "缺少基底 kvconfig：$base_kv
        plasma6-themes-colloid-git 可能安装不完整，重装：yay -S plasma6-themes-colloid-git"
    fi

    cp -f "$base_kv" "$TARGET_DIR/$TARGET_NAME.kvconfig" \
        || fail "写入 $TARGET_DIR/$TARGET_NAME.kvconfig 失败"

    # ⚠ 必须用 python3。原来的 `python` 在只装了 python3 的环境里不存在，
    #    而且脚本不进 quickshell venv —— 这两个脚本只用标准库，不需要 venv。
    python3 "$svg_script" \
        || fail "SVG 重着色失败（$svg_script），MaterialAdw.svg 未更新"

    # 让 Kvantum 重新读取当前主题（Kvantum 常驻时会缓存）
    kvantummanager --set "$TARGET_NAME" >/dev/null 2>&1 \
        || log "kvantummanager --set $TARGET_NAME 返回非零，请手动在 Kvantum 设置里选一次 $TARGET_NAME"

    log "已应用 $TARGET_NAME（$lightdark，基底 $COLLOID_DIR）"
}

apply_qt
