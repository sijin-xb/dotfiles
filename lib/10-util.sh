# ============================================================
# 输出与工具：颜色开关、say/warn/die、包管理探测、临时文件清理
# ============================================================
# 设了 NO_COLOR 或 stdout 不是终端时关掉颜色，否则重定向会把 ANSI 码写进文件。
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
# 不能用数组登记临时文件：调用点都写成 x="$(mktmp)"，命令替换起子 shell，
# TMPFILES+=() 加进的是子 shell 的数组，父 shell 永远为空。
# 改用统一 run 目录：路径由 $$ 推出，父子 shell 看到同一个值，清理是一次 rm -rf。
TMPRUN="${TMPDIR:-/tmp}/dotfiles-install.$$"

mktmp()  { mkdir -p "$TMPRUN" 2>/dev/null; mktemp    "$TMPRUN/XXXXXX"; }
mktmpd() { mkdir -p "$TMPRUN" 2>/dev/null; mktemp -d "$TMPRUN/XXXXXX"; }

cleanup_tmpfiles() {
    [[ -n ${TMPRUN:-} ]] && rm -rf -- "$TMPRUN" 2>/dev/null
    return 0
}
