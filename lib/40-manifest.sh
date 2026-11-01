# ============================================================
# 部署清单与计划
# 指纹、清单读写、源树遍历、增量计划 —— update 与 install 的共同底座。
# ============================================================
#
# install 从零部署：装包、拉底盘、编插件、部署文件。重跑要好几分钟，
# 而且会重拉上游底盘冲掉本地改动。
# update 只做文件层增量同步：比对清单、新增/覆盖/清理、写回。
# 默认不碰 pacman / AUR / 底盘 clone。
#
# 清单记录哪些文件是本脚本放进去的，以及部署时的内容指纹。
# 没有清单就无法安全清理：仓库删掉的文件会永远留在 $HOME，
# 而不敢确定归属时清理等于删用户文件。
#
# 三种情况：
#   源变了 + 目标 == 清单指纹  用户没动过，安全覆盖
#   源变了 + 目标 != 清单指纹  用户改过，覆盖前报出来
#   源没变                     不碰
#
# 清单按会话与合成器分开存。部署范围本身就跟会话走，换会话是另一套几百个
# 文件，拿旧清单 diff 会把它们全判成已删除。
#
# 清理一律移到备份目录，不 rm。备份根与 rollback 共用。

PRE_UPDATE_PREFIX="pre-update"

# 会话后缀：清单 / 版本记录按它分开
manifest_suffix() { printf '%s-%s' "${QS_SHELL:-unknown}" "${COMPOSITOR:-unknown}"; }
manifest_path()   { printf '%s/deployed-%s.tsv' "$STATE_DIR" "$(manifest_suffix)"; }
revision_path()   { printf '%s/deployed-revision-%s' "$STATE_DIR" "$(manifest_suffix)"; }
session_path()    { printf '%s/deployed-session' "$STATE_DIR"; }

# 内容指纹。
# ⚠ 符号链接记**链接目标**而不是跟随：systemd/user/symlink_mako.service 的内容
#   是 /dev/null，跟随过去会变成「哈希 /dev/null 的内容」，改链接目标检测不出来。
fingerprint() {
    local p="$1"
    if [[ -L "$p" ]]; then
        printf 'link:%s' "$(readlink "$p")"
    elif [[ -f "$p" ]]; then
        sha256sum "$p" 2>/dev/null | cut -d' ' -f1
    else
        printf 'absent'
    fi
}

# 写清单。$@ = 相对 $HOME 的路径
manifest_write() {
    local out; out="$(manifest_path)"
    ensure_dirs
    : > "$out"
    local rel
    for rel in "$@"; do
        [[ -n "$rel" ]] || continue
        printf '%s\t%s\n' "$(fingerprint "$HOME/$rel")" "$rel" >> "$out"
    done
}

# 读旧清单到关联数组 OLD_MANIFEST[relpath]=指纹。返回 1 = 没有清单（首次）
declare -A OLD_MANIFEST=()
manifest_read() {
    OLD_MANIFEST=()
    local f; f="$(manifest_path)"
    [[ -s "$f" ]] || return 1
    local fp rel
    while IFS=$'\t' read -r fp rel; do
        [[ -n "$rel" ]] && OLD_MANIFEST["$rel"]="$fp"
    done < "$f"
    return 0
}

current_revision() {
    if have git && [[ -d "$SRC/.git" ]]; then
        git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo unknown
    else
        echo unknown
    fi
}

# 记录本次部署的版本与会话。update 靠它做版本比对、靠 session_path 沿用会话。
record_revision() {
    ensure_dirs
    local rev branch dirty
    rev="$(current_revision)"
    branch="$(git -C "$SRC" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
    dirty="$(git -C "$SRC" status --porcelain 2>/dev/null | wc -l)"
    {
        printf 'revision=%s\n'   "$rev"
        printf 'branch=%s\n'     "$branch"
        printf 'dirty=%s\n'      "$dirty"
        printf 'session=%s\n'    "${QS_SHELL:-unknown}"
        printf 'compositor=%s\n' "${COMPOSITOR:-unknown}"
        printf 'time=%s\n'       "$(date -Iseconds)"
    } > "$(revision_path)"
    printf '%s|%s\n' "${QS_SHELL:-unknown}" "${COMPOSITOR:-unknown}" > "$(session_path)"
}

# 把仓库源树遍历一遍，对每个「应该部署」的文件调用回调。
# 回调参数：源文件 / 目标目录 / 目标文件名 / 仓库内相对路径
# 过滤规则与 [5/7] 完全一致（chezmoi 前缀在 deploy_one_file 内部剥离）。
# ── 壁纸目录：把仓库自带的壁纸铺到 ~/Pictures/Wallpapers ────────────────
# 壁纸选择器（Ctrl+Super+T）读这个目录。Pictures/Wallpapers 不在部署范围内，
# 新装机器上目录为空，选择器会显示「No wallpapers found」。
#
# 只补不覆盖：目标没有就复制；已有同名时内容相同跳过，
# 内容不同说明是用户自己的文件，不动。
# install 与 update 都调用，往仓库加壁纸后 update 也能带过去。
sync_wallpapers() {
    local src="$SRC/Pictures/Wallpapers"
    local dst="$HOME/Pictures/Wallpapers"
    [[ -d "$src" ]] || return 0
    mkdir -p "$dst"
    local f base n_copied=0 n_kept=0 n_same=0
    while IFS= read -r -d '' f; do
        base="$(basename "$f")"
        if [[ ! -e "$dst/$base" ]]; then
            cp -p "$f" "$dst/$base"
            n_copied=$((n_copied + 1))
        elif cmp -s "$f" "$dst/$base"; then
            n_same=$((n_same + 1))
        else
            n_kept=$((n_kept + 1))
        fi
    done < <(find "$src" -maxdepth 1 -type f -print0 | LC_ALL=C sort -z)
    say "壁纸目录已就绪：~/Pictures/Wallpapers（新铺 $n_copied，仓库与本地一致 $n_same，保留本地版本 $n_kept）"
}
