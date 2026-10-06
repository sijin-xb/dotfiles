# ============================================================
# 子命令 theme —— 已迁移到 Python（dotctl/commands/theme.py）
# ============================================================
# 这里只留一行转发。九个 sink 的解析与一致性判定现在都在 Python 侧，
# bash 版原有的 theme_read_kv / theme_read_gsettings / theme_consistency
# 随之删除 —— 它们只服务 theme，lib/ 与 tests/ 里没有别的引用。
cmd_theme() { dotctl_run theme "$@"; }
