# ============================================================
# 子命令 deps：打印当前会话需要的依赖包（只读）
# ============================================================

# 依赖来源与 install 完全同一批 *_pkgs() 函数，所以列表不会和实际安装漂移。
# 顺序也照抄 cmd_install：fixed → 合成器 → shell → 公共 → 字体。
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

# 打印一组包：<标题> <包...>；only_missing=1 时只留 pacman -Q 查不到的。
deps_emit_group() {
    local title="$1"; shift
    local only_missing="$1"; shift
    local p
    local -a out=()
    for p in "$@"; do
        [[ -z "$p" ]] && continue
        # in_sync_db 问的是「官方仓库有没有这个包」，不是「装没装」；
        # 这里要的是装没装，所以直接用 pacman -Q。
        if (( only_missing )) && pacman -Q "$p" >/dev/null 2>&1; then
            continue
        fi
        out+=("$p")
    done
    (( ${#out[@]} == 0 )) && return 0
    printf '%s（%d）\n' "$title" "${#out[@]}"
    printf '  %s\n' "${out[@]}"
    echo
}

cmd_deps() {
    local only_missing=0 want=all
    while (($#)); do
        case "$1" in
            -h|--help)
                cat <<EOF
用法：$0 deps [选项]

列出当前会话需要的依赖包，按来源分组。只读，不装任何东西。

选项：
  --missing    只列**当前未安装**的包（用 pacman -Q 查）
  --pacman     只列官方仓库包
  --aur        只列 AUR 包
  --fonts      只列字体链（含 FONTS=0 时会跳过的那些）
  -h, --help   显示本帮助

装缺失项：$0 update --with-packages（只补不卸）或 $0 install
EOF
                return 0 ;;
            --missing) only_missing=1; shift ;;
            --pacman)  want=pacman; shift ;;
            --aur)     want=aur; shift ;;
            --fonts)   want=fonts; shift ;;
            *) warn "deps: 未知选项 $1"; return 2 ;;
        esac
    done

    status_resolve_session
    echo "会话: $(status_session_label)"
    (( only_missing )) && echo "过滤: 只看未安装"
    echo

    local -a l_pacman=() l_aur=() l_fpacman=() l_faur=()
    if [[ "$want" == "all" || "$want" == "pacman" ]]; then
        mapfile -t l_pacman < <(deps_collect pacman)
    fi
    if [[ "$want" == "all" || "$want" == "aur" ]]; then
        mapfile -t l_aur < <(deps_collect aur)
    fi
    if [[ "$want" == "all" || "$want" == "fonts" ]]; then
        mapfile -t l_fpacman < <(deps_collect fonts-pacman)
        mapfile -t l_faur    < <(deps_collect fonts-aur)
    fi

    deps_emit_group "官方仓库（pacman）" "$only_missing" "${l_pacman[@]}"
    deps_emit_group "AUR" "$only_missing" "${l_aur[@]}"
    deps_emit_group "字体（pacman）" "$only_missing" "${l_fpacman[@]}"
    deps_emit_group "字体（AUR）" "$only_missing" "${l_faur[@]}"

    if (( only_missing )); then
        echo "以上为未安装项。补齐：$0 update --with-packages"
    else
        echo "以上为完整清单。只看缺口加 --missing。"
    fi
    return 0
}
