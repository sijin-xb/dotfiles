#!/usr/bin/env bash
#
# 跑 Caelestia 锁屏移植的独立测试外壳。
#
# 为什么不能直接用 `qs -p <file>`：`-p` 会把**文件所在目录**当成 shell 根，
# 于是 `../upstream` 落在配置目录之外（quickshell 明确拒绝），
# shim 里的 `qs.services` / `qs.modules.common` 也解析不到。
#
# 所以这里在 ~/.config/quickshell/ 下建一个一次性的配置目录，
# 用 symlink 指回本仓库的 modules / services / assets，
# 再把测试外壳放进去。这样 `qs.*` 全部正常解析，而真正的 end4-pC 配置不受影响
# （两个配置目录互相独立，跑测试外壳不会动到你正在用的 shell）。
#
# 用法：
#   scripts/lock/locktest.sh           # 跑（Ctrl+C 退出）
#   scripts/lock/locktest.sh --clean   # 删掉生成的测试配置目录

set -uo pipefail

QUICKSHELL_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
REAL_SHELL="$QUICKSHELL_ROOT/end4-pC"
TEST_NAME="locktest"
TEST_DIR="$QUICKSHELL_ROOT/$TEST_NAME"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" == "--clean" ]]; then
    rm -rf "$TEST_DIR"
    echo "已删除 $TEST_DIR"
    exit 0
fi

if [[ ! -d "$REAL_SHELL" ]]; then
    echo "找不到 quickshell 配置目录: $REAL_SHELL" >&2
    exit 1
fi

# 1) 建测试配置目录，并 symlink 回真实配置的资源
mkdir -p "$TEST_DIR"
for entry in modules services assets panelFamilies GlobalStates.qml; do
    [[ -e "$REAL_SHELL/$entry" ]] || continue
    ln -sfn "$REAL_SHELL/$entry" "$TEST_DIR/$entry"
done

# 2) 放测试外壳（从本脚本同目录拷一份，保持仓库是唯一源）
cp "$SCRIPT_DIR/locktest-shell.qml" "$TEST_DIR/shell.qml"

echo "测试配置已就绪: $TEST_DIR"
echo "启动锁屏测试外壳（Ctrl+C 退出，不影响你正在用的 shell）..."
echo

exec qs -c "$TEST_NAME"
