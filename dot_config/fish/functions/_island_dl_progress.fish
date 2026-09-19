function _island_dl_progress --description "解析 curl/wget 下载进度并上报灵动岛（内部函数）"
    # qs 未运行则直接返回，避免 "No running instances" 提示
    if not pgrep -x qs >/dev/null
        return
    end

    # 从 stdin 读取已按行切开的进度输出（上游已 tr '\r' '\n'）。
    set -l last -1
    while read -l line
        set -l pct
        # curl --progress-bar：#######################           45.2
        if set -l p (string match -r '^#+\s*(\d+(?:\.\d+)?)\s*$' -- $line)
            set pct (math "floor($p[2])")
        # wget bar 模式：45%[================>     ] 1.2M 10.2M/s eta 12s
        else if set -l p (string match -r '(\d+)%\[' -- $line)
            set pct $p[2]
        end
        if test -n "$pct"; and test $pct -ne $last
            set last $pct
            qs -c end4-pC ipc call island task_progress $pct download &>/dev/null
        end
    end
end
