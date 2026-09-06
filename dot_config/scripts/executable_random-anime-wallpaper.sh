#!/bin/bash

# ================= 默认配置 =================
API_URL="https://t.alcy.cc/pc/"
SAVE_DIR="$HOME/Pictures/Wallpapers/api-random-download"

# [新增配置] 自动清理时保留最近多少张图片？
KEEP_COUNT=40

# 阈值：宽度小于 2500 (即1080P及以下) 才进行超分，2K/4K 原图直出
UPSCALE_THRESHOLD=2200

# 默认开关状态 (可被参数覆盖)
ENABLE_CLEANUP=true   # 默认清理旧图片
ENABLE_UPSCALE=true   # 默认开启智能超分
SILENT_MODE=false     # 默认开启通知

# ================= 参数解析 =================
usage() {
    echo "用法: $(basename $0) [-k] [-n] [-s] [-h]"
    echo "  -k  (Keep)    保留模式：不清理旧壁纸"
    echo "  -n  (No Up)   禁用超分：无论分辨率多少，都直接使用原图"
    echo "  -s  (Silent)  静默模式：不发送任何 notify-send 通知"
    echo "  -h  帮助信息"
    exit 0
}

while getopts "knsh" opt; do
  case $opt in
    k) ENABLE_CLEANUP=false ;;
    n) ENABLE_UPSCALE=false ;;
    s) SILENT_MODE=true ;;
    h) usage ;;
    *) usage ;;
  esac
done

# ================= 辅助函数 =================

# 统一通知函数
send_notify() {
    # $1: Title, $2: Body, $3: Extra Args (optional)
    if [ "$SILENT_MODE" = false ]; then
        notify-send "$1" "$2" $3
    fi
}

# ================= 主逻辑 =================

mkdir -p "$SAVE_DIR"
RAW_FILENAME="wall_$(date +%s).jpg"
RAW_PATH="${SAVE_DIR}/${RAW_FILENAME}"

# --- 1. 下载模块 (带心跳通知) ---

# 如果非静默模式，启动后台心跳通知 (每8秒提示一次)
if [ "$SILENT_MODE" = false ]; then
    (
        sleep 8
        while true; do
            notify-send "Wallpaper" "Downloading is still in progress..." --expire-time=5000 --icon=drive-harddisk --replace-id=999
            sleep 8
        done
    ) &
    NOTIFY_PID=$!
else
    NOTIFY_PID=""
fi

send_notify "Wallpaper" "Downloading from Alcy..." "--expire-time=5000"

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# 执行下载
curl -L -s -A "$USER_AGENT" --connect-timeout 10 -m 120 -o "$RAW_PATH" "$API_URL"
DOWNLOAD_EXIT_CODE=$?

# 下载结束，杀掉通知进程
if [ -n "$NOTIFY_PID" ]; then
    kill "$NOTIFY_PID" 2>/dev/null
    wait "$NOTIFY_PID" 2>/dev/null
fi

# 检查下载结果
if [ $DOWNLOAD_EXIT_CODE -ne 0 ]; then
    send_notify "Wallpaper Error" "Download failed (Network/API Error)" "--urgency=critical"
    exit 1
fi

# 校验文件 (大小和类型)
if [ ! -f "$RAW_PATH" ] || [ "$(wc -c < "$RAW_PATH")" -lt 20480 ]; then
    send_notify "Wallpaper Error" "Download failed (File too small/Invalid)" "--urgency=critical"
    rm -f "$RAW_PATH"
    exit 1
fi

FILE_TYPE=$(file --mime-type -b "$RAW_PATH")
if [[ "$FILE_TYPE" != image/* ]]; then
    send_notify "Wallpaper Error" "Not an image file ($FILE_TYPE)" "--urgency=critical"
    rm -f "$RAW_PATH"
    exit 1
fi

# --- 2. 智能超分模块 ---

FINAL_PATH="$RAW_PATH"
MSG_EXTRA=""

if [ "$ENABLE_UPSCALE" = true ]; then
    IMG_WIDTH=0
    if command -v identify &> /dev/null; then
        IMG_WIDTH=$(identify -format "%w" "$RAW_PATH")
    fi

    # 条件: (宽度有效) AND (小于阈值) AND (waifu2x存在)
    if [ "$IMG_WIDTH" -gt 0 ] && [ "$IMG_WIDTH" -lt "$UPSCALE_THRESHOLD" ] && command -v waifu2x-ncnn-vulkan &> /dev/null; then
        send_notify "Wallpaper" "Upscaling image..." "--expire-time=2000"
        UPSCALED_PATH="${RAW_PATH%.*}.png"
        
        if waifu2x-ncnn-vulkan -i "$RAW_PATH" -o "$UPSCALED_PATH" -n 1 -s 2; then
            FINAL_PATH="$UPSCALED_PATH"
            MSG_EXTRA="(Upscaled 2x)"
            rm "$RAW_PATH"
        else
            MSG_EXTRA="(Upscale Failed)"
        fi
    else
        if [ "$IMG_WIDTH" -ge "$UPSCALE_THRESHOLD" ]; then
            MSG_EXTRA="(Original High-Res)"
        else
            MSG_EXTRA="(Original)"
        fi
    fi
else
    MSG_EXTRA="(Upscale Disabled)"
fi

# --- 3. 应用模块 ---

awww img "$FINAL_PATH" --transition-duration 2 --transition-type center --transition-fps 60

# --- 4. 钩子与清理 ---
(
    # 钩子脚本屏蔽标准输出，保留报错
    [ -x "$HOME/.config/scripts/matugen-update.sh" ] && "$HOME/.config/scripts/matugen-update.sh" "$FINAL_PATH" > /dev/null
    
    sleep 0.5
    
    [ -x "$HOME/.config/scripts/niri_set_overview_blur_dark_bg.sh" ] && "$HOME/.config/scripts/niri_set_overview_blur_dark_bg.sh" > /dev/null
    
    # [修改] 动态清理逻辑
    if [ "$ENABLE_CLEANUP" = true ]; then
        # 计算需要从第几行开始删除 (保留数量 + 1)
        DELETE_START=$((KEEP_COUNT + 1))
        cd "$SAVE_DIR" && ls -t | tail -n +$DELETE_START | xargs -I {} rm -- {} 2>/dev/null
    fi
) &

send_notify "Wallpaper Updated" "Enjoy! $MSG_EXTRA"
