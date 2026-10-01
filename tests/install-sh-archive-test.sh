#!/usr/bin/env bash
# cmd_archive 端到端测试：验证一次成型打包 + 拒绝存档的返回码语义
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
export HOME="$ROOT/home"
mkdir -p "$HOME/.config/kitty" "$HOME/.config/fish"
echo "kitty-cfg" > "$HOME/.config/kitty/kitty.conf"
echo "fish-cfg"  > "$HOME/.config/fish/config.fish"

# 库方式加载（install.sh 末尾有 BASH_SOURCE 守卫，source 不会跑 main）
# ⚠ 但 install.sh 顶层的 `set -euo pipefail` 会带进调用方 shell —— 被测函数
#   返回非 0（比如 cmd_archive 的用户取消返回 2）时会被 -e 杀掉。
#   测试台必须自己关掉 -e，只保留 -u。
# shellcheck disable=SC1091
source "$REPO/install.sh"
set +e

pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n        %s\n' "$1" "$2"; fail=$((fail+1)); }

echo "── 1. 正常打包"
out="$ROOT/out.tar.gz"
printf 'y\n' | cmd_archive -o "$out" >/dev/null 2>&1
rc=$?
[[ $rc -eq 0 ]] && ok "退出码 0" || bad "退出码" "实际 $rc"
[[ -f $out ]] && ok "归档已生成" || bad "归档未生成" "$out"

listing="$(tar -tzf "$out" 2>/dev/null)"
printf '%s\n' "$listing" | grep -qx "MANIFEST.txt" \
    && ok "包内有 MANIFEST.txt（在根目录）" || bad "包内无 MANIFEST.txt" "$listing"
printf '%s\n' "$listing" | grep -qx ".config/kitty/kitty.conf" \
    && ok "包内有 .config/kitty/kitty.conf" || bad "包内缺配置" "$listing"
printf '%s\n' "$listing" | grep -qx ".config/fish/config.fish" \
    && ok "包内有 .config/fish/config.fish" || bad "包内缺配置" "$listing"

tar -xzOf "$out" MANIFEST.txt 2>/dev/null | grep -q "sijin-xb's dotfiles archive MANIFEST" \
    && ok "MANIFEST 内容正确" || bad "MANIFEST 内容不对" ""

echo "── 2. 不留临时文件（旧实现会往 \$HOME 写 .ARCHIVE-MANIFEST.tmp）"
[[ -e "$HOME/.ARCHIVE-MANIFEST.tmp" ]] \
    && bad "残留了 .ARCHIVE-MANIFEST.tmp" "$HOME" || ok "没有残留临时文件"
find "$HOME" -maxdepth 1 -name '.ARCHIVE-MANIFEST*' | grep -q . \
    && bad "找到了残留" "$(find "$HOME" -maxdepth 1 -name '.ARCHIVE-MANIFEST*')" \
    || ok "家目录顶层干净"

echo "── 3. 拒绝打包 → 返回 2（不是 0）"
out2="$ROOT/reject.tar.gz"
printf 'n\n' | cmd_archive -o "$out2" >/dev/null 2>&1
rc2=$?
[[ $rc2 -eq 2 ]] && ok "返回码为 2（用户取消）" || bad "返回码" "期望 2，实际 $rc2"
[[ -f $out2 ]] && bad "拒绝后仍生成了归档" "$out2" || ok "拒绝后未生成归档"

echo "── 4. 没有可打包路径 → 返回非 0"
empty="$ROOT/empty-home"
mkdir -p "$empty"
out3="$ROOT/empty.tar.gz"
( export HOME="$empty"; printf 'y\n' | cmd_archive -o "$out3" >/dev/null 2>&1; exit $? )
rc3=$?
[[ $rc3 -ne 0 ]] && ok "返回非 0（$rc3）" || bad "返回码" "期望非 0"

echo
printf '结果: %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
