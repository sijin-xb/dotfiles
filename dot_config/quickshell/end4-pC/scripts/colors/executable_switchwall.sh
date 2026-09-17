#!/usr/bin/env bash
#
# 取色总入口：壁纸 → matugen → 各应用配色。
#
# 流程：解析参数/壁纸 → pre_process（gsettings 明暗）→ matugen 渲染全部模板
#       → generate_colors_material.py 产出 material_colors.scss（Kvantum 用）
#       → applycolor.sh 把终端配色推给运行中的终端 → post_process（Qt / VSCode）
#
# 设计约束：
#   * matugen 是唯一的取色来源，所有下游都读它渲染出来的文件，不要在别处再取一次色。
#   * 单个模板出错不应该拖垮整轮取色，所以调用前会过滤掉 input_path 缺失的模板。
#   * 脚本要能在没有 Hyprland 会话、没有 quickshell venv 的环境下跑到哪算哪。
#
# 常用参数：
#   --noswitch              不换壁纸，只重新取色
#   --image PATH --noswitch 从指定图片取色且完全不碰壁纸层（纯换色，供策略切换用）
#   --type / --mode         配色方案类型 / 明暗
#   --index N               用图片里第 N 主色当源色（matugen 只支持 0-4）
#   --color [#RRGGBB]       用指定颜色当源色（不带值则唤起 hyprpicker 取色）

QUICKSHELL_CONFIG_NAME="end4-pC"

# stdin 一律接到 /dev/null。本脚本会被 quickshell / 设置面板 / 快捷键以
# 「常开管道」的形式拉起，链路上任何一步只要读 stdin（ffmpeg 最典型，
# 不加 -nostdin 时会去读；将来换别的工具也可能踩到）就会永久阻塞：
# 实测表现为零 CPU 占用、卡死数分钟、配色不更新也没有任何报错。
# 本脚本不读 stdin，直接切掉最省事，也从根上杜绝这一类问题。
exec </dev/null

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"

# matugen 模板表 + 模板过滤器（把 input_path 不存在的模板剔掉）
MATUGEN_CONFIG_FILE="$XDG_CONFIG_HOME/matugen/config.toml"
MATUGEN_FILTER="$SCRIPT_DIR/filter_matugen_templates.py"

# quickshell venv：generate_colors_material.py / scheme_for_image.py 依赖里面的
# materialyoucolor，两个脚本的 shebang 也直接读这个环境变量。会话内由
# hyprland/env.lua 注入；脱离会话手动执行时退回默认路径，并显式导出，
# 保证被调用的 python 脚本也能拿到。
QUICKSHELL_VENV="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$HOME/.local/state/quickshell/.venv}"
export ILLOGICAL_IMPULSE_VIRTUAL_ENV="$QUICKSHELL_VENV"

terminalscheme="$SCRIPT_DIR/terminal/scheme-base.json"

# 依赖自检。缺了就直接给出可执行的补救命令，不要让用户去猜
# "command not found" 是哪一步炸的。
require_deps() {
    local missing=()
    command -v jq >/dev/null 2>&1 || missing+=(jq)
    command -v matugen >/dev/null 2>&1 || missing+=(matugen)
    if [ ${#missing[@]} -gt 0 ]; then
        echo "[switchwall] 缺少依赖: ${missing[*]}" >&2
        echo "[switchwall] 安装：sudo pacman -S jq；matugen 在 AUR：yay -S matugen" >&2
        notify-send -a "Wallpaper switcher" -c "im.error" \
            "取色依赖缺失" "缺少 ${missing[*]}，无法生成配色。" >/dev/null 2>&1 || true
        exit 1
    fi
}

# 统一的失败上报：写日志 + 桌面通知，调用方决定是否退出
report_failure() {
    local step="$1" detail="$2"
    echo "[switchwall] ${step}失败：${detail}" >&2
    notify-send -a "Wallpaper switcher" -c "im.error" \
        "配色生成失败" "${step}：${detail}" >/dev/null 2>&1 || true
}

handle_kde_material_you_colors() {
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        enable_qt_apps=$(jq -r '.appearance.wallpaperTheming.enableQtApps' "$SHELL_CONFIG_FILE")
        if [ "$enable_qt_apps" == "false" ]; then
            return
        fi
    fi

    local kde_scheme_variant=""
    case "$type_flag" in
        scheme-content|scheme-expressive|scheme-fidelity|scheme-fruit-salad|scheme-monochrome|scheme-neutral|scheme-rainbow|scheme-tonal-spot)
            kde_scheme_variant="$type_flag"
            ;;
        *)
            kde_scheme_variant="scheme-tonal-spot"
            ;;
    esac
    local kde_wrapper="$XDG_CONFIG_HOME/matugen/templates/kde/kde-material-you-colors-wrapper.sh"
    if [[ ! -x "$kde_wrapper" ]]; then
        echo "[switchwall] 跳过 KDE/Qt 配色：$kde_wrapper 不存在或不可执行" >&2
        return 0
    fi
    "$kde_wrapper" --scheme-variant "$kde_scheme_variant"
}

pre_process() {
    local mode_flag="$1"
    # gsettings 写的是 GNOME/GTK 的明暗偏好，GTK 系应用和 matugen 的
    # pre_process 判定都读它。没装 glib2 工具就跳过，不影响后续取色。
    if command -v gsettings >/dev/null 2>&1; then
        if [[ "$mode_flag" == "dark" ]]; then
            gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
            gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
        elif [[ "$mode_flag" == "light" ]]; then
            gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
            gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3'
        fi
    fi

    if [ ! -d "$CACHE_DIR"/user/generated ]; then
        mkdir -p "$CACHE_DIR"/user/generated
    fi
}

# 收尾：Qt / KDE 配色与编辑器主题。两者互不依赖，后台并行跑。
# 锁色模式（锁屏临时主题）不改这些常驻配色，直接跳过。
post_process() {
    local colors_lock_flag="$1"

    if [[ -n "$colors_lock_flag" ]]; then
        return
    fi

    handle_kde_material_you_colors >"$CACHE_DIR/kde-colors.log" 2>&1 &
    "$SCRIPT_DIR/code/material-code-set-color.sh" >"$CACHE_DIR/code-set-color.log" 2>&1 &
}

# 壁纸分辨率低于屏幕时提示上采样。拿不到显示器信息（不在 Hyprland 会话里）
# 就整体跳过 —— 这只是个锦上添花的提示，不该影响取色。
check_and_prompt_upscale() {
    local img="$1"
    local min_width_desired="" min_height_desired=""

    if command -v hyprctl >/dev/null 2>&1; then
        local monitors_json
        monitors_json="$(hyprctl monitors -j 2>/dev/null)" || monitors_json=""
        if [[ -n "$monitors_json" ]]; then
            min_width_desired="$(jq '([.[].width] | max) // empty' <<<"$monitors_json" 2>/dev/null)"
            min_height_desired="$(jq '([.[].height] | max) // empty' <<<"$monitors_json" 2>/dev/null)"
        fi
    fi
    [[ "$min_width_desired" =~ ^[0-9]+$ && "$min_height_desired" =~ ^[0-9]+$ ]] || return 0

    if command -v identify &>/dev/null && [ -f "$img" ]; then
        local img_width img_height
        if is_video "$img"; then
            img_width=$min_width_desired
            img_height=$min_height_desired
        else
            img_width=$(identify -format "%w" "$img" 2>/dev/null)
            img_height=$(identify -format "%h" "$img" 2>/dev/null)
        fi
        if [[ "$img_width" -lt "$min_width_desired" || "$img_height" -lt "$min_height_desired" ]]; then
            action=$(notify-send "Upscale?" \
                "Image resolution (${img_width}x${img_height}) is lower than screen resolution (${min_width_desired}x${min_height_desired})" \
                -A "open_upscayl=Open Upscayl"\
                -a "Wallpaper switcher")
            if [[ "$action" == "open_upscayl" ]]; then
                if command -v upscayl &>/dev/null; then
                    nohup upscayl > /dev/null 2>&1 &
                else
                    action2=$(notify-send \
                        -a "Wallpaper switcher" \
                        -c "im.error" \
                        -A "install_upscayl=Install Upscayl (Arch)" \
                        "Install Upscayl?" \
                        "yay -S upscayl-bin")
                    if [[ "$action2" == "install_upscayl" ]]; then
                        kitty -1 yay -S upscayl-bin
                        if command -v upscayl &>/dev/null; then
                            nohup upscayl > /dev/null 2>&1 &
                        fi
                    fi
                fi
            fi
        fi
    fi
}

CUSTOM_DIR="$XDG_CONFIG_HOME/hypr/custom"
RESTORE_SCRIPT_DIR="$CUSTOM_DIR/scripts"
RESTORE_SCRIPT="$RESTORE_SCRIPT_DIR/__restore_video_wallpaper.sh"
THUMBNAIL_DIR="$RESTORE_SCRIPT_DIR/mpvpaper_thumbnails"
# mpvpaper 的 mpv IPC socket 目录：quickshell 通过它实现视频壁纸视差
# （设置 video-zoom / video-align-x / video-align-y），命名必须与
# Background.qml 的 videoSocketPath 一致：<dir>/mpvpaper-<monitor>.sock
MPVPAPER_IPC_DIR="$XDG_CACHE_HOME/quickshell/mpvpaper"
VIDEO_OPTS="no-audio loop hwdec=auto scale=bilinear interpolation=no video-sync=display-resample panscan=1.0 video-scale-x=1.0 video-scale-y=1.0 video-align-x=0.5 video-align-y=0.5 load-scripts=no"

is_video() {
    local extension="${1##*.}"
    [[ "$extension" == "mp4" || "$extension" == "webm" || "$extension" == "mkv" || "$extension" == "avi" || "$extension" == "mov" ]] && return 0 || return 1
}

kill_existing_video_backend() {
    wallr quit >/dev/null 2>&1 || true
    pkill -x -9 phonto 2>/dev/null || true
    pkill -x -9 mpvpaper 2>/dev/null || true
    # 清掉上一轮留下的 IPC socket，避免 quickshell 连到已死的 mpv
    rm -f "$MPVPAPER_IPC_DIR"/mpvpaper-*.sock 2>/dev/null || true
}

resolve_video_backend() {
    local requested="$1"
    case "$requested" in
        wallr)
            if command -v wallr >/dev/null 2>&1; then
                echo wallr
            else
                echo mpvpaper
            fi
            ;;
        phonto)
            if command -v phonto >/dev/null 2>&1; then
                echo phonto
            else
                echo mpvpaper
            fi
            ;;
        mpvpaper|*)
            echo mpvpaper
            ;;
    esac
}

start_video_backend() {
    local backend="$1"
    local video_path="$2"

    case "$backend" in
        wallr)
            wallr set "$video_path" --mode fill --no-theme >/dev/null 2>&1 &
            ;;
        phonto)
            phonto "$video_path" --layer background >/dev/null 2>&1 &
            ;;
        mpvpaper)
            local monitor
            mkdir -p "$MPVPAPER_IPC_DIR"
            while IFS= read -r monitor; do
                mpvpaper -o "$VIDEO_OPTS input-ipc-server=$MPVPAPER_IPC_DIR/mpvpaper-$monitor.sock" "$monitor" "$video_path" &
                sleep 0.1
            done < <(hyprctl monitors -j | jq -r '.[] | .name')
            ;;
    esac
}

create_restore_script() {
    local backend="$1"
    local video_path="$2"
    cat > "$RESTORE_SCRIPT.tmp" << EOF
#!/bin/bash
# Generated by switchwall.sh - Don't modify it by yourself.
# Time: $(date)

wallr quit >/dev/null 2>&1 || true
pkill -x -9 phonto 2>/dev/null || true
pkill -x -9 mpvpaper 2>/dev/null || true
rm -f "$MPVPAPER_IPC_DIR"/mpvpaper-*.sock 2>/dev/null || true

case "$backend" in
    wallr)
        wallr set "$video_path" --mode fill --no-theme >/dev/null 2>&1 &
        ;;
    phonto)
        phonto "$video_path" --layer background >/dev/null 2>&1 &
        ;;
    mpvpaper)
        mkdir -p "$MPVPAPER_IPC_DIR"
        while IFS= read -r monitor; do
            mpvpaper -o "$VIDEO_OPTS input-ipc-server=$MPVPAPER_IPC_DIR/mpvpaper-\$monitor.sock" "\$monitor" "$video_path" &
            sleep 0.1
        done < <(hyprctl monitors -j | jq -r '.[] | .name')
        ;;
esac
EOF
    mv "$RESTORE_SCRIPT.tmp" "$RESTORE_SCRIPT"
    chmod +x "$RESTORE_SCRIPT"
}

remove_restore() {
    cat > "$RESTORE_SCRIPT.tmp" << EOF
#!/bin/bash
# The content of this script will be generated by switchwall.sh - Don't modify it by yourself.
EOF
    mv "$RESTORE_SCRIPT.tmp" "$RESTORE_SCRIPT"
}

# 原子写回 config.json 里的某个键。quickshell 在 watch 这个文件，
# 必须 tmp + mv，不能原地改；jq 失败时清掉临时文件，别在配置目录留垃圾。
set_shell_config_key() {
    local filter="$1" value="$2"
    [[ -f "$SHELL_CONFIG_FILE" ]] || return 0
    if jq --arg value "$value" "$filter = \$value" "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp"; then
        mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
    else
        rm -f "$SHELL_CONFIG_FILE.tmp"
    fi
}

set_wallpaper_path() {
    set_shell_config_key '.background.wallpaperPath' "$1"
}

set_thumbnail_path() {
    set_shell_config_key '.background.thumbnailPath' "$1"
}

# 用 AI 给壁纸分类（给桌面小部件选图用）。脚本不在就安静跳过。
categorize_wallpaper() {
    local script="$SCRIPT_DIR/../ai/gemini-categorize-wallpaper.sh"
    [[ -x "$script" ]] || return 0
    local img_cat
    img_cat="$("$script" "$1")" || return 0
    echo "$img_cat" > "$STATE_DIR/user/generated/wallpaper/category.txt"
}

switch() {
    imgpath="$1"
    mode_flag="$2"
    type_flag="$3"
    color_flag="$4"
    color="$5"
    colors_only_flag="$6"
    colors_lock_flag="$7"
    index_flag="${8:-0}"

    # generate_colors_material.py 的取色源，二选一（见下面「同源」那段）
    scss_source_color=""
    scss_source_path=""

    aiStylingEnabled=$(jq -r '.background.widgets.clock.cookie.aiStyling' "$SHELL_CONFIG_FILE")
    if [[ "$aiStylingEnabled" == "true" && -z "$colors_only_flag" ]]; then
        categorize_wallpaper "$imgpath" &
    fi

    matugen_args=(--source-color-index "$index_flag")

    if [[ "$color_flag" == "1" ]]; then
        matugen_args+=(color hex "$color")
        scss_source_color="$color"
        scss_source_path=""
    else
        if [[ -z "$imgpath" ]]; then
            echo 'Aborted'
            exit 0
        fi

        check_and_prompt_upscale "$imgpath" &

        if [[ -z "$colors_only_flag" ]]; then
            kill_existing_video_backend
        fi

        if is_video "$imgpath"; then
            mkdir -p "$THUMBNAIL_DIR"

            requested_backend=$(jq -r '.background.videoBackend // "mpvpaper"' "$SHELL_CONFIG_FILE" 2>/dev/null)
            video_backend=$(resolve_video_backend "$requested_backend")
            if [[ "$video_backend" != "$requested_backend" ]]; then
                notify-send \
                    -a "Wallpaper switcher" \
                    "Video backend unavailable" \
                    "$requested_backend is not installed; falling back to $video_backend." \
                    >/dev/null 2>&1 || true
            fi

            missing_deps=()
            if ! command -v "$video_backend" &> /dev/null; then
                missing_deps+=("$video_backend")
            fi
            if ! command -v ffmpeg &> /dev/null; then
                missing_deps+=("ffmpeg")
            fi
            if [ ${#missing_deps[@]} -gt 0 ]; then
                echo "Missing deps: ${missing_deps[*]}"
                echo "Arch: sudo pacman -S ${missing_deps[*]}"
                action=$(notify-send \
                    -a "Wallpaper switcher" \
                    -c "im.error" \
                    -A "install_arch=Install (Arch)" \
                    "Can't switch to video wallpaper" \
                    "Missing dependencies: ${missing_deps[*]}")
                if [[ "$action" == "install_arch" ]]; then
                    kitty -1 sudo pacman -S "${missing_deps[@]}"
                    if command -v "$video_backend" &>/dev/null && command -v ffmpeg &>/dev/null; then
                        notify-send 'Wallpaper switcher' 'Alright, try again!' -a "Wallpaper switcher"
                    fi
                fi
                exit 0
            fi

            if [[ -z "$colors_only_flag" ]]; then
                set_wallpaper_path "$imgpath"

                local video_path="$imgpath"
                start_video_backend "$video_backend" "$video_path"
            fi

            thumbnail="$THUMBNAIL_DIR/$(basename "$imgpath").jpg"
            # 缩略图没变就复用。4K 视频每次换色都重新抽帧是纯浪费，
            # 而这一步在「换一次配色」里占了大头。
            # -nostdin 是必须的：ffmpeg 在 stdin 不是终端时会去读它，
            # 而 quickshell / 设置面板调用本脚本时 stdin 是常开的管道，
            # 结果 ffmpeg 会一直阻塞（实测 >2 分钟零 CPU），整条取色链路卡死。
            if [[ ! -f "$thumbnail" || "$imgpath" -nt "$thumbnail" ]]; then
                ffmpeg -nostdin -y -i "$imgpath" -vframes 1 "$thumbnail" </dev/null 2>/dev/null
            fi

            if [[ -z "$colors_only_flag" ]]; then
                set_thumbnail_path "$thumbnail"
            fi

            if [ -f "$thumbnail" ]; then
                matugen_args+=(image "$thumbnail")
                scss_source_path="$thumbnail"
                scss_source_color=""
                if [[ -z "$colors_only_flag" ]]; then
                    create_restore_script "$video_backend" "$video_path"
                fi
            else
                echo "Cannot create image to colorgen"
                if [[ -z "$colors_only_flag" ]]; then
                    remove_restore
                fi
                exit 1
            fi
        else
            matugen_args+=(image "$imgpath")
            scss_source_path="$imgpath"
            scss_source_color=""
            if [[ -z "$colors_only_flag" ]]; then
                set_wallpaper_path "$imgpath"
                remove_restore
            fi
        fi
    fi

    # 明暗模式：命令行 > GNOME 的 color-scheme（GTK 应用的明暗偏好，
    # 也是 pre_process 自己写的那一项）> 兜底 dark。
    if [[ -z "$mode_flag" ]]; then
        current_mode=""
        if command -v gsettings >/dev/null 2>&1; then
            current_mode=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
        fi
        if [[ "$current_mode" == "prefer-light" ]]; then
            mode_flag="light"
        else
            mode_flag="dark"
        fi
    fi

    # generate_colors_material.py 的参数分两部分：取色源（source）和调参（extra）。
    # 源色要等 matugen 跑完才能确定（见下面「同源」那段），所以先攒 extra。
    scss_extra_args=()

    if [[ -n "$mode_flag" ]]; then
        matugen_args+=(--mode "$mode_flag")
        if [[ $(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode' "$SHELL_CONFIG_FILE") == "true" ]]; then
            scss_extra_args+=(--mode "dark")
        else
            scss_extra_args+=(--mode "$mode_flag")
        fi
    fi
    [[ -n "$type_flag" ]] && matugen_args+=(--type "$type_flag")
    [[ -n "$type_flag" ]] && scss_extra_args+=(--scheme "$type_flag")
    scss_extra_args+=(--termscheme "$terminalscheme" --blend_bg_fg)

    pre_process "$mode_flag"

    if [ -f "$SHELL_CONFIG_FILE" ]; then
        enable_apps_shell=$(jq -r '.appearance.wallpaperTheming.enableAppsAndShell' "$SHELL_CONFIG_FILE")
        if [ "$enable_apps_shell" == "false" ]; then
            echo "App and shell theming disabled, skipping matugen and color generation"
            return
        fi
    fi

    if [ -f "$SHELL_CONFIG_FILE" ]; then
        harmony=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.harmony' "$SHELL_CONFIG_FILE")
        harmonize_threshold=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold' "$SHELL_CONFIG_FILE")
        term_fg_boost=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost' "$SHELL_CONFIG_FILE")
        [[ "$harmony" != "null" && -n "$harmony" ]] && scss_extra_args+=(--harmony "$harmony")
        [[ "$harmonize_threshold" != "null" && -n "$harmonize_threshold" ]] && scss_extra_args+=(--harmonize_threshold "$harmonize_threshold")
        [[ "$term_fg_boost" != "null" && -n "$term_fg_boost" ]] && scss_extra_args+=(--term_fg_boost "$term_fg_boost")
    fi

    colors_json_path="$STATE_DIR/user/generated/colors.json"
    colors_lock_json_path="$STATE_DIR/user/generated/colors-lock.json"
    colors_lock_watch_paths=(
        "$colors_json_path"
        "$XDG_CONFIG_HOME/gtk-3.0/gtk.css"
        "$XDG_CONFIG_HOME/gtk-4.0/gtk.css"
    )
    colors_lock_backups=()
    if [[ -n "$colors_lock_flag" ]]; then
        for i in "${!colors_lock_watch_paths[@]}"; do
            watch_path="${colors_lock_watch_paths[$i]}"
            if [[ -f "$watch_path" ]]; then
                backup_path="$(mktemp)"
                cp "$watch_path" "$backup_path"
                colors_lock_backups[$i]="$backup_path"
            fi
        done
    fi

    # matugen 是「全有或全无」的：任何一个模板的 input_path 不存在，整轮渲染
    # 直接失败，所有应用都停在旧配色上。先过滤一遍，缺哪个就跳过哪个，
    # 剩下的照常生成，并在日志里点名缺失项。
    matugen_config_args=()
    if [[ -f "$MATUGEN_CONFIG_FILE" && -f "$MATUGEN_FILTER" ]]; then
        effective_config="$CACHE_DIR/matugen-effective.toml"
        missing_templates="$(python3 "$MATUGEN_FILTER" "$MATUGEN_CONFIG_FILE" "$effective_config" 2>/dev/null)" || missing_templates=""
        if [[ -n "$missing_templates" ]]; then
            report_failure "matugen 模板" "以下模板的 input_path 不存在，已跳过：$(tr '\n' ' ' <<<"$missing_templates")"
        fi
        [[ -f "$effective_config" ]] && matugen_config_args=(-c "$effective_config")
    fi

    if ! matugen "${matugen_args[@]}" "${matugen_config_args[@]}"; then
        report_failure "matugen" "取色渲染失败，配色未更新（壁纸已切换）"
        return 1
    fi

    if [[ -n "$colors_lock_flag" ]]; then
        if [[ -f "$colors_json_path" ]]; then
            cp "$colors_json_path" "$colors_lock_json_path"
        fi
        for i in "${!colors_lock_watch_paths[@]}"; do
            watch_path="${colors_lock_watch_paths[$i]}"
            backup_path="${colors_lock_backups[$i]:-}"
            if [[ -n "$backup_path" ]]; then
                mv "$backup_path" "$watch_path"
            fi
        done
    fi

    if [[ -n "$colors_lock_flag" ]]; then
        output_scss="$STATE_DIR/user/generated/material_colors_lock.scss"
    else
        output_scss="$STATE_DIR/user/generated/material_colors.scss"
    fi

    # 同源：generate_colors_material.py 有自己的取色算法（Score.score），
    # 跟 matugen 的 --source-color-index 不是一回事。两边各挑各的话，
    # 终端 16 色和 Quickshell 的 M3 就会来自同一张图的不同颜色。
    # matugen 选定的源色已经由 [templates.kde_colors] 写进 color.txt，
    # 直接拿来当 generate_colors_material.py 的 --color，保证两边同源；
    # 只有拿不到（比如模板被关掉）才退回让它自己从图片里挑。
    matugen_source_color="$(tr -d '[:space:]' < "$STATE_DIR/user/generated/color.txt" 2>/dev/null)"
    if [[ -z "$scss_source_color" && "$matugen_source_color" =~ ^#[0-9A-Fa-f]{6}$ ]]; then
        scss_source_color="$matugen_source_color"
    fi

    scss_ready=1
    generate_colors_material_args=()
    if [[ -n "$scss_source_color" ]]; then
        generate_colors_material_args+=(--color "$scss_source_color")
    elif [[ -n "$scss_source_path" ]]; then
        generate_colors_material_args+=(--path "$scss_source_path")
    else
        scss_ready=0
        report_failure "material_colors.scss" "既没有源色也没有图片，跳过生成"
    fi
    [[ ${#scss_extra_args[@]} -gt 0 ]] && generate_colors_material_args+=("${scss_extra_args[@]}")

    # material_colors.scss 只有 Kvantum（scripts/kvantum/*.py）在读，
    # 供 Qt 应用取色。venv 缺失不该拖垮已经成功的 matugen 结果，
    # 所以这里降级为「跳过 + 提示」而不是退出。
    if (( scss_ready )); then
        if [[ -f "$QUICKSHELL_VENV/bin/activate" ]]; then
            # shellcheck source=/dev/null
            if source "$QUICKSHELL_VENV/bin/activate" \
                && python3 "$SCRIPT_DIR/generate_colors_material.py" "${generate_colors_material_args[@]}" > "$output_scss"; then
                deactivate
            else
                deactivate 2>/dev/null || true
                report_failure "material_colors.scss" "生成失败，Qt/Kvantum 应用会继续用上一套配色"
            fi
        else
            report_failure "material_colors.scss" "找不到 quickshell venv（$QUICKSHELL_VENV），已跳过"
        fi
    fi

    if [[ -z "$colors_lock_flag" ]]; then
        "$SCRIPT_DIR"/applycolor.sh
    fi

    post_process "$colors_lock_flag"
}

main() {
    require_deps

    imgpath=""
    mode_flag=""
    type_flag=""
    color_flag=""
    color=""
    noswitch_flag=""
    colors_only_flag=""
    colors_lock_flag=""
    explicit_image=""
    start_dir_flag=""
    index_flag="0"

    # 用 `// 默认值` 而不是 `|| echo 默认值`：jq 在键不存在时会输出 "null"
    # 且退出码为 0，右侧的兜底根本不会执行，结果把字符串 "null" 当成了配置值。
    get_type_from_config() {
        jq -r '.appearance.palette.type // "auto"' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "auto"
    }
    get_accent_color_from_config() {
        jq -r '.appearance.palette.accentColor // ""' "$SHELL_CONFIG_FILE" 2>/dev/null || echo ""
    }
    set_accent_color() {
        set_shell_config_key '.appearance.palette.accentColor' "$1"
    }

    # 只做「方案类型」判定（content / expressive / …），不产出颜色，
    # 所以直接调脚本即可：它的 shebang 会自己进 venv（ILLOGICAL_IMPULSE_VIRTUAL_ENV
    # 已在文件头导出）。识别失败返回空串，调用方会退回 scheme-tonal-spot。
    detect_scheme_type_from_image() {
        local img="$1"
        [[ -f "$SCRIPT_DIR/scheme_for_image.py" ]] || return 0
        "$SCRIPT_DIR"/scheme_for_image.py "$img" 2>/dev/null | tr -d '\n'
    }

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode)
                mode_flag="$2"
                shift 2
                ;;
            --type)
                type_flag="$2"
                shift 2
                ;;
            --index)
                # matugen 的 --source-color-index：0 = 最主色，1 = 次主色…，上限 4
                index_flag="$2"
                shift 2
                ;;
            --color)
                if [[ "$2" =~ ^#?[A-Fa-f0-9]{6}$ ]]; then
                    set_accent_color "$2"
                    shift 2
                elif [[ "$2" == "clear" ]]; then
                    set_accent_color ""
                    shift 2
                else
                    set_accent_color $(hyprpicker --no-fancy)
                    shift
                fi
                ;;
            --image)
                imgpath="$2"
                explicit_image="1"
                shift 2
                ;;
            --start-dir)
                start_dir_flag="$2"
                shift 2
                ;;
            --noswitch)
                noswitch_flag="1"
                if [[ -z "$imgpath" ]]; then
                    imgpath=$(jq -r '.background.wallpaperPath' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "")
                fi
                shift
                ;;
            --colors_lock)
                colors_lock_flag="1"
                colors_only_flag="1"
                noswitch_flag="1"
                if [[ -z "$imgpath" ]]; then
                    imgpath=$(jq -r '.background.wallpaperPath' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "")
                fi
                shift
                ;;
            *)
                if [[ -z "$imgpath" ]]; then
                    imgpath="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -n "$noswitch_flag" && -n "$explicit_image" ]]; then
        colors_only_flag="1"
    fi

    config_color="$(get_accent_color_from_config)"
    if [[ "$config_color" =~ ^#?[A-Fa-f0-9]{6}$ ]]; then
        color_flag="1"
        color="$config_color"
    fi

    if [[ -z "$type_flag" ]]; then
        type_flag="$(get_type_from_config)"
    fi

    allowed_types=(scheme-content scheme-expressive scheme-fidelity scheme-fruit-salad scheme-monochrome scheme-neutral scheme-rainbow scheme-tonal-spot auto)
    valid_type=0
    for t in "${allowed_types[@]}"; do
        if [[ "$type_flag" == "$t" ]]; then
            valid_type=1
            break
        fi
    done
    if [[ $valid_type -eq 0 ]]; then
        echo "[switchwall.sh] Warning: Invalid type '$type_flag', defaulting to 'auto'" >&2
        type_flag="auto"
    fi

    # 主色索引：matugen 只接受 0-4，越界会让整轮取色失败
    if [[ ! "$index_flag" =~ ^[0-4]$ ]]; then
        echo "[switchwall.sh] Warning: Invalid --index '$index_flag', defaulting to 0" >&2
        index_flag="0"
    fi

    # Only prompt for wallpaper if not using --color and not using --noswitch and no imgpath set
    if [[ -z "$imgpath" && -z "$color_flag" && -z "$noswitch_flag" ]]; then
        if [[ -n "$start_dir_flag" && -d "$start_dir_flag" ]]; then
            cd "$start_dir_flag" || return 1
        else
            cd "$(xdg-user-dir PICTURES)/Wallpapers/showcase" 2>/dev/null || cd "$(xdg-user-dir PICTURES)/Wallpapers" 2>/dev/null || cd "$(xdg-user-dir PICTURES)" || return 1
        fi
        imgpath="$(kdialog --getopenfilename . --title 'Choose wallpaper')"
    fi

    if [[ -n "$imgpath" && -z "$noswitch_flag" ]]; then
        set_accent_color ""
        color_flag=""
        color=""
    fi

    if [[ "$type_flag" == "auto" ]]; then
        # 视频壁纸不能直接喂给 scheme_for_image.py（PIL 读不了 mp4），
        # 会一直静默退回 scheme-tonal-spot。缩略图路径是可推导的
        # （和 switch() 里 ffmpeg 落盘的位置一致），存在就说明是这个视频的帧。
        detect_image="$imgpath"
        if [[ -n "$imgpath" ]] && is_video "$imgpath"; then
            detect_image="$THUMBNAIL_DIR/$(basename "$imgpath").jpg"
        fi

        if [[ -n "$detect_image" && -f "$detect_image" ]]; then
            detected_type="$(detect_scheme_type_from_image "$detect_image")"
            valid_detected=0
            for t in "${allowed_types[@]}"; do
                if [[ "$detected_type" == "$t" && "$detected_type" != "auto" ]]; then
                    valid_detected=1
                    break
                fi
            done
            if [[ $valid_detected -eq 1 ]]; then
                type_flag="$detected_type"
            else
                echo "[switchwall] Warning: Could not auto-detect a valid scheme, defaulting to 'scheme-tonal-spot'" >&2
                type_flag="scheme-tonal-spot"
            fi
        else
            echo "[switchwall] Warning: No image to auto-detect scheme from, defaulting to 'scheme-tonal-spot'" >&2
            type_flag="scheme-tonal-spot"
        fi
    fi

    if [[ "$mode_flag" == "dark" || "$mode_flag" == "light" ]]; then
        local imgdir="$(dirname "$imgpath")"
        local imgbase="$(basename "$imgpath")"
        local imgname="${imgbase%.*}"
        local imgext="${imgbase##*.}"

        local stripped_name="${imgname%-dark}"
        stripped_name="${stripped_name%-light}"

        local new_imgpath="${imgdir}/${stripped_name}-${mode_flag}.${imgext}"
        local new_stripped_imgpath="${imgdir}/${stripped_name}.${imgext}"

        if [[ -f "$new_imgpath" ]]; then
            imgpath="$new_imgpath"
        elif [[ -f "$new_stripped_imgpath" ]]; then
            imgpath="$new_stripped_imgpath"
        fi
    fi

    switch "$imgpath" "$mode_flag" "$type_flag" "$color_flag" "$color" "$colors_only_flag" "$colors_lock_flag" "$index_flag"
}

main "$@"