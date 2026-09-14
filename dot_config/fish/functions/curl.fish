function curl --wraps curl --description "curl，文件下载进度实时上报灵动岛"
    # 仅在交互 shell、stdout 是终端、灵动岛在跑时启用，其余场景原样透传
    if not status is-interactive; or not test -t 1; or not type -q qs; or not pgrep -x qs >/dev/null
        command curl $argv
        return
    end

    # 只在真正的落盘下载（-o / -O）时启用；结果进管道的用法（curl url | jq）不掺和
    if not contains -e -- -o -O --output --remote-name $argv
        and not string match -rq -- '^--output=' $argv
        command curl $argv
        return
    end
    # 静默模式（-s / -sS / --silent）下 curl 不出进度条，别硬加 --progress-bar 打破预期
    if string match -rq -- '^-s' $argv; or contains -e -- --silent $argv
        command curl $argv
        return
    end

    # 标签用下载文件名，取不到就显示「下载」
    set -l label 下载
    if set -l i (contains -i -- -o $argv)
        set label $argv[(math $i + 1)]
    else if set -l m (string match -r -- '^--output=(.+)$' $argv)
        set label $m[2]
    end
    qs -c end4-pC ipc call island task_begin "$label" download 2>/dev/null

    # --progress-bar 把进度打到 stderr（\r 刷新）：透传回终端的同时解析百分比。
    # 重定向顺序：stderr 进管道供解析，stdout（数据本体）直通终端。
    command curl --progress-bar $argv 2>&1 >/dev/tty | tee /dev/tty | tr '\r' '\n' | _island_dl_progress
    set -l st $pipestatus[1]
    qs -c end4-pC ipc call island task_end download 2>/dev/null
    return $st
end
