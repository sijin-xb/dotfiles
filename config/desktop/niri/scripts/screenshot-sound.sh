#!/bin/bash

SOUND="/usr/share/sounds/freedesktop/stereo/camera-shutter.oga"

if ! command -v pw-play >/dev/null; then
    notify-send "错误: 未找到 pw-play"
    exit 1
fi

# niri 只在截图确认后发 ScreenshotCaptured（取消不发），故无需去抖
echo "截图音效服务已启动，监听 niri event-stream..."
niri msg --json event-stream | while IFS= read -r line; do
    case "$line" in
        *'"ScreenshotCaptured"'*) pw-play "$SOUND" & ;;
    esac
done
