#!/usr/bin/env bash

set -euo pipefail

mode="${1:-region}"
save_dir="${HOME}/Pictures/Screenshots/Niri-screenshots"
timestamp="$(date +%Y-%m-%d_%H-%M-%S)"
save_path="${save_dir}/${timestamp}.png"

mkdir -p "$save_dir"

require() {
    if ! command -v "$1" >/dev/null 2>&1; then
        notify-send "截图失败" "缺少命令: $1"
        exit 1
    fi
}

arm_shutter() {
    pkill -USR1 -f "/home/xibie/.config/niri/scripts/screenshot-sound.sh" 2>/dev/null || true
}

copy_image() {
    arm_shutter
    wl-copy -t image/png < "$save_path"
}

focused_output_name() {
    if command -v niri >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        niri msg -j focused-output 2>/dev/null | jq -r '.name // empty'
    fi
}

capture_region() {
    local region=""

    if ! region="$(slurp)"; then
        exit 0
    fi

    [[ -z "$region" ]] && exit 0

    grim -g "$region" "$save_path"
    copy_image
    notify-send "区域截图" "已保存并复制到剪贴板"

    if command -v satty >/dev/null 2>&1; then
        satty \
            --filename "$save_path" \
            --output-filename "$save_path" \
            --copy-command "wl-copy --type image/png" \
            --fullscreen current-screen \
            --initial-tool crop \
            --corner-roundness 8
    fi
}

capture_screen() {
    local output_name=""

    output_name="$(focused_output_name)"

    if [[ -n "$output_name" ]]; then
        grim -o "$output_name" "$save_path"
    else
        grim "$save_path"
    fi

    copy_image
    notify-send "屏幕截图" "已保存并复制到剪贴板"
}

require grim
require slurp
require wl-copy
require notify-send

case "$mode" in
    region)
        capture_region
        ;;
    screen)
        capture_screen
        ;;
    *)
        notify-send "截图失败" "未知模式: $mode"
        exit 1
        ;;
esac
