# ============================================================
# 子命令 install —— 已迁移到 Python（dotctl/commands/install.py）
# ============================================================
# 这里只留一行转发。七个步骤的**编排**与文件层（[0/7] 快照、[5/7] 部署、
# 清单与版本写回）在 Python 侧；外部流程（装包 / clone 底盘 / cmake 编译 /
# venv）仍在 bash 侧，由 Python 经 bashsrc 按顺序调用 —— 见 lib/15-python.sh
# 末尾那组 dotctl_* 与 install_* 函数。
#
# ⚠ 与 update 的差异：install 会重装包、重拉上游底盘、重编插件，重跑要几分钟，
#   且会冲掉本地对上游底盘的改动。日常升级用 update。
cmd_install() { dotctl_run install "$@"; }
