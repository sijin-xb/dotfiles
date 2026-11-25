#!/usr/bin/env bash
# sync.sh — 把 $HOME 活文件改动同步回 dotfiles 源仓库（活文件 → 源，单向）
#
#   ./sync.sh <file>...      同步
#   ./sync.sh -n <file>...   只看差异，不写盘
#
# 映射与 dotctl/deploy.py 的 map_target() 相反：
#   ~/.config/foo/...  → config/desktop/foo/...  或  config/personal/foo/...
#   ~/.local/foo/...   → local/foo/...
#   ~/.icons/foo/...   → icons/foo/...
#   ~/.vimrc           → vimrc
#
# 分层按「同名子目录只在一层存在」判定；两层都有同名目录时报错退出，
# 因为目标不唯一，由人决定该落到哪层。
#
# 源文件后缀 .private / .symlink 会影响部署属性：
#   .private  部署后 0600 —— 命中时在输出里提示，属性不随内容同步变化
#   .symlink  内容是链接目标 —— 活文件是普通文件则不匹配，跳过
#
# 退出码：0 全部成功或无需改动；1 有跳过或失败项。

set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_REAL="${HOME%/}"
DRY_RUN=false
FAILED=0
SKIPPED=0

usage() { sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

if [[ "${1:-}" == "-n" || "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    shift
elif [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

skip() { printf '跳过（%s）: %s\n' "$1" "$2" >&2; SKIPPED=$((SKIPPED + 1)); }

# 在两层里定位 $HOME 相对路径的首段目录，输出源侧前缀。
config_prefix() {
    local sub="$1"
    local in_desk=0 in_pers=0
    [[ -d "$SRC/config/desktop/$sub" ]] && in_desk=1
    [[ -d "$SRC/config/personal/$sub" ]] && in_pers=1
    if (( in_desk && in_pers )); then
        printf '错误: config/desktop/%s 与 config/personal/%s 同时存在，目标不唯一\n' "$sub" "$sub" >&2
        return 1
    fi
    if (( in_desk )); then printf 'config/desktop\n'; return 0; fi
    if (( in_pers )); then printf 'config/personal\n'; return 0; fi
    printf 'config/desktop\n'
}

# $HOME 相对路径 → 源树相对路径。找不到映射返回 1。
map_source() {
    local rel="$1"
    case "$rel" in
        .config/*)
            local sub="${rel#.config/}"; sub="${sub%%/*}"
            local prefix
            prefix="$(config_prefix "$sub")" || return 1
            printf '%s/%s\n' "$prefix" "${rel#.config/}"
            ;;
        .local/*)  printf 'local/%s\n' "${rel#.local/}" ;;
        .icons/*)  printf 'icons/%s\n' "${rel#.icons/}" ;;
        .vimrc)    printf 'vimrc\n' ;;
        *) return 1 ;;
    esac
}

sync_one() {
    local live="$1"
    live="${live%/}"
    [[ "$live" != /* ]] && live="$PWD/$live"

    if [[ "${live}" != "$HOME_REAL/"* ]]; then
        skip "不在 \$HOME 下" "$live"
        return 0
    fi

    local rel="${live#"$HOME_REAL"/}"

    if [[ ! -e "$live" ]]; then
        skip "活文件不存在" "~/$rel"
        return 0
    fi

    local src_rel
    if ! src_rel="$(map_source "$rel")"; then
        skip "该路径不在部署范围内" "~/$rel"
        return 0
    fi

    local dst="$SRC/$src_rel"
    local attr_note=""

    if [[ ! -e "$dst" ]]; then
        if [[ -e "$dst.private" ]]; then
            dst="$dst.private"; src_rel="$src_rel.private"; attr_note="（.private，部署后 0600）"
        elif [[ -e "$dst.symlink" ]]; then
            if [[ -L "$live" ]]; then
                dst="$dst.symlink"; src_rel="$src_rel.symlink"; attr_note="（.symlink）"
            else
                skip "源是 .symlink 但活文件已是普通文件" "$src_rel"
                return 0
            fi
        else
            skip "源中无对应文件" "$src_rel"
            printf '  新增文件请在 %s 下创建对应条目\n' "$(dirname "$src_rel")" >&2
            return 0
        fi
    fi

    # .symlink 条目比较的是链接目标，不是文件内容
    local same=0
    if [[ "$dst" == *.symlink ]]; then
        [[ "$(readlink "$live" 2>/dev/null)" == "$(cat "$dst")" ]] && same=1
    else
        cmp -s "$live" "$dst" && same=1
    fi

    if (( same )); then
        printf '无变化: %s\n' "$src_rel"
        return 0
    fi

    if $DRY_RUN; then
        printf '[dry-run] 有差异: %s%s\n' "$src_rel" "$attr_note"
        return 0
    fi

    if [[ "$dst" == *.symlink ]]; then
        printf '%s\n' "$(readlink "$live")" > "$dst"
    else
        cp -p "$live" "$dst"
    fi
    printf '已同步: %s%s\n' "$src_rel" "$attr_note"
}

for f in "$@"; do
    sync_one "$f" || FAILED=1
done

if (( SKIPPED + FAILED > 0 )); then
    printf '\n有 %d 项跳过、%d 项失败。\n' "$SKIPPED" "$FAILED" >&2
    exit 1
fi
