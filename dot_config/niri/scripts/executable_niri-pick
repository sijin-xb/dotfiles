#!/usr/bin/env bash
#
# niri-pick
# 提取 Niri 窗口信息或吸取屏幕颜色，并复制到剪贴板

# ==========================================
# 1. 语言环境检测
# ==========================================
IS_ZH=false
if locale 2>/dev/null | grep -iq "zh"; then
    IS_ZH=true
elif echo "${LANG} ${LC_ALL} ${LC_MESSAGES}" | grep -iq "zh"; then
    IS_ZH=true
fi

# 定义多语言文案 (精简、去括号)
if [[ "$IS_ZH" == true ]]; then
    STR_ERR_TITLE="缺失依赖"
    STR_MENU_TITLE="选择并复制:"
    
    STR_MENU_WIN_ALL="完整信息"
    STR_MENU_WIN_TITLE="标题"
    STR_MENU_WIN_APPID="App ID"
    STR_MENU_WIN_PID="PID"
    STR_MENU_COLOR_HEX="HEX"
    STR_MENU_COLOR_RGB="RGB"
    
    LBL_WIN_ALL="窗口完整信息"
    LBL_WIN_TITLE="窗口标题"
    LBL_WIN_APPID="窗口 App ID"
    LBL_WIN_PID="窗口 PID"
    LBL_COLOR_HEX="颜色 HEX"
    LBL_COLOR_RGB="颜色 RGB"

    STR_NOTIFY_SUCC_TITLE="复制成功"
    STR_NOTIFY_SUCC_MSG="已复制 %s 到剪贴板:\n%s"
    STR_CANCELLED="操作已取消。"
    STR_ERR_NOT_FOUND="未获取到有效内容。"
    STR_ERR_CMD="未知命令"
else
    STR_ERR_TITLE="Missing Dependency"
    STR_MENU_TITLE="Copy:"
    
    STR_MENU_WIN_ALL="Raw Info"
    STR_MENU_WIN_TITLE="Title"
    STR_MENU_WIN_APPID="App ID"
    STR_MENU_WIN_PID="PID"
    STR_MENU_COLOR_HEX="HEX"
    STR_MENU_COLOR_RGB="RGB"
    
    LBL_WIN_ALL="Window Info"
    LBL_WIN_TITLE="Window Title"
    LBL_WIN_APPID="Window App ID"
    LBL_WIN_PID="Window PID"
    LBL_COLOR_HEX="Color HEX"
    LBL_COLOR_RGB="Color RGB"

    STR_NOTIFY_SUCC_TITLE="Copied Successfully"
    STR_NOTIFY_SUCC_MSG="Copied %s to clipboard:\n%s"
    STR_CANCELLED="Operation cancelled."
    STR_ERR_NOT_FOUND="No valid content captured."
    STR_ERR_CMD="Unknown command"
fi

# ==========================================
# 2. 核心函数
# ==========================================
show_notification() {
    local title="$1"
    local msg="$2"
    local icon="${3:-edit-copy}"
    if command -v notify-send &> /dev/null; then
        notify-send "$title" "$msg" -a "niri-pick" -i "$icon"
    fi
}

show_error() {
    local msg="$1"
    if command -v notify-send &> /dev/null; then
        notify-send "$STR_ERR_TITLE" "$msg" -u critical -a "niri-pick" -i "dialog-error"
    fi
    echo -e "\e[31mError: $msg\e[0m" >&2
}

check_dependencies() {
    local action="$1"
    local missing=()
    
    if ! command -v wl-copy &> /dev/null; then
        missing+=("wl-clipboard")
    fi
    
    # 唤起菜单操作时，强制要求 rofi / fuzzel
    if [[ "$action" == "menu" || "$action" == "focus" ]]; then
        if ! command -v fuzzel &> /dev/null && ! command -v rofi &> /dev/null; then
            missing+=("fuzzel/rofi")
        fi
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        show_error "$(IFS=', '; echo "${missing[*]}")"
        exit 1
    fi
}

copy_to_clipboard() {
    echo -n "$1" | wl-copy
}

run_menu() {
    local prompt="$1"; shift
    local items=("$@")
    local input_str=$(printf "%s\n" "${items[@]}")
    
    if command -v fuzzel &> /dev/null; then
        echo "$input_str" | fuzzel --dmenu --prompt "$prompt " --index
    elif command -v rofi &> /dev/null; then
        echo "$input_str" | rofi -dmenu -p "$prompt" -format i
    fi
}

# ==========================================
# 3. 参数解析与命令分发
# ==========================================
ACTION="menu"
SOURCE="pick-window" # 默认为鼠标点选窗口来源

if [[ $# -gt 0 ]]; then
    case "$1" in
        help|-h|--help)
            ACTION="help" ;;
        menu|focus|all|title|appid|pid|hex|rgb)
            ACTION="$1" ;;
        *)
            echo -e "\e[31m$STR_ERR_CMD: $1\e[0m" >&2
            ACTION="help" ;;
    esac
fi

# --------------------------
# 处理 Help
# --------------------------
if [[ "$ACTION" == "help" ]]; then
    if [[ "$IS_ZH" == true ]]; then
        echo "用法: niri-pick [命令]"
        echo ""
        echo "命令:"
        echo "  menu       显示完整交互式菜单 (默认行为)"
        echo "  focus      获取当前焦点窗口，并弹出菜单选择要复制的属性"
        echo "  all        点选窗口，并复制 窗口完整信息"
        echo "  title      点选窗口，并复制 窗口标题"
        echo "  appid      点选窗口，并复制 窗口 App ID"
        echo "  pid        点选窗口，并复制 窗口 PID"
        echo "  hex        吸取并复制 屏幕颜色 (HEX)"
        echo "  rgb        吸取并复制 屏幕颜色 (RGB)"
        echo "  help, -h   显示此帮助信息"
    else
        echo "Usage: niri-pick[COMMAND]"
        echo ""
        echo "Commands:"
        echo "  menu       Show full interactive menu (Default)"
        echo "  focus      Get focused window info and show menu to pick property"
        echo "  all        Pick and copy window Raw Info"
        echo "  title      Pick and copy window Title"
        echo "  appid      Pick and copy window App ID"
        echo "  pid        Pick and copy window PID"
        echo "  hex        Pick and copy screen color (HEX)"
        echo "  rgb        Pick and copy screen color (RGB)"
        echo "  help, -h   Show this help message"
    fi
    exit 0
fi

check_dependencies "$ACTION"

# --------------------------
# 处理 Menu / Focus 菜单逻辑
# --------------------------
if [[ "$ACTION" == "menu" ]]; then
    main_items=(
        "$STR_MENU_WIN_ALL"
        "$STR_MENU_WIN_TITLE" 
        "$STR_MENU_WIN_APPID" 
        "$STR_MENU_WIN_PID" 
        "$STR_MENU_COLOR_HEX" 
        "$STR_MENU_COLOR_RGB" 
    )

    selected_idx=$(run_menu "$STR_MENU_TITLE" "${main_items[@]}")
    if [[ $? -ne 0 ]] || [[ -z "$selected_idx" ]]; then
        echo "$STR_CANCELLED"
        exit 0
    fi

    case "$selected_idx" in
        0) ACTION="all" ;;
        1) ACTION="title" ;;
        2) ACTION="appid" ;;
        3) ACTION="pid" ;;
        4) ACTION="hex" ;;
        5) ACTION="rgb" ;;
    esac
    SOURCE="pick-window"

elif [[ "$ACTION" == "focus" ]]; then
    # 提前检查是否有聚焦窗口，没有则静默退出
    _focused=$(niri msg focused-window 2>/dev/null)
    if [[ $? -ne 0 ]] || [[ -z "$_focused" ]] || echo "$_focused" | grep -iq "no window is focused"; then
        exit 0
    fi

    # focus 专属菜单，没有颜色项
    focus_items=(
        "$STR_MENU_WIN_ALL"
        "$STR_MENU_WIN_TITLE" 
        "$STR_MENU_WIN_APPID" 
        "$STR_MENU_WIN_PID" 
    )

    selected_idx=$(run_menu "$STR_MENU_TITLE" "${focus_items[@]}")
    if [[ $? -ne 0 ]] || [[ -z "$selected_idx" ]]; then
        echo "$STR_CANCELLED"
        exit 0
    fi

    case "$selected_idx" in
        0) ACTION="all" ;;
        1) ACTION="title" ;;
        2) ACTION="appid" ;;
        3) ACTION="pid" ;;
    esac
    # 将信息获取来源设定为当前焦点窗口
    SOURCE="focused-window"
fi

# ==========================================
# 4. 执行操作并提取数据
# ==========================================
value=""
label=""

if [[ "$ACTION" =~ ^(all|title|appid|pid)$ ]]; then
    # 根据 SOURCE 动态执行 pick-window 还是 focused-window
    output=$(niri msg "$SOURCE" 2>/dev/null)
    [[ -z "$output" ]] && { echo "$STR_CANCELLED"; exit 0; }
    
    case "$ACTION" in
        all)
            value="$output"
            label="$LBL_WIN_ALL" ;;
        title)
            value=$(echo "$output" | grep -Po 'Title: "\K.*(?=")')
            label="$LBL_WIN_TITLE" ;;
        appid)
            value=$(echo "$output" | grep -Po 'App ID: "\K.*(?=")')
            label="$LBL_WIN_APPID" ;;
        pid)
            value=$(echo "$output" | grep -Po 'PID: \K\d+')
            label="$LBL_WIN_PID" ;;
    esac

elif [[ "$ACTION" =~ ^(hex|rgb)$ ]]; then
    if command -v hyprpicker &>/dev/null; then
        # 优先使用 hyprpicker (修复了上个版本的正则小笔误)
        if [[ "$ACTION" == "rgb" ]]; then
            raw_val=$(hyprpicker --format rgb -n 2>/dev/null)
            if [[ "$raw_val" =~ ^[0-9]+\ [0-9]+\[0-9]+$ ]]; then
                value="rgb(${raw_val// /, })"
            else
                value="$raw_val"
            fi
            label="$LBL_COLOR_RGB"
        else
            value=$(hyprpicker --format hex -n 2>/dev/null)
            label="$LBL_COLOR_HEX"
        fi
    else
        # 退回 niri 原生吸色
        output=$(niri msg pick-color 2>/dev/null)
        case "$ACTION" in
            hex)
                value=$(echo "$output" | grep -Po '#[[:xdigit:]]{6}')
                label="$LBL_COLOR_HEX" ;;
            rgb)
                value=$(echo "$output" | grep -Po 'rgb\([^)]+\)')
                label="$LBL_COLOR_RGB" ;;
        esac
    fi
    
    [[ -z "$value" ]] && { echo "$STR_CANCELLED"; exit 0; }
fi

# ==========================================
# 5. 复制并通知
# ==========================================
if [[ -z "$value" ]]; then
    show_error "$STR_ERR_NOT_FOUND"
    exit 1
fi

copy_to_clipboard "$value"

# 发起弹窗通知
notify_msg=$(printf "$STR_NOTIFY_SUCC_MSG" "$label" "$value")
show_notification "$STR_NOTIFY_SUCC_TITLE" "$notify_msg"

# 终端同步输出反馈 (安全换码避免 EOF 异常)
echo -e "\e[32m✔ ${label}: \n\e[1m$value\e[0m\e[32m\e[0m"