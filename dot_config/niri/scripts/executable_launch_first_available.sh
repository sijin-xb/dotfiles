#!/usr/bin/env bash
# 依次尝试候选命令，启动第一个存在的。
# 用法：launch_first_available.sh "cmd1 --opt" "cmd2" ...
# 注意：被 niri 的 spawn-sh 调用，所以 $HOME 已由 shell 展开。

for candidate in "$@"; do
    bin=${candidate%% *}
    if command -v "$bin" >/dev/null 2>&1; then
        # 故意不加引号：让 "code --foo" 这类带参数的候选能正常分词
        exec $candidate
    fi
done

if command -v notify-send >/dev/null 2>&1; then
    notify-send "启动失败" "以下程序都没装：$*"
fi
exit 1
