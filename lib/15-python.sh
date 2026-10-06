# ============================================================
# Python 引擎（dotctl）的调用入口
# ============================================================
# 迁移期：一部分子命令已迁到 dotctl（纯标准库 Python），其余仍在 bash。
# lib/8x-cmd-*.sh 里已迁的只剩一行转发，实现看 dotctl/commands/。
#
# ⚠ 用 PYTHONPATH 而不是 cd：后者会改掉工作目录，而脚本里所有相对路径都以
#   调用者的 cwd 为准（bash 版一直如此），换了目录行为会跟着变。
#
# ⚠ DOTCTL_SELF：把「调用者看到的安装器路径」传下去。bash 版提示语里写的是
#   $0（`./install.sh` / `install.sh` / 绝对路径，随调用方式变），Python 侧
#   拿不到它，硬编码就会让两边输出对不上。
dotctl_run() {
    have python3 || die "该子命令已迁到 Python 实现，需要 python3 3.11+（sudo pacman -S python）"
    # TMPRUN 要显式传：它是 lib/10-util.sh 里的普通变量（没 export），而
    # clean 必须能认出「当前这次运行自己的临时目录」并跳过它 —— 删了它，
    # 本次运行后续的 mktmp 全部失效，EXIT trap 也没东西可清。
    DOTCTL_SELF="${DOTCTL_SELF:-$0}" \
    TMPRUN="${TMPRUN:-}" \
    PYTHONPATH="$SRC${PYTHONPATH:+:$PYTHONPATH}" python3 -m dotctl "$@"
}
