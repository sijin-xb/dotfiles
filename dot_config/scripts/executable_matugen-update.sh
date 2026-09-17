#!/bin/bash
#
# 重新生成全局配色（配色策略 / 明暗 / 主色索引）。
#
# 文件名是历史遗留，调用方没变：
#   · ~/.config/hypr/custom/keybinds.lua  SUPER+ALT+T → matugen-select-type.sh → 本脚本
#   · ~/.config/scripts/random-anime-wallpaper.sh
#
# 实际取色与分发全部交给 switchwall.sh —— 它是唯一入口。这样「换壁纸」和
# 「切策略」走的是同一条链路（matugen → 全部模板 → material_colors.scss →
# 终端 OSC → Qt/VSCode 收尾），不会出现「Quickshell 变了、终端没变」。
#
# 状态文件（由 matugen-select-type.sh 写入）：
#   ~/.cache/matugen-strategy/type          配色方案类型
#   ~/.cache/matugen-strategy/mode          明暗
#   ~/.cache/matugen-strategy/index_mode    主色索引模式：0 / random
#   ~/.cache/matugen-strategy/current_index random 模式下轮换到的索引
#
# 用法：
#   matugen-update.sh [-f] [WALLPAPER]
#     -f  忽略「壁纸没变就跳过」，强制重新生成
#   matugen-update.sh -n
#     直接用 matugen 自己的交互式取色（需要终端）。这条路径**不会**同步终端 /
#     Qt 配色，只用于手动试色，日常请用不带 -n 的调用。

set -u

# 同 switchwall.sh：本脚本会被快捷键 / waypaper 的 post_command 以管道 stdin
# 拉起，链路上任一步读 stdin 就会永久阻塞。这里不读 stdin，直接切断。
exec </dev/null

CACHE_DIR="$HOME/.cache/matugen-strategy"
TYPE_FILE="$CACHE_DIR/type"
MODE_FILE="$CACHE_DIR/mode"
INDEX_MODE_FILE="$CACHE_DIR/index_mode"
CURRENT_INDEX_FILE="$CACHE_DIR/current_index"
VALID_INDICES_FILE="$CACHE_DIR/valid_indices"
LAST_WALL_FILE="$CACHE_DIR/last_wallpaper"

UPDATE_CACHE_DIR="$HOME/.cache/matugen-update"
LAST_PROCESSED_WALL_FILE="$UPDATE_CACHE_DIR/last_wallpaper_path"

SHELL_CONFIG="$HOME/.config/illogical-impulse/config.json"
SWITCHWALL="$HOME/.config/quickshell/end4-pC/scripts/colors/switchwall.sh"
WAYPAPER_CONFIG="$HOME/.config/waypaper/config.ini"
CURRENT_WALL_LINK="$HOME/.cache/.current_wallpaper"

# matugen 的 --source-color-index 只接受 0-4
MAX_SOURCE_COLOR_INDEX=4

show_help() {
    cat <<'EOF'
Usage: matugen-update.sh [OPTIONS] [WALLPAPER]

Options:
  -h, --help   显示此帮助信息
  -n, --no-index
               用 matugen 自己的交互式取色（不同步终端 / Qt 配色）
  -f, --force  强制重新生成，忽略「壁纸没变」的跳过判断

不带 WALLPAPER 时按以下顺序找当前壁纸：
  Quickshell 配置 → ~/.cache/.current_wallpaper → waypaper → niri/awww
EOF
}

# --- 1. 参数解析 ---
WALLPAPER=""
NO_INDEX=false
FORCE_UPDATE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)      show_help; exit 0 ;;
        -n|--no-index)  NO_INDEX=true; shift ;;
        -f|--force)     FORCE_UPDATE=true; shift ;;
        *)              WALLPAPER="$1"; shift ;;
    esac
done

mkdir -p "$CACHE_DIR" "$UPDATE_CACHE_DIR"

# --- 2. 找当前壁纸 ---
# 主来源是 Quickshell 的配置：换壁纸走的就是 switchwall.sh，
# 它把路径写在 background.wallpaperPath，是当前会话唯一权威的记录。
# 其余来源是旧 rice 的残留（niri + awww、waypaper），留作兜底。
find_wallpaper() {
    local candidate=""

    if [[ -f "$SHELL_CONFIG" ]] && command -v jq >/dev/null 2>&1; then
        candidate="$(jq -r '.background.wallpaperPath // ""' "$SHELL_CONFIG" 2>/dev/null)"
        [[ -n "$candidate" && -f "$candidate" ]] && { echo "$candidate"; return 0; }
    fi

    if [[ -e "$CURRENT_WALL_LINK" ]]; then
        candidate="$(readlink -f "$CURRENT_WALL_LINK" 2>/dev/null)"
        [[ -n "$candidate" && -f "$candidate" ]] && { echo "$candidate"; return 0; }
    fi

    if [[ -f "$WAYPAPER_CONFIG" ]]; then
        candidate="$(sed -n 's/^wallpaper[[:space:]]*=[[:space:]]*//p' "$WAYPAPER_CONFIG")"
        candidate="${candidate/#\~/$HOME}"
        [[ -n "$candidate" && -f "$candidate" ]] && { echo "$candidate"; return 0; }
    fi

    if command -v niri >/dev/null 2>&1 && command -v awww >/dev/null 2>&1; then
        local focused
        focused="$(niri msg focused-output 2>/dev/null | head -n 1 | awk -F '[()]' '{print $2}')"
        if [[ -n "$focused" ]]; then
            candidate="$(awww query 2>/dev/null | grep "^: ${focused}:" | awk -F 'image: ' '{print $2}' | xargs)"
            [[ -n "$candidate" && -f "$candidate" ]] && { echo "$candidate"; return 0; }
        fi
    fi

    return 1
}

if [[ -z "$WALLPAPER" ]]; then
    if ! WALLPAPER="$(find_wallpaper)"; then
        notify-send -a "Matugen" -c "im.error" "找不到壁纸" "无法确定当前壁纸路径，请显式传入。"
        exit 1
    fi
fi

if [[ ! -f "$WALLPAPER" ]]; then
    notify-send -a "Matugen" -c "im.error" "找不到壁纸" "$WALLPAPER 不存在。"
    exit 1
fi

ln -sf "$WALLPAPER" "$CURRENT_WALL_LINK"

# --- 3. 读取策略与模式 ---
STRATEGY="scheme-content"
[[ -f "$TYPE_FILE" ]] && STRATEGY="$(<"$TYPE_FILE")"
MODE="dark"
[[ -f "$MODE_FILE" ]] && MODE="$(<"$MODE_FILE")"

# --- 4. 壁纸没变就别白干 ---
LAST_PROCESSED_WALL=""
[[ -f "$LAST_PROCESSED_WALL_FILE" ]] && LAST_PROCESSED_WALL="$(<"$LAST_PROCESSED_WALL_FILE")"

if [[ "$FORCE_UPDATE" == false && "$NO_INDEX" == false && "$WALLPAPER" == "$LAST_PROCESSED_WALL" ]]; then
    echo "Wallpaper unchanged. Skipping Matugen update."
    exit 0
fi

# --- 5. -n：直接交给 matugen 的交互式取色 ---
if [[ "$NO_INDEX" == true ]]; then
    if ! command -v matugen >/dev/null 2>&1; then
        notify-send -a "Matugen" -c "im.error" "缺少 matugen" "请先安装：yay -S matugen"
        exit 1
    fi
    matugen image "$WALLPAPER" -t "$STRATEGY" -m "$MODE"
    echo "$WALLPAPER" > "$LAST_WALL_FILE"
    echo "$WALLPAPER" > "$LAST_PROCESSED_WALL_FILE"
    exit 0
fi

# --- 6. 选主色索引 ---
# index_mode = 0      固定用最主色（索引 0）
# index_mode = random 在同一张图上轮换主色，每切一次策略换一次主色
INDEX_MODE="0"
[[ -f "$INDEX_MODE_FILE" ]] && INDEX_MODE="$(<"$INDEX_MODE_FILE")"

SELECTED_INDEX=0
if [[ "$INDEX_MODE" == "random" ]]; then
    LAST_WALL=""
    [[ -f "$LAST_WALL_FILE" ]] && LAST_WALL="$(<"$LAST_WALL_FILE")"
    # 换了壁纸，之前的探测结果作废
    [[ "$WALLPAPER" != "$LAST_WALL" ]] && rm -f "$VALID_INDICES_FILE"

    if [[ ! -s "$VALID_INDICES_FILE" ]]; then
        # 图片主色个数不定，越界的索引会让 matugen 直接报错，
        # 所以先逐个探测一遍并缓存（--dry-run 不写文件）。
        valid=()
        for i in $(seq 0 "$MAX_SOURCE_COLOR_INDEX"); do
            matugen image "$WALLPAPER" --source-color-index "$i" --dry-run >/dev/null 2>&1 || break
            valid+=("$i")
        done
        printf '%s\n' "${valid[@]:-0}" > "$VALID_INDICES_FILE"
    fi

    read -r -a VALID_INDICES < "$VALID_INDICES_FILE"
    [[ ${#VALID_INDICES[@]} -eq 0 ]] && VALID_INDICES=(0)

    LAST_INDEX=""
    [[ -f "$CURRENT_INDEX_FILE" ]] && LAST_INDEX="$(<"$CURRENT_INDEX_FILE")"

    SELECTED_INDEX="${VALID_INDICES[0]}"
    for pos in "${!VALID_INDICES[@]}"; do
        if [[ "${VALID_INDICES[$pos]}" == "$LAST_INDEX" ]]; then
            SELECTED_INDEX="${VALID_INDICES[$(( (pos + 1) % ${#VALID_INDICES[@]} ))]}"
            break
        fi
    done
fi

echo "$SELECTED_INDEX" > "$CURRENT_INDEX_FILE"
echo "$WALLPAPER" > "$LAST_WALL_FILE"

# --- 7. 交给唯一入口生成配色 ---
if [[ ! -x "$SWITCHWALL" ]]; then
    notify-send -a "Matugen" -c "im.error" "缺少 switchwall.sh" "找不到 $SWITCHWALL"
    exit 1
fi

# --image + --noswitch = 只按这张图重新取色，完全不碰壁纸层
# （不重启视频壁纸后端，也不改写 wallpaperPath）。
# 明暗偏好（gsettings）与光标主题由 switchwall.sh 内部统一处理，
# 这里不再重复设置 —— 之前两处各设一遍，改一处就容易不一致。
"$SWITCHWALL" --image "$WALLPAPER" --noswitch --type "$STRATEGY" --mode "$MODE" --index "$SELECTED_INDEX"

echo "$WALLPAPER" > "$LAST_PROCESSED_WALL_FILE"
