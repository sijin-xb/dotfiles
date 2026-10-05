# ============================================================
# 子命令 status：当前部署状态一览（只读）
# ============================================================

# 会话来源：优先读部署时写下的 deployed-session —— 那才代表**机器现状**；
# 环境变量只是「这次想装什么」，没有部署记录时才退回它推断。
# 副作用：会把 QS_SHELL / COMPOSITOR 设成当前生效值，后续函数（manifest_path
# 等）依赖它们，所以每个命令开头都要先调一次。
status_resolve_session() {
    local sp; sp="$(session_path)"
    if [[ -s "$sp" ]]; then
        IFS='|' read -r QS_SHELL COMPOSITOR < "$sp"
    else
        session_to_parts
    fi
}

status_session_label() {
    case "${QS_SHELL:-}:${COMPOSITOR:-}" in
        end4-pC:hyprland)  printf 'end4pc（Hyprland + quickshell end4-PC）' ;;
        caelestia:hyprland) printf 'caelestia（Hyprland + caelestia shell）' ;;
        dms:niri)          printf 'dms（niri + DankMaterialShell）' ;;
        *)                 printf '%s + %s' "${QS_SHELL:-未知}" "${COMPOSITOR:-未知}" ;;
    esac
}

cmd_status() {
    case "${1:-}" in
        -h|--help)
            cat <<EOF
用法：$0 status

打印当前部署状态，只读、不写任何文件：
  会话 / 部署清单条目数 / 上次部署时间与 revision / 仓库工作区状态 /
  快照数量与最近一份 / 备份目录占用
EOF
            return 0 ;;
        "") ;;
        *) warn "status 不接受参数：$1"; return 2 ;;
    esac

    status_resolve_session
    # 标签手工对齐：printf 的 %-Ns 按字符数补位，中文是双宽，用它会参差不齐。
    printf '会话        %s\n' "$(status_session_label)"

    local mp; mp="$(manifest_path)"
    if [[ -s "$mp" ]]; then
        printf '部署清单    %s · %s 项\n' "$(basename "$mp")" "$(wc -l < "$mp")"
    else
        printf '部署清单    无（这台机器没跑过 install，或清单属于别的会话）\n'
    fi

    local rp; rp="$(revision_path)"
    if [[ -s "$rp" ]]; then
        printf '上次部署    %s（revision %s · %s · 当时工作区改动 %s 项）\n' \
            "$(sed -n 's/^time=//p'     "$rp")" \
            "$(sed -n 's/^revision=//p' "$rp")" \
            "$(sed -n 's/^branch=//p'   "$rp")" \
            "$(sed -n 's/^dirty=//p'    "$rp")"
    else
        printf '上次部署    无记录\n'
    fi

    if have git && [[ -d "$SRC/.git" ]]; then
        printf '仓库        %s · %s · 当前 revision %s（工作区改动 %s 项）\n' \
            "$SRC" "$RICE_VERSION" \
            "$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo unknown)" \
            "$(git -C "$SRC" status --porcelain 2>/dev/null | wc -l)"
    else
        printf '仓库        %s · %s（非 git 检出）\n' "$SRC" "$RICE_VERSION"
    fi

    local snaps=0 newest=""
    if [[ -d "$SNAP_ROOT" ]]; then
        snaps="$(find "$SNAP_ROOT" -maxdepth 1 -name '*.tar.gz' 2>/dev/null | wc -l)"
        # -printf '%T@\t%p' 而不是 `ls -t`：文件名里没有空格，但路径里有中文时
        # ls 的排序在不同 locale 下不稳定，按 mtime 排序更可靠。
        newest="$(find "$SNAP_ROOT" -maxdepth 1 -name '*.tar.gz' -printf '%T@\t%p\n' 2>/dev/null \
            | sort -rn | head -1 | cut -f2-)"
    fi
    if [[ -n "$newest" ]]; then
        printf '快照        %s 份 · 最近 %s（%s）\n' "$snaps" "$(basename "$newest")" \
            "$(du -h "$newest" 2>/dev/null | cut -f1)"
    else
        printf '快照        0 份\n'
    fi

    if [[ -d "$BACKUP_ROOT" ]]; then
        printf '备份占用    %s（%s）\n' "$(du -sh "$BACKUP_ROOT" 2>/dev/null | cut -f1)" "$BACKUP_ROOT"
    else
        printf '备份占用    无（%s 不存在）\n' "$BACKUP_ROOT"
    fi
    return 0
}
