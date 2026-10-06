# ============================================================
# 子命令 update —— 已迁移到 Python（dotctl/commands/update.py）
# ============================================================
# 这里只留一行转发。清单 diff、冲突安全网、备份与删除清理、QML 自检现在都在
# Python 侧；部署原语在 dotctl/deploy.py。
#
# ⚠ 没有旧清单时走「首次升级」安全分支：目标已存在且与源不同的文件不覆盖，
#   列出来让用户决定。本机实测过盲覆盖的代价 —— 会把 live 里带修复的文件
#   退回仓库旧版。
# ⚠ ensure_repo / choose_session / sync_wallpapers / record_revision /
#   session_warning_if_running 仍由 bash 提供（install 还在用，见 dotctl/deploy.py
#   与 dotctl/snapshot.py 的说明）。
cmd_update() { dotctl_run update "$@"; }
