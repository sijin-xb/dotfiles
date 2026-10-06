# ============================================================
# 子命令 status —— 已迁移到 Python（dotctl/commands/status.py）
# ============================================================
# 这里只留一行转发：install.sh 的分发与 TUI 的「状态与诊断」都调 cmd_status，
# 入口名保持不变，实现看 dotctl/。会话推断函数已挪到 lib/50-session.sh。
cmd_status() { dotctl_run status "$@"; }
