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

# uninstall 已迁移到 Python（dotctl/commands/uninstall.py）。
# ⚠ 它是唯一会递归删 $HOME 下路径的命令，实现里守的边界：只删
#   active_snap_paths + EXTRA_ARCHIVE_PATHS 的项、按会话过滤、任一确认答 n
#   都不删、以及区分「用户拒绝存档」与「存档失败」。
# ⚠ 范围选择与清单计算必须在同一个 bash 进程里完成 —— 那两个 scope 函数设的
#   变量决定 active_snap_paths 的输出，分两次 fork 会让过滤失效、误删另一套
#   会话的配置。见 lib/15-python.sh 的 dotctl_uninstall_plan。
cmd_uninstall() { dotctl_run uninstall "$@"; }
