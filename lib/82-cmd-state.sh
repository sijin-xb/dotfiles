# rollback / restore 已迁移到 Python（dotctl/commands/rollback.py）。
# 两者会真的覆盖 $HOME，所以实现里那几处细节（覆盖前先存 pre-rollback 快照、
# 确认的三种结果、取消时一个字节都不写）必须与原先一致。
# ⚠ 快照原语（snapshot_current / read_state / ensure_dirs /
#   session_warning_if_running）仍由 bash 侧提供 —— install 与 update 还在
#   用它，见 dotctl/snapshot.py 的说明。
cmd_rollback() { dotctl_run rollback "$@"; }

cmd_restore() { dotctl_run restore "$@"; }

# cmd_archive：打包存档
# 支持参数：-o PATH  --delete
cmd_archive() {
    local out_path="" do_delete=0
    while (($#)); do
        case "$1" in
            -o)
                # -o 必须带路径：set -u 下直接取 $2 会因未绑定变量裸崩
                [[ $# -ge 2 ]] || die "archive: -o 需要一个输出路径参数，例如：$0 archive -o ~/backup.tar.gz"
                out_path="$2"; shift 2 ;;
            -o=*) out_path="${1#-o=}"; shift ;;
            --delete) do_delete=1; shift ;;
            --help|-h) print_help; return 0 ;;
            *) warn "archive 未知参数: $1（已忽略）"; shift ;;
        esac
    done
    [[ -z $out_path ]] && out_path="$HOME/dotfiles-archive-$(now_ts).tar.gz"
    # 输出目录必须已存在且可写：tar 不会自动建父目录，等到 tar 报错再查会难懂得多
    local out_dir; out_dir="$(dirname "$out_path")"
    [[ -d $out_dir ]] || die "输出目录不存在：$out_dir（先创建目录，或用 -o 指定别的路径）"
    [[ -w $out_dir ]] || die "输出目录不可写：$out_dir"
    ensure_dirs

    # 组装完整归档路径集 = SNAP_PATHS + EXTRA_ARCHIVE_PATHS
    local all_paths=()
    local p
    for p in "${SNAP_PATHS[@]}"; do all_paths+=("$p"); done
    for p in "${EXTRA_ARCHIVE_PATHS[@]}"; do all_paths+=("$p"); done

    local tmp_list; tmp_list="$(mktmp)"
    local total_size=0
    for p in "${all_paths[@]}"; do
        if [[ -e "$HOME/$p" ]]; then
            printf '%s\n' "$p" >> "$tmp_list"
            local sz; sz="$(du -sk "$HOME/$p" 2>/dev/null | awk '{print $1}')"
            [[ -n ${sz:-} ]] && total_size=$((total_size + sz))
        fi
    done
    if [[ ! -s $tmp_list ]]; then
        warn "没有可打包的 rice 相关文件，退出。"
        rm -f "$tmp_list"
        return 1
    fi
    local total_h
    total_h="$(numfmt --to=iec "${total_size}K" 2>/dev/null || echo "${total_size} KB")"
    echo "----------------------------------------------------------------------"
    echo "  将打包 $(wc -l < "$tmp_list") 个顶级路径，总大小约：${total_h}"
    echo "  源路径清单（缺省自动跳过）："
    for p in "${all_paths[@]}"; do
        [[ -e "$HOME/$p" ]] && printf '     \033[1;32m✓\033[0m ~/%s\n' "$p" || printf '     \033[1;33m·\033[0m ~/%s （缺失，跳过）\n' "$p"
    done
    echo "  输出文件：$out_path"
    echo "----------------------------------------------------------------------"
    # 2 = 用户主动取消，区别于 1 = 真的失败。调用方必须能区分这两者：
    # cmd_uninstall 里「拒绝存档」被当成「存档成功」会让用户以为已有备份，
    # 接着就去删文件了。
    confirm "确认开始打包？" || { say "已取消打包，未写入任何文件。"; return 2; }

    # 打包：包含一个 MANIFEST.txt
    local tmpdir; tmpdir="$(mktmpd)"
    local manifest="$tmpdir/MANIFEST.txt"
    {
        echo "# sijin-xb's dotfiles archive MANIFEST"
        echo "用户名      : ${USER:-unknown}"
        echo "时间戳      : $(date -Iseconds)"
        echo "主机名      : $(hostname 2>/dev/null || unknown)"
        echo "Rice 版本  : $RICE_VERSION"
        echo "打包命令行  : $0 $*"
        echo
        echo "源路径清单（相对 \$HOME）："
        for p in "${all_paths[@]}"; do
            [[ -e "$HOME/$p" ]] && echo "  [PRESENT]  $p" || echo "  [MISSING]  $p"
        done
        echo
        echo "注意：.local/state/dotfiles-backup/snapshots/ 已排除。"
        echo "      那些快照覆盖的正是同一批路径，包含进来会让本包体积"
        echo "      随安装/回档次数接近平方增长。需要历史快照请单独备份该目录。"
        echo
        echo "归档内实际包含的文件列表（前 50 项）："
        sort "$tmp_list" | head -50
    } > "$manifest"
    say "打包中 ..."
    # ⚠ 一次成型，**不要**「先建只含 MANIFEST 的包、再 -r 追加配置」。
    #   GNU tar 对压缩归档**从不支持**追加 —— 实测
    #       tar -pzrf x.tgz y   →  tar: 无法更新压缩归档文件（exit 2）
    #   所以那条路是死代码，每次都会掉进回退分支；而回退要把 MANIFEST 复制成
    #   $HOME/.ARCHIVE-MANIFEST.tmp —— 中途 Ctrl-C 就把它留在 $HOME，
    #   还会被后续快照和下次归档一起打进去。
    #
    #   这里用两个 -C 在同一个 tar 进程里指定不同基准目录：先收 tmpdir 里的
    #   MANIFEST.txt，再收 $HOME 下的配置。
    #   ⚠ 两个 -C 必须给**绝对路径**：GNU tar 的 -C 是相对前一个 -C 解析的，
    #     相对路径会拼成 tartest/tmpd/tartest/home 这种不存在的路径。
    # ⚠ --exclude 是**位置敏感**的（只影响它之后列出的文件），必须放在
    #   --files-from 之前。
    #   排除 snapshots/：里面的快照覆盖的正是同一批 SNAP_PATHS，不排除的话
    #   每次归档都会把之前所有快照再打一遍，体积随安装次数接近平方增长。
    tar --numeric-owner -pzcf "$out_path" \
        --exclude='.local/state/dotfiles-backup/snapshots' \
        -C "$tmpdir" MANIFEST.txt \
        -C "$HOME" --files-from="$tmp_list"
    rm -rf "$tmpdir" "$tmp_list"
    say "打包完成 → $out_path ($(du -h "$out_path" | cut -f1))"

    if ((do_delete)); then
        echo
        # 打包带全部（备份从宽），删除只删范围内（另一套合成器配置原样保留）
        uninstall_compositor_scope
        local del_paths=()
        mapfile -t del_paths < <(active_snap_paths)
        for p in "${EXTRA_ARCHIVE_PATHS[@]}"; do del_paths+=("$p"); done
        warn "--delete 模式：以下 rice 管理路径将在确认后删除（其他用户文件绝不触碰）："
        for p in "${del_paths[@]}"; do
            if [[ -e "$HOME/$p" ]]; then
                printf '     rm -rf ~/%s  (%s)\n' "$p" "$(du -sh "$HOME/$p" 2>/dev/null | cut -f1)"
            fi
        done
        confirm "⚠️  真的要删除吗？此操作不可恢复！" || { say "已取消删除。"; return 0; }
        for p in "${del_paths[@]}"; do
            if [[ -e "$HOME/$p" ]]; then
                rm -rf "$HOME/$p"
                echo "     已删除 ~/$p"
            fi
        done
        say "--delete 清理完成。建议注销重新登录。"
    fi
}

# 卸载：先让用户选"是否顺便存档"，然后存档 → 执行 --delete（可选）
cmd_uninstall() {
    # 与其他子命令统一：认 -h，多余参数显式告警而不是静默忽略
    # （以前 `./install.sh rollback --dry-run` 既不报错也不生效）。
    case "${1:-}" in
        -h|--help) print_help; return 0 ;;
        "") ;;
        *) warn "uninstall 不接受参数，已忽略: $*" ;;
    esac
    ensure_dirs
    echo "卸载 rice 配置：建议先打包存档作为备份。"
    local do_archive=1
    confirm "是否先打包存档？" || do_archive=0
    if ((do_archive)); then
        local archive_path="$HOME/dotfiles-archive-uninstall-$(now_ts).tar.gz"
        local arc_rc=0
        cmd_archive -o "$archive_path" || arc_rc=$?
        case "$arc_rc" in
            0) ;;
            2) # 用户在打包确认处按了 n —— 必须说清楚，否则他以为有备份
               warn "你取消了存档 —— 本次卸载**没有备份**。"
               confirm "仍然继续卸载？" || { say "已中止，未删除任何文件。"; return 0; } ;;
            *) warn "存档失败，将继续执行卸载（无备份）" ;;
        esac
    fi
    # 只删本次范围内的合成器 / shell 配置，其余原样保留（见 active_snap_paths 说明）
    uninstall_compositor_scope
    uninstall_shell_scope
    confirm "确认删除 rice 相关路径？（合成器与 shell 配置只删上述范围；不会删除其他个人文件）" || return 0
    local paths=() p
    mapfile -t paths < <(active_snap_paths)
    for p in "${paths[@]}" "${EXTRA_ARCHIVE_PATHS[@]}"; do
        if [[ -e "$HOME/$p" ]]; then
            rm -rf "$HOME/$p"
            echo "     已删除 ~/$p"
        fi
    done
    say "卸载完成。如果你还想保留 quickshell/hyprland 程序本身，请使用 pacman -Rns 手动卸载。"
}

