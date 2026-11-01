#!/usr/bin/env bash
CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"
JSON_PATH=".screenRecord.savePath"
CUSTOM_PATH=$(jq -r "$JSON_PATH" "$CONFIG_FILE" 2>/dev/null)
RECORDING_DIR=""
if [[ -n "$CUSTOM_PATH" ]]; then
    RECORDING_DIR="$CUSTOM_PATH"
else
    RECORDING_DIR="$HOME/Videos"
fi

set_recording_state() {
    local state=$1
    local STATE_FILE="$HOME/.local/state/quickshell/states.json"
    local tmp=$(mktemp)
    jq ".record.enable = $state" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

getdate() {
    date '+%Y-%m-%d_%H.%M.%S'
}

# 获取系统音频输出设备的 monitor 源（仅录制系统声音，不含麦克风输入）
getaudiooutput() {
    local default_sink
    default_sink=$(pactl get-default-sink 2>/dev/null)
    if [[ -n "$default_sink" ]]; then
        echo "${default_sink}.monitor"
    else
        # 回退：取第一个 monitor 源
        pactl list sources short 2>/dev/null | awk '/\.monitor$/ {print $2; exit}'
    fi
}

# 获取麦克风输入源（pactl 的默认 source）。对应 --mic，
# 由灵动岛的「录屏」设置区打开「麦克风」时使用。
getaudioinput() {
    local default_source
    default_source=$(pactl get-default-source 2>/dev/null)
    if [[ -n "$default_source" ]]; then
        echo "$default_source"
    else
        # 回退：取第一个非 monitor 源
        pactl list sources short 2>/dev/null | awk '!/\.monitor$/ {print $2; exit}'
    fi
}

detect_compositor() {
    local combined
    combined="$(echo "${XDG_CURRENT_DESKTOP:-} ${XDG_SESSION_DESKTOP:-}" | tr '[:upper:]' '[:lower:]')"
    if [[ "$combined" == *"niri"* ]]; then
        echo "niri"
    elif [[ "$combined" == *"hyprland"* ]]; then
        echo "hyprland"
    else
        echo "unknown"
    fi
}

getactivemonitor() {
    if [[ "$(detect_compositor)" == "niri" ]]; then
        niri msg -j workspaces | jq -r '.[] | select(.is_focused == true) | .output'
    else
        hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name'
    fi
}

mkdir -p "$RECORDING_DIR"
cd "$RECORDING_DIR" || exit

ARGS=("$@")
MANUAL_REGION=""
SOUND_FLAG=0
MIC_FLAG=0
FULLSCREEN_FLAG=0
for ((i=0;i<${#ARGS[@]};i++)); do
    if [[ "${ARGS[i]}" == "--region" ]]; then
        if (( i+1 < ${#ARGS[@]} )); then
            MANUAL_REGION="${ARGS[i+1]}"
        else
            notify-send "Recording cancelled" "No region specified for --region" -a 'Recorder' & disown
            exit 1
        fi
    elif [[ "${ARGS[i]}" == "--sound" ]]; then
        SOUND_FLAG=1
    elif [[ "${ARGS[i]}" == "--mic" ]]; then
        MIC_FLAG=1
    elif [[ "${ARGS[i]}" == "--fullscreen" ]]; then
        FULLSCREEN_FLAG=1
    fi
done

# ── 画质 ────────────────────────────────────────────────────────────────────
# 由灵动岛的「录屏」设置区写进 config.json（screenRecord.quality）。
# 数值只在这一处定义：ScreenRecService 那边只负责显示「高/中/低」，
# 不重复维护一份映射，避免两边漂移。
QUALITY=$(jq -r '.screenRecord.quality // "medium"' "$CONFIG_FILE" 2>/dev/null)
case "$QUALITY" in
    high) CRF=16; PRESET="fast"      ;;
    low)  CRF=28; PRESET="veryfast"  ;;
    *)    CRF=20; PRESET="superfast" ;;   # medium，以及任何非法值
esac

# ── 音频 ────────────────────────────────────────────────────────────────────
# wf-recorder 只接受一个 --audio，所以两者同时开启时系统声优先。
# 要同时录得先建虚拟 sink 做混音，不在当前范围内。
AUDIO_ARGS=()
if [[ $SOUND_FLAG -eq 1 ]]; then
    AUDIO_ARGS=(--audio="$(getaudiooutput)")
elif [[ $MIC_FLAG -eq 1 ]]; then
    AUDIO_ARGS=(--audio="$(getaudioinput)")
fi

# 注：原命令里的 -t 在当前 wf-recorder 上是无效参数
# （启动时报 "invalid option -- 't'"），已去掉，行为不变。
ENC_ARGS=(-c libx264 -p "crf=$CRF" -p "preset=$PRESET")

if pgrep wf-recorder > /dev/null; then
    pkill wf-recorder &
    set_recording_state false
else
    if [[ $FULLSCREEN_FLAG -eq 1 ]]; then
        # 开始反馈改由 quickshell 灵动岛（RecordIndicator / 岛屿捕获条）承担
        set_recording_state true
        wf-recorder -o "$(getactivemonitor)" --pixel-format yuv420p \
            -f "./recording_$(getdate).mp4" \
            "${ENC_ARGS[@]}" "${AUDIO_ARGS[@]}"
    else
        if [[ -n "$MANUAL_REGION" ]]; then
            region="$MANUAL_REGION"
        else
            if ! region="$(slurp 2>&1)"; then
                notify-send "Recording cancelled" "Selection was cancelled" -a 'Recorder' & disown
                exit 1
            fi
        fi
        # 开始反馈改由 quickshell 灵动岛（RecordIndicator / 岛屿捕获条）承担
        set_recording_state true
        wf-recorder --pixel-format yuv420p \
            -f "./recording_$(getdate).mp4" --geometry "$region" \
            "${ENC_ARGS[@]}" "${AUDIO_ARGS[@]}"
    fi
    set_recording_state false
fi
