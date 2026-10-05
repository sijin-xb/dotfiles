# ============================================================
# 子命令 theme：主题取值总览与一致性检查（只读）
# ============================================================
# 为什么要这个：图标主题散在 9 个互不知情的 sink 里（gsettings、GTK2/3/4、
# Qt5/Qt6、fuzzel、xsettingsd、rofi）。matugen 每次换壁纸会把它们整批改写，
# 手动改主题或某个程序自己写回时又只改其中一处 —— 结果就是「文件管理器换了、
# fuzzel 没换」。这一条命令把全部取值摊开并标出不一致。

# 读一个 ini 风格文件里的键；文件不存在/键缺失时给明确占位，不打印空行。
theme_read_kv() { # <file> <sed-表达式> [默认占位]
    local file="$1" expr="$2" fallback="${3:-未设置}"
    if [[ ! -f "$file" ]]; then
        printf '%s' "无此文件"
        return 0
    fi
    local v; v="$(sed -n "$expr" "$file" 2>/dev/null | head -1)"
    if [[ -n "$v" ]]; then printf '%s' "$v"; else printf '%s' "$fallback"; fi
}

theme_read_gsettings() { # <schema> <key>
    if have gsettings; then
        gsettings get "$1" "$2" 2>/dev/null | tr -d "'" || printf '读取失败'
    else
        printf '无 gsettings'
    fi
}

# 汇总一组的取值并判定一致性。入参：值数组（已去空）；出参：打印结论行。
theme_consistency() {
    local -a vals=("$@")
    local -a uniq=()
    local v
    for v in "${vals[@]}"; do
        [[ -z "$v" || "$v" == "无此文件" || "$v" == "未设置" ]] && continue
        local seen=0 u
        for u in "${uniq[@]}"; do [[ "$u" == "$v" ]] && seen=1; done
        (( seen )) || uniq+=("$v")
    done
    if (( ${#uniq[@]} == 0 )); then
        printf '%s没有任何一处设置了主题%s\n' "$C_YELLOW" "$C_RESET"
        return 1
    elif (( ${#uniq[@]} == 1 )); then
        printf '%s一致%s：%s\n' "$C_GREEN" "$C_RESET" "${uniq[0]}"
        return 0
    else
        printf '%s不一致%s：%s\n' "$C_YELLOW" "$C_RESET" "$(printf '%s / ' "${uniq[@]}" | sed 's/ \/ $//')"
        return 1
    fi
}

cmd_theme() {
    case "${1:-}" in
        -h|--help)
            cat <<EOF
用法：$0 theme

打印图标 / 光标 / GTK 主题在各个 sink 里的当前取值，并标出一致性。

为什么要看这个：图标主题散在 gsettings、GTK2/3/4、Qt5/Qt6、fuzzel、
xsettingsd、rofi 共 9 处；matugen 换壁纸时会整批重写，手动改或某个程序
自己写回时又只改一处 —— 这里能把「哪一处没跟上」直接指出来。

只读，不改任何文件。
EOF
            return 0 ;;
        "") ;;
        *) warn "theme 不接受参数：$1"; return 2 ;;
    esac

    local -a icon_vals=()

    echo "── 图标主题 ──"
    local v
    v="$(theme_read_gsettings org.gnome.desktop.interface icon-theme)"
    printf '  %-22s %s\n' "gsettings" "$v"; icon_vals+=("$v")

    v="$(theme_read_kv "$HOME/.config/gtk-3.0/settings.ini" 's/^gtk-icon-theme-name=//p')"
    printf '  %-22s %s\n' "gtk-3.0" "$v"; icon_vals+=("$v")

    v="$(theme_read_kv "$HOME/.config/gtk-4.0/settings.ini" 's/^gtk-icon-theme-name=//p')"
    printf '  %-22s %s\n' "gtk-4.0" "$v"; icon_vals+=("$v")

    v="$(theme_read_kv "$HOME/.gtkrc-2.0" 's/^gtk-icon-theme-name="\?\([^"]*\)"\?$/\1/p')"
    printf '  %-22s %s\n' "gtk-2.0" "$v"; icon_vals+=("$v")

    v="$(theme_read_kv "$HOME/.config/qt5ct/qt5ct.conf" 's/^icon_theme=//p')"
    printf '  %-22s %s\n' "qt5ct" "$v"; icon_vals+=("$v")

    v="$(theme_read_kv "$HOME/.config/qt6ct/qt6ct.conf" 's/^icon_theme=//p')"
    printf '  %-22s %s\n' "qt6ct" "$v"; icon_vals+=("$v")

    v="$(theme_read_kv "$HOME/.config/fuzzel/fuzzel.ini" 's/^icon-theme=//p')"
    printf '  %-22s %s\n' "fuzzel" "$v"; icon_vals+=("$v")

    v="$(theme_read_kv "$HOME/.config/xsettingsd/xsettingsd.conf" 's/^Net\/IconThemeName[[:space:]]*"\([^"]*\)".*/\1/p')"
    printf '  %-22s %s\n' "xsettingsd" "$v"; icon_vals+=("$v")

    v="$(theme_read_kv "$HOME/.config/rofi/themes/icons.rasi" 's/.*icon-theme:[[:space:]]*"\([^"]*\)".*/\1/p')"
    printf '  %-22s %s\n' "rofi" "$v"; icon_vals+=("$v")

    printf '  %-22s ' "一致性"
    theme_consistency "${icon_vals[@]}" || true

    echo
    echo "── 光标主题 ──"
    local -a cur_vals=()
    v="$(theme_read_gsettings org.gnome.desktop.interface cursor-theme)"
    printf '  %-22s %s\n' "gsettings" "$v"; cur_vals+=("$v")
    v="$(theme_read_kv "$HOME/.config/gtk-3.0/settings.ini" 's/^gtk-cursor-theme-name=//p')"
    printf '  %-22s %s\n' "gtk-3.0" "$v"; cur_vals+=("$v")
    v="$(theme_read_kv "$HOME/.config/gtk-4.0/settings.ini" 's/^gtk-cursor-theme-name=//p')"
    printf '  %-22s %s\n' "gtk-4.0" "$v"; cur_vals+=("$v")
    v="$(theme_read_kv "$HOME/.icons/default/index.theme" 's/^Inherits=//p')"
    printf '  %-22s %s\n' "~/.icons/default" "$v"; cur_vals+=("$v")
    v="$(theme_read_kv "$HOME/.local/share/icons/default/index.theme" 's/^Inherits=//p')"
    printf '  %-22s %s\n' "icons/default" "$v"; cur_vals+=("$v")
    printf '  %-22s ' "一致性"
    theme_consistency "${cur_vals[@]}" || true

    echo
    echo "── GTK 主题 ──"
    printf '  %-22s %s\n' "gsettings" "$(theme_read_gsettings org.gnome.desktop.interface gtk-theme)"
    printf '  %-22s %s\n' "gtk-3.0" "$(theme_read_kv "$HOME/.config/gtk-3.0/settings.ini" 's/^gtk-theme-name=//p')"
    printf '  %-22s %s\n' "gtk-4.0" "$(theme_read_kv "$HOME/.config/gtk-4.0/settings.ini" 's/^gtk-theme-name=//p')"

    echo
    echo "提示：图标主题由 matugen 的 [templates.gtk-folder] 在换壁纸时整批重写；"
    echo "      手动改过某一处的话，下次换壁纸会被它拉回统一值。"
    return 0
}
