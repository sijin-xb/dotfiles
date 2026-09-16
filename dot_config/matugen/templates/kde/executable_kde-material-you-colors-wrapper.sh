#!/usr/bin/env bash
# kde-material-you-colors wrapper
# 读取 matugen 生成的 source color 与当前明暗模式，产出 KDE/Qt 配色方案。
# 调用方：switchwall.sh（换壁纸）、matugen-update.sh（切策略/切明暗）。

set -u

XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
COLOR_FILE="$XDG_STATE_HOME/quickshell/user/generated/color.txt"

if [ ! -r "$COLOR_FILE" ]; then
    echo "kmyc-wrapper: source color not found at $COLOR_FILE" >&2
    exit 0
fi

color=$(tr -d '\n' < "$COLOR_FILE")
if [ -z "$color" ]; then
    echo "kmyc-wrapper: source color is empty" >&2
    exit 0
fi

# kmyc 寄生在 Quickshell 的 venv 里。venv 被重建或尚未创建时静默跳过，
# 不要因为 Qt 配色失败而阻断上游的壁纸 / GTK 流程。
VENV="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$HOME/.local/state/quickshell/.venv}"
if [ ! -f "$VENV/bin/activate" ]; then
    echo "kmyc-wrapper: venv missing at $VENV, skipping Qt theming" >&2
    exit 0
fi

current_mode=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
if [[ "$current_mode" == "prefer-dark" ]]; then
    mode_flag="-d"
else
    mode_flag="-l"
fi

scheme_variant_str=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --scheme-variant)
            scheme_variant_str="${2:-}"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

case "$scheme_variant_str" in
    scheme-content) sv_num=0 ;;
    scheme-expressive) sv_num=1 ;;
    scheme-fidelity) sv_num=2 ;;
    scheme-monochrome) sv_num=3 ;;
    scheme-neutral) sv_num=4 ;;
    scheme-tonal-spot) sv_num=5 ;;
    scheme-vibrant) sv_num=6 ;;
    scheme-rainbow) sv_num=7 ;;
    scheme-fruit-salad) sv_num=8 ;;
    "") sv_num=5 ;;
    *)
        echo "kmyc-wrapper: unknown scheme variant: $scheme_variant_str" >&2
        exit 0
        ;;
esac

# shellcheck source=/dev/null
source "$VENV/bin/activate"

if ! command -v kde-material-you-colors >/dev/null 2>&1; then
    echo "kmyc-wrapper: kde-material-you-colors not installed in venv, skipping" >&2
    deactivate
    exit 0
fi

kde-material-you-colors "$mode_flag" --color "$color" -sv "$sv_num"
deactivate
