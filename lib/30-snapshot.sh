# ============================================================
# 快照核心（原 §2）
# 状态文件读写 + 快照生成 / 应用。install、rollback、restore 共用。
# ============================================================
# ============================================================
# 2. 快照核心：snapshot_current / apply_snapshot_from_state
# ============================================================

# $1 = 快照前缀 (pre-install / pre-rollback)
# 写入 state 文件：使用传入的前缀作为 key（如 current / before-rollback）
# $2 = 写入的 state key（可选；不提供就不落 state）
snapshot_current() {
    local prefix="$1"
    local state_key="${2:-}"
    ensure_dirs
    local ts; ts=$(now_ts)
    local snap_path="$SNAP_ROOT/${prefix}-${ts}.tar.gz"
    local tmp_list; tmp_list="$(mktmp)"
    local p rel
    # 筛选真实存在的路径，相对 $HOME
    for p in "${SNAP_PATHS[@]}"; do
        [[ -e "$HOME/$p" ]] && printf '%s\n' "$p" >> "$tmp_list"
    done
    if [[ ! -s $tmp_list ]]; then
        warn "快照：没有任何 rice 路径存在，跳过创建快照"
        rm -f "$tmp_list"
        return 1
    fi
    say "创建快照 [${prefix}] → $(basename "$snap_path")（$(wc -l < "$tmp_list") 个顶级路径）"
    # ⚠ 不要 2>/dev/null 后重试：那会把「权限不足 / 磁盘满」这类真错误藏起来，
    #   只在第二次（不抑制）才暴露；而第一次若是部分写入后失败，第二次会覆盖，
    #   用户看到的错误可能指向别的原因。
    #   这里改成只抑制已知的无害告警（打包时文件被改 / 被删）。
    tar --numeric-owner -pzcf "$snap_path" -C "$HOME" --files-from="$tmp_list" \
        --warning=no-file-changed --warning=no-file-removed
    rm -f "$tmp_list"
    [[ -n $state_key ]] && write_state "$state_key" "$snap_path"
    say "快照完成，大小：$(du -h "$snap_path" | cut -f1)"
    return 0
}

apply_snapshot_from_state() {
    local state_key="$1" allow_back="${2:-}"
    local snap_path
    if ! snap_path="$(read_state "$state_key")"; then
        warn "找不到可用的快照（state/$state_key 丢失或快照文件不存在）"
        return 1
    fi
    local nfiles
    # grep -c 在计数为 0 时仍会打印 "0" 但返回 1，直接 || echo 0 会得到两行
    nfiles="$(tar -tzf "$snap_path" 2>/dev/null | grep -v '/$' | wc -l)"
    session_warning_if_running
    echo "----------------------------------------------------------------------"
    echo "  快照文件 : $(basename "$snap_path")"
    echo "  创建时间 : $(stat -c '%y' "$snap_path" 2>/dev/null || unknown)"
    echo "  覆盖目标 : $HOME（只覆盖快照内包含的约 ${nfiles} 个文件，不会删除快照外的文件）"
    echo "----------------------------------------------------------------------"
    # ⚠ 不要写成 `confirm ...; _r=$?`。confirm 返回 1（用户答 n）是个**裸的
    #   失败命令**，而本脚本开头是 set -euo pipefail。现在能跑只是因为两个
    #   调用点都写成 `apply_snapshot_from_state ... || { ... }` —— bash 对
    #   `||` 列表左侧的整个函数体禁用 -e。新增一个不带 `||` 的调用点，表现就是
    #   「在确认处按 n → 脚本无声退出」，看起来像崩溃。
    #   用 `|| _r=$?` 显式取码：成功时 _r 保持 0，失败时 _r 是该退出码。
    local _r=0
    if [[ "$allow_back" == "back" ]]; then
        confirm "确认从该快照覆盖写入 $HOME？" "allow_back" || _r=$?
    else
        confirm "确认从该快照覆盖写入 $HOME？" || _r=$?
    fi
    case "$_r" in
        0) ;;
        2) return 2 ;;
        *) return 1 ;;
    esac
    say "开始提取 $(basename "$snap_path") ..."
    tar --numeric-owner -pzxf "$snap_path" -C "$HOME"
    say "已提取完成（约 ${nfiles} 个文件）"
    return 0
}

