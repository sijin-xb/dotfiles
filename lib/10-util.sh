# ============================================================
# 输出与工具（原 §1）
# 颜色开关、say/warn/die、包管理探测、临时文件登记与清理。
# ============================================================
# 颜色。设了 NO_COLOR（https://no-color.org）或 stdout 不是终端时全部关掉 ——
# `./install.sh update --dry-run > plan.txt` 以前会把 ANSI 码写进文件。
if [[ -n ${NO_COLOR:-} || ! -t 1 ]]; then
    C_GREEN=""; C_YELLOW=""; C_RED=""; C_RESET=""
else
    C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'
    C_RED=$'\033[1;31m';   C_RESET=$'\033[0m'
fi
say()  { printf '%s==>%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s ->%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
die()  { printf '%s错误:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
in_sync_db() { LC_ALL=C pacman -Si "$1" >/dev/null 2>&1; }
aur_helper() { if have paru; then echo paru; elif have yay; then echo yay; else echo ""; fi; }
# ── 临时文件登记 + 统一清理 ──────────────────────────────────────────────
# 全脚本有 8 处 mktemp / mktemp -d（yay clone、quickshell 源码、底盘 clone、
# 归档临时目录……）。以前没有 trap：Ctrl-C 或中途 die 会在 /tmp 留下几十 MB。
#
# ⚠ 不能用「数组登记」的方案：所有调用点都写成 `x="$(mktmp)"`，而命令替换会
#   起一个子 shell —— `TMPFILES+=()` 加进的是**子 shell 的数组**，父 shell
#   永远是空的，清理函数等于没做事（实测踩到）。
#   改成「统一 run 目录」：路径由 $$ 推出，父子 shell 看到的是同一个值
#   （bash 在子 shell 里保留 $$），清理就是一次 rm -rf。
TMPRUN="${TMPDIR:-/tmp}/dotfiles-install.$$"

mktmp()  { mkdir -p "$TMPRUN" 2>/dev/null; mktemp    "$TMPRUN/XXXXXX"; }
mktmpd() { mkdir -p "$TMPRUN" 2>/dev/null; mktemp -d "$TMPRUN/XXXXXX"; }

cleanup_tmpfiles() {
    [[ -n ${TMPRUN:-} ]] && rm -rf -- "$TMPRUN" 2>/dev/null
    return 0
}
