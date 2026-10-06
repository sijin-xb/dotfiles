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
    # DOTCTL_BASH_VERSION 同理：doctor 里那一行「bash 5.3」取自 BASH_VERSINFO，
    # 而它也不是导出变量，Python 侧只能由这里递过去。
    #
    # DOTCTL_COLOR：把 bash 侧已经算好的颜色开关递过去。它按 install.sh 启动
    # 时的 fd 1 判定，而 Python 是子进程 —— 自己判 isatty() 会得出相反的结论
    # （同一份输出一边带 ANSI 一边不带；archive 的计划清单实测踩到）。
    # DOTCTL_BACKUP_ROOT / _SNAP_ROOT / _STATE_DIR：bash 侧这三个路径是 source
    # 时算好的**常量**，之后不再随 $HOME 变。Python 若自己按 $HOME 动态推，会在
    # 「改了 HOME 再调函数」的场景下与 bash 分道扬镳 —— archive 的测试就是
    # 这么暴露的：子 shell 里换 HOME 后，bash 仍用旧 HOME 的备份目录（于是
    # 「无可打包路径」→ 返回 1），Python 动态读新 HOME、被 ensure_dirs 建出目录
    # → 变成有路径 → 返回 0。传下来才与 bash 一致。
    DOTCTL_SELF="${DOTCTL_SELF:-$0}" \
    DOTCTL_COLOR="$([[ -n $C_GREEN ]] && echo 1 || echo 0)" \
    DOTCTL_BASH_VERSION="${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}" \
    DOTCTL_BACKUP_ROOT="$BACKUP_ROOT" \
    DOTCTL_SNAP_ROOT="$SNAP_ROOT" \
    DOTCTL_STATE_DIR="$STATE_DIR" \
    TMPRUN="${TMPRUN:-}" \
    PYTHONPATH="$SRC${PYTHONPATH:+:$PYTHONPATH}" python3 -m dotctl "$@"
}

# 归档涉及的路径清单（SNAP_PATHS + EXTRA_ARCHIVE_PATHS），一行一个。
# 供 dotctl 的 archive 读取 —— 与 deps_collect 同理：清单留在 bash 侧当唯一
# 来源，Python 不另抄一份，否则两边迟早不一致（改了 bash 忘改 Python，
# 归档范围就与快照/卸载范围对不上）。
dotctl_archive_paths() {
    printf '%s\n' "${SNAP_PATHS[@]}" "${EXTRA_ARCHIVE_PATHS[@]}"
}

# EXTRA_ARCHIVE_PATHS（快照目录 / quickshell 状态 / 缓存），一行一个。
# 与 dotctl_archive_paths 分开：archive 的 --delete 只删这一份 + 当前会话的
# active_snap_paths，不删 SNAP_PATHS 全集。
dotctl_extra_paths() {
    printf '%s\n' "${EXTRA_ARCHIVE_PATHS[@]}"
}

# 用**冻结的**路径常量建目录（不经 ensure_dirs）。
# ⚠ 必须这样：ensure_dirs 用的是运行时 $HOME，而 BACKUP_ROOT / SNAP_ROOT /
#   STATE_DIR 是 source 时算好的常量。在「改了 HOME 再调函数」的场景下两者
#   会分叉 —— archive 的测试就踩到了：ensure_dirs 在 empty-home 下建出
#   dotfiles-backup，于是它自己成了「可打包路径」，本该返回 1 的场景返回 0。
#   这里照抄 bash 的可观察行为：目录建在冻结路径上。
dotctl_ensure_frozen_dirs() {
    mkdir -p "$BACKUP_ROOT" "$SNAP_ROOT" "$STATE_DIR"
}
