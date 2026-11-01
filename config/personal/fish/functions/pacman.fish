function pacman --wraps pacman --description "pacman，下载/安装进度实时上报灵动岛"
    # 仅在交互 shell、stdout 是终端、灵动岛在跑时启用进度上报，其余场景原样透传
    if not status is-interactive; or not test -t 1; or not type -q qs; or not pgrep -x qs >/dev/null
        command pacman $argv
        return
    end

    # 需要 root 的安装/卸载/升级且当前不是 root：自动加 sudo
    #（sudo 从 /dev/tty 要密码，不受下面管道影响；只读操作 -Ss/-Si/-Sl/-Sg 不提权）
    set -l cmd pacman
    if not test (id -u) -eq 0
        and string match -rq -- '^-[a-zA-Z]*[UR]' $argv
        or begin
            not test (id -u) -eq 0
            and string match -rq -- '^-[a-zA-Z]*S' $argv
            and not string match -rq -- '^-[a-zA-Z]*[silg]' $argv
        end
        set cmd sudo pacman
    end

    # 原始终端体验照旧（tee 回 tty），同时解析百分比喂给灵动岛。
    # 不强制 --color：管道下 pacman 本来就去色，保证正则解析稳定。
    $cmd $argv 2>&1 | tee /dev/tty | tr '\r' '\n' | _island_pkg_progress
    set -l st $pipestatus[1]
    qs -c end4-pC ipc call island task_end package &>/dev/null
    return $st
end
