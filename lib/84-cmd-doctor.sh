# ============================================================
# 子命令 doctor —— 已迁移到 Python（dotctl/commands/doctor.py）
# ============================================================
# 这里只留一行转发。系统 / 工具链 / 会话 / 依赖缺口 / QML 自检 / 备份目录
# 六段的判定现在都在 Python 侧。
#
# ⚠ doctor 里那一行「bash 5.3」取自 BASH_VERSINFO，它不是导出变量 ——
#   由 lib/15-python.sh 的 dotctl_run 递过去，见那里的注释。
cmd_doctor() { dotctl_run doctor "$@"; }
