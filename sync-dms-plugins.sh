#!/usr/bin/env bash
# 把本机 ~/.config/DankMaterialShell/plugins 里**启用中的插件**同步进本仓库
# （sijin-xb/dotfiles，公开）。
#
# 为什么单独一个脚本、不塞进 install.sh
# ------------------------------------
# install.sh 的 [5/7] 是**从仓库往家目录部署**（dot_* → $HOME，含 dot_ 解码）。
# 插件是反方向的一步：家目录（DMS 插件商店装的）→ 仓库。
# 方向相反、只在开发时用，所以独立成脚本，别混进安装流程。
#
# 同步什么、不同步什么（这是重点）
# --------------------------------
# DMS 的 plugins/ 目录里其实是三类东西：
#
#   .repos/<hash>/…        插件商店 clone 下来的**整个第三方插件仓库**
#                          （本机 1284 个文件、20+ 个插件）→ **不同步**
#                          它可随时重新拉取，且不是你写的；仓库里只保留
#                          plugins/dot_repos/.keep 这个占位，让部署后
#                          目录存在。要它请显式加 --with-store-cache。
#   *.meta                 商店元数据（repo= / path= / repodir=）→ 默认不同步
#                          （也是商店状态，非你的配置）。--with-store-meta 可带。
#   <插件名>/              真正启用的插件 ← **只同步这些**
#
# 与 install.sh 一致的约定
# ------------------------
# 1. chezmoi 前缀编码：各级 basename 的**前导点**改写为 dot_。
#      例：plugins/.repos/x  → plugins/dot_repos/x
#    与 install.sh 部署循环里的解码严格互逆。
# 2. 跳过仓库/部署都不该管的运行时生成物：
#      任意层级的 .git   （.chezmoiignore:50 与 .gitignore 都点名了；
#                          git 也不会把嵌套 .git 当普通文件收）
#      __pycache__ / *.pyc / *.bak / *.bak-*
#
# 用法
#   bash sync-dms-plugins.sh                      # dry-run（默认）
#   bash sync-dms-plugins.sh --yes                # 写入工作区（不自动 commit）
#   bash sync-dms-plugins.sh --yes --prune        # 额外删掉"仓库有、本机已无"的文件
#   bash sync-dms-plugins.sh --verbose            # 逐文件打印（默认只按插件汇总）
#   bash sync-dms-plugins.sh --with-store-meta    # 连 *.meta 一起同步
#
# ⚠ 必须在**能完整读取 plugins 目录**的环境里跑。某些容器/受限挂载下会出现
#   "目录项可见（ls 看得到）但文件内容读不出来（find -type f 返回 0）"，
#   那种情况下同步会产出**空壳插件**并写进仓库。脚本会逐插件自检并跳过。
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HOME/.config/DankMaterialShell/plugins"
DST="$REPO_DIR/dot_config/DankMaterialShell/plugins"

DO_IT=0; PRUNE=0; VERBOSE=0; WITH_META=0; WITH_CACHE=0
for a in "$@"; do
    case "$a" in
        --yes)              DO_IT=1 ;;
        --prune)            PRUNE=1 ;;
        --verbose|-v)       VERBOSE=1 ;;
        --with-store-meta)  WITH_META=1 ;;
        --with-store-cache) WITH_CACHE=1 ;;
        -h|--help)          sed -n '2,45p' "$0"; exit 0 ;;
        *) echo "未知参数: $a" >&2; exit 2 ;;
    esac
done

say()  { printf '%s\n' "$*"; }
warn() { printf ' -> %s\n' "$*" >&2; }
die()  { printf '错误：%s\n' "$*" >&2; exit 1; }

[[ -d "$SRC" ]] || die "源目录不存在：$SRC"

# chezmoi 编码：逐级把 basename 的前导点换成 dot_
encode() {
    local rel="$1" out="" part oldifs="$IFS"
    IFS='/'
    for part in $rel; do
        [[ "$part" == .* ]] && part="dot_${part#.}"
        out="${out:+$out/}$part"
    done
    IFS="$oldifs"
    printf '%s' "$out"
}

skip_path() {   # $1 = 相对 plugins/ 的路径
    case "$1" in
        .git|.git/*|*/.git|*/.git/*)          return 0 ;;
        __pycache__|__pycache__/*|*/__pycache__|*/__pycache__/*) return 0 ;;
        *.pyc)                                return 0 ;;
        *.bak|*.bak-*)                        return 0 ;;
    esac
    return 1
}

# ---------- 选择要同步的顶层条目 ----------
# ⚠ 这里刻意**不用** `< <(ls …)` 进程替换：它依赖 /dev/fd，容器 / 精简 chroot
#   里可能不存在，一旦不可用整段枚举会静默为空 —— 表现就是"同步成功但什么都没同步"。
TOPS=()
TOP_LIST="$(mktemp)"
( cd "$SRC" && ls -A 2>/dev/null | sort ) > "$TOP_LIST"
while IFS= read -r e; do
    case "$e" in
        .repos)
            (( WITH_CACHE )) && TOPS+=("$e") || say "  跳过 .repos/（插件商店的克隆缓存；--with-store-cache 可带）"
            ;;
        *.meta)
            (( WITH_META )) && TOPS+=("$e") || say "  跳过 $e（商店元数据；--with-store-meta 可带）"
            ;;
        *) TOPS+=("$e") ;;
    esac
done < "$TOP_LIST"

say "=================================================================="
say "  DMS 插件同步 → dotfiles（公开仓库）"
(( DO_IT )) && say "  模式：**执行写入**" || say "  模式：DRY-RUN（只列不改）。写入加 --yes"
say "  源  ：$SRC"
say "  目标：$DST"
say "=================================================================="
say

LIST="$(mktemp)"; WANT="$(mktemp)"
trap 'rm -f "$LIST" "$WANT" "$TOP_LIST"' EXIT

add=0; upd=0; skip=0; skipped_plugins=0

for top in "${TOPS[@]}"; do
    p_src="$SRC/$top"

    # 目录型条目：先做可读性自检，挡住"空壳插件"
    if [[ -d "$p_src" ]]; then
        n_ls=$(ls -A "$p_src" 2>/dev/null | wc -l)
        n_find=$(find "$p_src" -type f 2>/dev/null | wc -l)
        if (( n_ls > 0 && n_find == 0 )); then
            warn "跳过 $top/：目录里有 $n_ls 个条目，但一个文件都读不出来"
            warn "  （受限容器/挂载的典型症状）。在真实终端里重跑本脚本。"
            skipped_plugins=$((skipped_plugins+1))
            continue
        fi
    fi

    find "$p_src" -type f -print0 2>/dev/null | tr '\0' '\n' | sed "s|^$SRC/||" | sort > "$LIST"
    p_add=0; p_upd=0
    while IFS= read -r rel; do
        [[ -z "$rel" ]] && continue
        if skip_path "$rel"; then skip=$((skip+1)); continue; fi
        enc="$(encode "$rel")"
        printf '%s\n' "$enc" >> "$WANT"
        dst="$DST/$enc"
        if [[ -e "$dst" ]]; then
            cmp -s "$SRC/$rel" "$dst" || { p_upd=$((p_upd+1)); upd=$((upd+1)); (( VERBOSE )) && say "  更新 $enc"; }
        else
            p_add=$((p_add+1)); add=$((add+1))
            (( VERBOSE )) && say "  新增 $enc"
        fi
        if (( DO_IT )); then
            mkdir -p "$(dirname "$dst")"
            cp -p "$SRC/$rel" "$dst"
        fi
    done < "$LIST"
    say "  $(printf '%-22s' "$top") 新增 $p_add / 更新 $p_upd"
done

# ---------- 反向：仓库里有、本机已无 ----------
gone=0
if [[ -d "$DST" ]]; then
    find "$DST" -type f 2>/dev/null | sed "s|^$DST/||" | sort > "$LIST.dst"
    while IFS= read -r enc; do
        grep -Fxq "$enc" "$WANT" && continue
        gone=$((gone+1))
        if (( PRUNE )); then
            say "  删除 $enc"
            (( DO_IT )) && rm -f "$DST/$enc"
        elif (( VERBOSE )); then
            say "  仓库多余（未删）$enc"
        fi
    done < "$LIST.dst"
    rm -f "$LIST.dst"
fi

say
say "------------------------------------------------------------------"
say "  新增 $add / 更新 $upd / 跳过 $skip（.git、字节码、备份）"
(( skipped_plugins )) && warn "有 $skipped_plugins 个插件因为**内容读不出来**被跳过，它们没有被同步！"
if (( gone )); then
    if (( PRUNE )); then say "  删除 $gone"
    else warn "有 $gone 个文件仓库有、本机已无。确认是要删的再加 --prune（先用 --verbose 看清单）。"; fi
fi
say
if (( DO_IT )); then
    say "工作区已改好，没有自动提交。核验与提交："
    say "  git -C '$REPO_DIR' status --short -- dot_config/DankMaterialShell/plugins"
    say "  git -C '$REPO_DIR' add -A dot_config/DankMaterialShell/plugins && git commit"
else
    say "确认无误后执行： bash $0 --yes"
fi
