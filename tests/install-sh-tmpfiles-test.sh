#!/usr/bin/env bash
# 临时文件清理机制测试
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 下面有几处 `bash -c '...'`（单引号，外层不展开变量），靠环境变量把 REPO 传进去
export REPO
pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n        %s\n' "$1" "$2"; fail=$((fail+1)); }

echo "── 1. mktmpd 落在统一 run 目录里，cleanup 能一次清掉"
bash -c '
    source "$REPO/install.sh"
    d1=$(mktmpd); f1=$(mktmp)
    echo "$TMPRUN" > /tmp/mtest/_runpath
    echo "$d1"    > /tmp/mtest/_d1path
    cleanup_tmpfiles
    [[ -e "$d1" ]] && echo "LEAK" || echo "CLEAN"
' > /tmp/mtest/_out 2>&1
grep -q CLEAN /tmp/mtest/_out && ok "run 目录被整体清掉" || bad "未清理" "$(cat /tmp/mtest/_out)"
runpath="$(cat /tmp/mtest/_runpath)"
[[ "$runpath" == /tmp/dotfiles-install.* ]] && ok "run 目录路径形如 /tmp/dotfiles-install.PID" \
    || bad "run 目录路径异常" "$runpath"
[[ -e "$runpath" ]] && bad "run 目录残留" "$runpath" || ok "run 目录已消失"

echo "── 2. 直接执行时注册 trap；source 时不抢调用方的"
out="$(bash -x "$REPO/install.sh" --help 2>&1 | grep -c '^+ trap cleanup_tmpfiles EXIT')"
[[ "$out" == "1" ]] && ok "直接执行注册了 EXIT trap" || bad "未注册" "计数=$out"

out="$(bash -c 'trap "echo KEPT" EXIT; source "$REPO/install.sh"; echo done' 2>&1)"
printf '%s' "$out" | grep -q KEPT && ok "source 未抢调用方 trap" || bad "调用方 trap 被覆盖" "$out"

echo "── 3. SIGINT 端到端：中途打断不留 /tmp 垃圾"
ROOT="$(mktemp -d)"
export HOME="$ROOT/home"
mkdir -p "$HOME/.config/kitty"
echo x > "$HOME/.config/kitty/kitty.conf"
mkfifo "$ROOT/fifo"
# 让 install.sh 停在 cmd_archive 的 confirm 上（stdin 是 fifo，没人写）
sleep 20 > "$ROOT/fifo" &
FEEDER=$!
bash "$REPO/install.sh" archive -o "$ROOT/out.tar.gz" < "$ROOT/fifo" >/dev/null 2>&1 &
PID=$!
sleep 2
alive=0
kill -0 "$PID" 2>/dev/null && alive=1
if (( alive )); then
    before="$(find /tmp -maxdepth 1 -name "dotfiles-install.$PID" 2>/dev/null | wc -l)"
    kill -INT "$PID" 2>/dev/null
    wait "$PID" 2>/dev/null
    sleep 0.5
    after="$(find /tmp -maxdepth 1 -name "dotfiles-install.$PID" 2>/dev/null | wc -l)"
    [[ "$before" == "1" ]] && ok "打断前 run 目录存在" || bad "run 目录没建出来" "before=$before"
    [[ "$after" == "0" ]] && ok "SIGINT 后 run 目录已清理" || bad "SIGINT 后残留" "after=$after"
else
    bad "install.sh 没跑起来" "进程已退出"
fi
kill "$FEEDER" 2>/dev/null
rm -rf "$ROOT"

echo
printf '结果: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
