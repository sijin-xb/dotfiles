function yay --wraps yay --description "yay，下载/构建/安装进度实时上报灵动岛"
    # 仅在交互 shell、stdout 是终端、灵动岛在跑时启用进度上报，其余场景原样透传
    if not status is-interactive; or not test -t 1; or not type -q qs; or not pgrep -x qs >/dev/null
        command yay $argv
        return
    end

    command yay $argv 2>&1 | tee /dev/tty | tr '\r' '\n' | _island_pkg_progress
    set -l st $pipestatus[1]
    qs -c end4-pC ipc call island task_end package 2>/dev/null
    return $st
end
