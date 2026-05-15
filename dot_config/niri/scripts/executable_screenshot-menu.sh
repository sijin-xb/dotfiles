#!/bin/bash
# 依赖: zenity grim slurp wf-recorder ffmpeg vips wl-copy notify-send
for cmd in zenity grim slurp wf-recorder ffmpeg vips wl-copy notify-send; do
    command -v "$cmd" >/dev/null 2>&1 || { notify-send "错误" "缺少依赖: $cmd"; exit 1; }
done
SAVE_DIR="$HOME/Pictures/Screenshots"
mkdir -p "$SAVE_DIR"
NOTIF_ID=9999
toast() {
    local title="$1" body="$2" timeout="${3:-2000}"
    notify-send -r "$NOTIF_ID" -t "$timeout" "$title" "$body"
}
CHOICE=$(zenity --list --title="截图助手" --column="模式" \
    "区域截图" \
    "全屏截图" \
    "长截图" \
    --width=300 --height=400 --hide-header 2>/dev/null)
[ -z "$CHOICE" ] && exit 0
case "$CHOICE" in
    "区域截图")
        SAVE_PATH="$SAVE_DIR/region_$(date +%Y%m%d_%H%M%S).png"
        sleep 0.8
        grim -g "$(slurp)" "$SAVE_PATH"
        wl-copy -t image/png < "$SAVE_PATH"
        toast "截图" "已保存并复制到剪贴板"
        ;;
    "全屏截图")
        SAVE_PATH="$SAVE_DIR/full_$(date +%Y%m%d_%H%M%S).png"
        sleep 0.8
        grim "$SAVE_PATH"
        wl-copy -t image/png < "$SAVE_PATH"
        toast "截图" "已保存并复制到剪贴板"
        ;;
    "长截图")
        DURATION=$(zenity --scale \
            --title="长截图" \
            --text="录制时长（秒）？慢慢滚不要超时" \
            --min-value=3 --max-value=60 --value=10 2>/dev/null)
        [ -z "$DURATION" ] && exit 0
        GEOM=$(slurp) || exit 1
        TEMP_DIR=$(mktemp -d)
        trap 'rm -rf "$TEMP_DIR"' EXIT
        VIDEO="$TEMP_DIR/scroll.mp4"
        sleep 0.8
        wf-recorder -r 10 -g "$GEOM" -f "$VIDEO" &
        REC_PID=$!
        for (( t=DURATION; t>0; t-- )); do
            toast "长截图" "▶ 录制中，剩余 ${t} 秒\n请滚动页面..." 1100
            sleep 1
        done
        kill "$REC_PID" 2>/dev/null
        wait "$REC_PID" 2>/dev/null || true
        [[ ! -s "$VIDEO" ]] && { toast "长截图" "录制失败" 3000; exit 1; }
        toast "长截图" "⏹ 提取关键帧中..." 5000
        ffmpeg -i "$VIDEO" \
            -vf "fps=2,mpdecimate=hi=64*12:lo=64*5:frac=0.15,normalize=independence=0,scale=iw:ih:flags=fast_bilinear" \
            -vsync vfr \
            "$TEMP_DIR/f_%04d.png" \
            -loglevel error
        FRAMES=( "$TEMP_DIR"/f_*.png )
        (( ${#FRAMES[@]} == 0 )) && { toast "长截图" "未提取到有效帧" 3000; exit 1; }
        toast "长截图" "🔗 拼合 ${#FRAMES[@]} 帧..." 5000
        SAVE_PATH="$SAVE_DIR/long_$(date +%Y%m%d_%H%M%S).png"
        vips arrayjoin "$(IFS=' '; echo "${FRAMES[*]}")" "$SAVE_PATH" --across 1
        wl-copy -t image/png < "$SAVE_PATH"
        toast "长截图完成" "✅ 已保存并复制到剪贴板（${#FRAMES[@]} 帧）" 4000
        ;;
esac
