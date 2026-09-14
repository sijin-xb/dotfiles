function wget --wraps wget --description "wget，下载进度实时上报灵动岛"
    # 仅在交互 shell、stdout 是终端、灵动岛在跑时启用，其余场景原样透传
    if not status is-interactive; or not test -t 1; or not type -q qs; or not pgrep -x qs >/dev/null
        command wget $argv
        return
    end

    # wget 的进度条在 stderr；非 tty 时默认退化为点阵模式，强制 bar 方便解析
    command wget --progress=bar:force $argv 2>&1 >/dev/tty | tee /dev/tty | tr '\r' '\n' | _island_dl_progress
    set -l st $pipestatus[1]
    qs -c end4-pC ipc call island task_end download 2>/dev/null
    return $st
end
