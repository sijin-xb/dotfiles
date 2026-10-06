# ============================================================
# 子命令 deps —— 已迁移到 Python（dotctl/commands/deps.py）
# ============================================================
# cmd_deps 只留一行转发。deps_collect() 留在 bash 侧是**故意的**：它是包
# 列表的唯一来源（install 装包读的也是同一批 *_pkgs()），Python 侧经
# dotctl.bashsrc 调它，而不是再抄一份清单。
# 原先的 deps_emit_group 已删 —— 分组与缩进的排版逻辑现在在 Python 里。

deps_collect() { # <pacman|aur|fonts-pacman|fonts-aur>
    # ⚠ 各 *_pkgs() 的输出格式并不统一：多数一行一个，但 compositor_pkgs /
    #   base_pacman_pkgs 这类把多个包写在同一行（"hyprland xdg-desktop-portal-hyprland"）。
    #   cmd_install 用 `+=($(...))` 靠 word splitting 拆开，这里若不显式拆，
    #   mapfile 会把整行当成一个包名（实测：列表里出现 "aubio libpipewire ..." 一项）。
    {
        case "$1" in
            pacman)
                fixed_pacman_pkgs
                compositor_pkgs
                shell_pacman_pkgs
                base_pacman_pkgs ;;
            aur)
                fixed_aur_pkgs
                compositor_aur_pkgs
                shell_aur_pkgs
                base_aur_pkgs ;;
            fonts-pacman) font_pacman_pkgs ;;
            fonts-aur)    font_aur_pkgs ;;
        esac
    } | tr -s '[:space:]' '\n' | sed '/^$/d'
}

cmd_deps() { dotctl_run deps "$@"; }
