function _island_pkg_progress --description "解析 pacman/yay/paru 输出并上报灵动岛进度（内部函数）"
    # qs 未运行则直接返回，避免 "No running instances" 提示
    if not pgrep -x qs >/dev/null
        return
    end

    # 从 stdin 读取已按行切开的输出（上游已 tr '\r' '\n'），
    # 识别百分比并调用 qs ipc 上报。仅在百分比变化时上报（节流）。
    set -l last -1
    while read -l line
        # 换标签：pacman「downloading 包名」/ yay「Cloning 包名 build files」
        # TaskSource.begin 在任务进行中只换标签不重置进度，不会闪 0%
        if set -l m (string match -r 'downloading (\S+)' -- $line)
            # 去掉行尾省略号（「downloading foo-1.0...」），只留包名
            set -l pkg (string trim --right --chars=. -- $m[2])
            qs -c end4-pC ipc call island task_begin $pkg package &>/dev/null
        else if set -l m (string match -r 'Cloning (\S+) build files' -- $line)
            qs -c end4-pC ipc call island task_begin "$m[2] (AUR)" package &>/dev/null
        else
            # 百分比：pacman 进度条 [######------]  45%，
            # 或 yay 拉取 AUR 的 git 输出 Receiving objects:  45% (12/26)
            set -l pct
            if set -l p (string match -r '\]\s*(\d+)%' -- $line)
                set pct $p[2]
            else if set -l p (string match -r 'Receiving objects:\s+(\d+)%' -- $line)
                set pct $p[2]
            end
            if test -n "$pct"; and test $pct -ne $last
                set last $pct
                qs -c end4-pC ipc call island task_progress $pct package &>/dev/null
            end
        end
    end
end
