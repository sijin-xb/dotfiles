# rollback / restore 已迁移到 Python（dotctl/commands/rollback.py）。
# 两者会真的覆盖 $HOME，所以实现里那几处细节（覆盖前先存 pre-rollback 快照、
# 确认的三种结果、取消时一个字节都不写）必须与原先一致。
# ⚠ 快照原语（snapshot_current / read_state / ensure_dirs /
#   session_warning_if_running）仍由 bash 侧提供 —— install 与 update 还在
#   用它，见 dotctl/snapshot.py 的说明。
cmd_rollback() { dotctl_run rollback "$@"; }

cmd_restore() { dotctl_run restore "$@"; }

# archive 已迁移到 Python（dotctl/commands/archive.py）。
# ⚠ 用户取消返回 2、真的失败返回 1 —— cmd_uninstall 靠这个区分「拒绝存档」
#   与「存档失败」，混淆会让用户以为已有备份就去删文件。
# ⚠ 归档路径清单（SNAP_PATHS + EXTRA_ARCHIVE_PATHS）仍由 bash 侧提供
#   （dotctl_archive_paths / dotctl_extra_paths），见 lib/15-python.sh。
cmd_archive() { dotctl_run archive "$@"; }

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

