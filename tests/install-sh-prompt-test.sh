#!/usr/bin/env bash
# confirm / read_answer 的「非交互不挂死」行为测试
#
# 背景：以前 confirm 与三处菜单是裸 `read`。stdin 若是**打开着但一直不给
# 数据**的管道，read 会永久阻塞 —— 实测 `bash tests/install-sh-cli-test.sh`
# 卡死 10 分钟、零输出（read 在无 tty 时并不会自动 EOF，这点常被误解）。
#
# 三种 stdin 形态都要钉住：真终端（等用户）/ EOF（立刻否）/ 沉默管道（超时否）。
#
# ⚠ 三个测试写法上的坑（都踩过，改之前先看）：
#   1) 不能用 `$( (sleep N) | cmd )` 测耗时 —— $( ) 要等**整个管道**结束，
#      沉默 writer 会把测量拖满 N 秒，看起来像「兜底没生效」。用 FIFO 起
#      后台 writer，只给 reader 计时。
#   2) FIFO writer 必须用 `exec 3<> "$fifo"`（读写打开，不阻塞）。写成
#      `exec > "$fifo"` 会**阻塞在 open**（此时还没有读者），而且后台子 shell
#      仍握着外层 `$( )` 的捕获管道 —— $( ) 永远等不到 EOF，直接死锁。
#      同理别用 `wp="$(start_writer ...)"` 取 pid，用全局变量。
#   3) say/warn 写的是 **stdout**（只有 die 走 stderr），断言提示文本要抓 stdout。
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO
pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n        %s\n' "$1" "$2"; fail=$((fail+1)); }

now_ms() { date +%s%3N; }

# 在子进程里 source install.sh 后调用 confirm，只回显退出码
probe_confirm() {
    bash -c '
        source "$REPO/install.sh" 2>/dev/null
        set +e
        confirm "测试确认？" >/dev/null 2>&1
        printf "%s" "$?"
    '
}

# 起一个「打开写端但一直不写」的后台 writer。结果放在全局 WRITER_PID。
WRITER_PID=""
SILENT_FIFOS=()
start_silent_writer() {
    local fifo="$1"
    mkfifo "$fifo"
    SILENT_FIFOS+=("$fifo")
    ( exec 3<> "$fifo"; sleep 30 ) &
    WRITER_PID=$!
}
stop_silent_writers() {
    [[ -n $WRITER_PID ]] && kill "$WRITER_PID" 2>/dev/null
    local f
    for f in "${SILENT_FIFOS[@]:-}"; do [[ -n $f ]] && rm -f "$f"; done
    WRITER_PID=""; SILENT_FIFOS=()
}

echo "── 1. 管道里给了 y → 视为同意（自动化不被破坏）"
got="$(printf 'y\n' | probe_confirm)"
[[ "$got" == "0" ]] && ok "echo y | confirm → 0" || bad "管道 y 未被采纳" "rc=$got"

echo "── 2. stdin 是 /dev/null → EOF 立即按「否」，不等待"
t0=$(now_ms); got="$(probe_confirm </dev/null)"; t1=$(now_ms)
[[ "$got" == "1" ]] && ok "EOF → 1（默认否）" || bad "EOF 未按否处理" "rc=$got"
(( t1 - t0 <= 1500 )) && ok "EOF 不等待（$((t1-t0))ms）" \
    || bad "EOF 竟然等了 $((t1-t0))ms" ""

echo "── 3. stdin 是沉默管道（打开但不给数据）→ 超时兜底，绝不永久挂"
fifo="$(mktemp -u /tmp/prompt-test.XXXXXX)"
start_silent_writer "$fifo"
t0=$(now_ms); got="$(probe_confirm < "$fifo")"; t1=$(now_ms)
stop_silent_writers
el=$((t1 - t0))
[[ "$got" == "1" ]] && ok "沉默管道 → 1（默认否）" || bad "沉默管道未按否处理" "rc=$got"
(( el >= 2000 && el <= 6000 )) && ok "沉默管道 ${el}ms 内返回（兜底生效，未挂死）" \
    || bad "沉默管道耗时 ${el}ms，兜底未按预期（期望 2~6s）" ""

echo "── 4. 超时有明确提示"
fifo2="$(mktemp -u /tmp/prompt-test.XXXXXX)"
start_silent_writer "$fifo2"
# 注意：这里**不能**复用 probe_confirm —— 它把 confirm 的 stdout 丢进 /dev/null，
# 而 warn 走的就是 stdout，提示会被吞掉。保留 stdout、只丢 stderr。
out="$(bash -c '
    source "$REPO/install.sh" 2>/dev/null
    set +e
    confirm "测试确认？" 2>/dev/null
' < "$fifo2" )"
stop_silent_writers
printf '%s' "$out" | grep -q "非交互" \
    && ok "超时提示含「非交互」" \
    || bad "超时无提示（say/warn 走 stdout，别抓 stderr）" "out=$(printf '%s' "$out" | tr '\n' ' ')"

echo "── 5. 非交互时菜单走默认值，不卡住"
fifo3="$(mktemp -u /tmp/prompt-test.XXXXXX)"
start_silent_writer "$fifo3"
t0=$(now_ms)
out="$(bash -c '
    source "$REPO/install.sh" 2>/dev/null
    set +e
    SESSION=""
    choose_session >/dev/null 2>&1
    printf "%s" "$SESSION"
' < "$fifo3" )"
t1=$(now_ms)
stop_silent_writers
[[ -n "$out" ]] && ok "choose_session 非交互有默认值（SESSION=$out）" \
    || bad "choose_session 非交互没给出 SESSION" ""
(( t1 - t0 <= 6000 )) && ok "菜单不永久等待（$((t1-t0))ms）" || bad "菜单挂了 $((t1-t0))ms" ""

echo "── 6. 真终端（pty）下 confirm 仍正常读到输入"
if command -v script >/dev/null 2>&1; then
    tmp="$(mktemp /tmp/prompt-pty.XXXXXX.sh)"
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf 'source "%s/install.sh" 2>/dev/null\n' "$REPO"
        printf '%s\n' 'set +e' 'confirm "测试确认？" >/dev/null 2>&1' 'printf "rc=%s\n" "$?"' 'exit 0'
    } > "$tmp"
    got="$(printf 'y\n' | script -qec "bash '$tmp'" /dev/null 2>&1 \
            | tr -d '\r' | grep -o 'rc=[0-9]' | tail -1)"
    rm -f "$tmp"
    [[ "$got" == "rc=0" ]] && ok "pty 下 confirm 读到 y（$got）" || bad "pty 下 confirm 异常" "got='$got'"
else
    printf '  SKIP  script(1) 不可用，跳过 pty 检查\n'
fi

echo
printf '结果: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
