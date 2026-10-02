#!/usr/bin/env bash
# 批次 3（P2 一致性 + P1-3 dry-run）行为测试
#
# ⚠ 所有对 install.sh 的调用都带 `</dev/null`。不重定向的话测试台会继承
#   调用方的 stdin —— 若是「打开着但不给数据」的管道，install.sh 里的
#   confirm 会永久阻塞（实测卡死 10 分钟）。install.sh 侧现在也有超时兜底，
#   但测试台不该依赖被测算代码的兜底来保证自己不退。
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n        %s\n' "$1" "$2"; fail=$((fail+1)); }

echo "── 1. 非终端输出不含 ANSI 转义（等价于自动 NO_COLOR）"
out="$(bash "$REPO/install.sh" --help 2>&1 </dev/null)"
printf '%s' "$out" | grep -q $'' && bad "help 里有转义码" "" || ok "help 无转义码"
# say/warn 走的是 stderr，但重定向后同样应无颜色
ROOT="$(mktemp -d)"; export HOME="$ROOT/home"; mkdir -p "$HOME"
out="$(bash "$REPO/install.sh" update --dry-run 2>&1 </dev/null)"
printf '%s' "$out" | grep -q $'' && bad "update 输出里有转义码" "" || ok "update 无转义码"

echo "── 2. 三个子命令认 -h 并对多余参数告警"
for sub in rollback restore uninstall; do
    o="$(bash "$REPO/install.sh" "$sub" --help 2>&1 </dev/null)"
    printf '%s' "$o" | grep -q "用法：" && ok "$sub --help 打印帮助" \
        || bad "$sub --help 没打印帮助" "$(printf '%s' "$o" | head -1)"
    o="$(bash "$REPO/install.sh" "$sub" --bogus 2>&1 </dev/null)"
    printf '%s' "$o" | grep -q "不接受参数" && ok "$sub 对多余参数告警" \
        || bad "$sub 静默忽略参数" "$(printf '%s' "$o" | head -1)"
done

echo "── 3. --dry-run 不创建备份目录"
ROOT2="$(mktemp -d)"
( export HOME="$ROOT2/home"; mkdir -p "$HOME"
  bash "$REPO/install.sh" update --dry-run >/dev/null 2>&1 </dev/null )
[[ -e "$ROOT2/home/.local/state/dotfiles-backup" ]] \
    && bad "dry-run 建了 dotfiles-backup" "$ROOT2" \
    || ok "dry-run 未创建 dotfiles-backup"
# 对照：非 dry-run 的路径会建（用 rollback 触发，它一定会 ensure_dirs）
( export HOME="$ROOT2/home"; bash "$REPO/install.sh" rollback >/dev/null 2>&1 </dev/null )
[[ -e "$ROOT2/home/.local/state/dotfiles-backup/state" ]] \
    && ok "非 dry-run 会创建备份目录（对照组）" \
    || bad "非 dry-run 没建目录" "$ROOT2"

echo "── 4. write_state 只写一个文件"
( export HOME="$ROOT2/home"
  source "$REPO/install.sh"
  set +e
  mkdir -p "$ROOT2/home/.local/state/dotfiles-backup/state"
  echo /tmp/fake-snap.tar.gz > "$ROOT2/home/snap"
  write_state testkey "$ROOT2/home/snap"
  ls "$ROOT2/home/.local/state/dotfiles-backup/state/" 2>/dev/null )
ls "$ROOT2/home/.local/state/dotfiles-backup/state/" 2>/dev/null | grep -q "withtime" \
    && bad "仍然写了 .withtime" "" || ok "不再写 .withtime"

echo "── 5. draw_line 宽度正确且无乱码"
( export HOME="$ROOT2/home"
  source "$REPO/install.sh"
  set +e
  COLUMNS=40; line="$(draw_line '─')"
  n=$(printf '%s' "$line" | wc -m)
  [[ "$n" == "40" ]] && ok "宽度 = COLUMNS（40）" || bad "宽度不对" "实际 $n"
  printf '%s' "$line" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 \
      && ok "输出是合法 UTF-8（tr 的字节替换问题已避免）" || bad "非法 UTF-8" "" )

rm -rf "$ROOT" "$ROOT2"
echo
printf '结果: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
