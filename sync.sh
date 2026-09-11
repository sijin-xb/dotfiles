#!/usr/bin/env bash
# sync.sh — 把 $HOME 活文件改动同步回 dotfiles 源仓库
#
#   ./sync.sh <file>...      同步（自动匹配 dot_/executable_ 前缀）
#   ./sync.sh -n <file>...   只看差异
#
# 示例:
#   ./sync.sh ~/.config/hypr/custom/general.lua
#   ./sync.sh ~/.config/fish/config.fish ~/.config/fuzzel/fuzzel.ini

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_REAL="${HOME%/}"
DRY_RUN=false

if [[ "${1:-}" == "-n" || "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    shift
fi

if [[ $# -eq 0 ]]; then
    awk 'NR>1 { if (/^#/) { sub(/^# ?/, ""); print } else exit }' "$0"
    exit 1
fi

sync_one() {
    local live="$1"
    live="${live%/}"
    [[ "$live" != /* ]] && live="$PWD/$live"

    if [[ "$live" != "$HOME_REAL/"* ]]; then
        printf '跳过（不在 $HOME 下）: %s\n' "$live" >&2
        return 0
    fi

    local rel="${live#$HOME_REAL/}"
    local first="${rel%%/*}"
    local rest="${rel#*/}"
    local src_rel="dot_${first#.}/$rest"
    local dst="$SRC/$src_rel"

    if [[ ! -e "$dst" ]]; then
        local cand
        cand="$(dirname "$src_rel")/executable_$(basename "$src_rel")"
        if [[ -e "$SRC/$cand" ]]; then
            dst="$SRC/$cand"
            src_rel="$cand"
        fi
    fi

    if [[ ! -e "$live" ]]; then
        printf '跳过（活文件不存在）: %s\n' "$live" >&2
        return 0
    fi

    if [[ ! -e "$dst" ]]; then
        printf '跳过（源中无对应文件）: %s\n' "$src_rel" >&2
        printf '  新增文件请先在源目录创建对应 dot_ 文件\n' >&2
        return 0
    fi

    if cmp -s "$live" "$dst"; then
        printf '无变化: %s\n' "$src_rel"
        return 0
    fi

    if $DRY_RUN; then
        printf '[dry-run] 有差异: %s\n' "$src_rel"
    else
        cp -p "$live" "$dst"
        printf '已同步: %s\n' "$src_rel"
    fi
}

for f in "$@"; do
    sync_one "$f"
done
