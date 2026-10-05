#!/usr/bin/env bash
# ============================================================
# sijin-xb's dotfiles（Rice 版本: v2.0）—— 安装器引导
# ------------------------------------------------------------
# 这一层只做四件事：定位仓库、判定是否直接执行、按序加载 lib/、分发子命令。
# 真正的逻辑按职责拆在 lib/ 下（字典序即加载序）：
#
#   lib/00-env.sh          常量与路径
#   lib/10-util.sh         颜色 / say·warn·die / 包管理探测 / 临时文件清理
#   lib/20-bootstrap.sh    自举：单文件 curl | bash 时拉仓库
#   lib/30-snapshot.sh     快照读写（install / rollback / restore 共用）
#   lib/40-manifest.sh     部署清单、指纹、增量计划
#   lib/50-session.sh      会话三选一与字体开关
#   lib/60-packages.sh     各会话的包列表
#   lib/65-scope.sh        删除范围与跳过矩阵
#   lib/70-deploy.sh       上游底盘装配与单条目落盘
#   lib/80-cmd-install.sh  子命令 install
#   lib/81-cmd-update.sh   子命令 update
#   lib/82-cmd-state.sh    子命令 rollback / restore / archive / uninstall
#   lib/90-help.sh         --help
#   lib/95-tui.sh          TUI 二级菜单
#   lib/99-main.sh         入口分发
#
# 不依赖 chezmoi，纯 bash 自部署：
#   dot_ 前缀目录  → $HOME 下的隐藏目录（dot_config → ~/.config）
#   executable_ 前缀文件 → 剥前缀 + 恢复执行位
# 覆盖有差异的旧文件前会备份到 ~/.local/state/dotfiles-backup/，重复运行幂等。
#
# 单文件运行（自举）：只把 install.sh 捞下来也能跑 —— 它会 clone 仓库到
# ~/.local/share/dotfiles-src，再用仓库里那份（更新的）脚本重新执行自己：
#
#     curl -fsSL https://raw.githubusercontent.com/sijin-xb/dotfiles/main/install.sh \
#         | bash -s -- update
#
#   · 想换仓库地址：DOTFILES_REPO_URL=... 或改缓存位置 DOTFILES_SRC_DIR=...
#   · 想彻底重置自举缓存：rm -rf ~/.local/share/dotfiles-src
#
# 子命令：install / update / rollback / restore / archive / uninstall，
# 详细用法与全部环境变量见 ./install.sh --help。
# ============================================================
set -euo pipefail

# ── 仓库定位 ────────────────────────────────────────────────
# ⚠ 必须在这一层算：lib/ 下 BASH_SOURCE[0] 指向的是 lib/x.sh，
#   dirname 出来是 lib/ 而不是仓库根。
if [[ -n ${BASH_SOURCE[0]:-} ]]; then
    SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SRC="$(pwd)"
fi

# ── 是否「直接执行」（而非被 tests/ source 进来）─────────────
# 用途有二：决定要不要接管 EXIT/INT/TERM trap（被 source 时不能抢调用方的 ——
# tests/*.sh 自己就 `trap 'rm -rf "$ROOT"' EXIT`），以及决定末尾要不要跑 main。
# ⚠ curl | bash 场景下 BASH_SOURCE[0] 为空、$0 是 bash，两者不等 ——
#   那种情况下必须仍然算「直接执行」，所以空值也算。
INSTALL_SH_IS_MAIN=0
if [[ -z ${BASH_SOURCE[0]:-} || ${BASH_SOURCE[0]} == "${0}" ]]; then
    INSTALL_SH_IS_MAIN=1
fi

# ── 加载模块（lib/NN-name.sh，字典序即依赖序）────────────────
if [[ ! -d "$SRC/lib" ]]; then
    printf '错误: 找不到模块目录 %s/lib —— 仓库不完整，重新 clone 后再试。\n' "$SRC" >&2
    exit 1
fi
for _mod in "$SRC"/lib/*.sh; do
    # shellcheck source=/dev/null
    source "$_mod"
done
unset _mod

# ── 临时文件清理（source 时不抢调用方的 trap）───────────────
if (( INSTALL_SH_IS_MAIN )); then
    trap cleanup_tmpfiles EXIT
    trap 'cleanup_tmpfiles; exit 130' INT
    trap 'cleanup_tmpfiles; exit 143' TERM
fi

# ── 入口 ────────────────────────────────────────────────────
if (( INSTALL_SH_IS_MAIN )); then
    main "$@"
fi
