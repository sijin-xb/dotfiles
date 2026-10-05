# ============================================================
# 子命令 doctor：环境体检（只读）
# ============================================================
# 定位：装之前/装之后想知道「这台机器到底缺什么」。只报告，不改任何东西 ——
# 补救命令打印出来由你决定跑不跑。

DOCTOR_WARN=0
DOCTOR_FAIL=0

doctor_ok()   { printf '  %s✓%s %s\n' "$C_GREEN"  "$C_RESET" "$*"; }
doctor_warn() { printf '  %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; DOCTOR_WARN=$((DOCTOR_WARN + 1)); }
doctor_bad()  { printf '  %s✗%s %s\n' "$C_RED"    "$C_RESET" "$*"; DOCTOR_FAIL=$((DOCTOR_FAIL + 1)); }
doctor_head() { printf '\n%s\n' "$*"; }

cmd_doctor() {
    case "${1:-}" in
        -h|--help)
            cat <<EOF
用法：$0 doctor

体检当前环境并打印缺口，只读、不改任何东西。检查项：
  系统（发行版 / 是否 root）· 工具链（git、pacman、python3…）
  当前会话的合成器与 quickshell · 依赖包缺口 · QML 模块自检 · 备份目录可写
EOF
            return 0 ;;
        "") ;;
        *) warn "doctor 不接受参数：$1"; return 2 ;;
    esac

    doctor_head "── 系统 ──"
    if [[ -f /etc/arch-release ]]; then
        doctor_ok "Arch 系发行版"
    else
        doctor_bad "非 Arch 系（缺 /etc/arch-release）—— 本脚本的装包逻辑写死了 pacman"
    fi
    if [[ "$(id -u)" -eq 0 ]]; then
        doctor_bad "以 root 运行 —— 请用普通用户，脚本会拒绝 root"
    else
        doctor_ok "普通用户（uid $(id -u)）"
    fi
    doctor_ok "bash ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"

    doctor_head "── 工具链 ──"
    local c
    for c in git sudo pacman python3 tar curl; do
        if have "$c"; then doctor_ok "$c"; else doctor_bad "$c 缺失"; fi
    done
    local helper; helper="$(aur_helper)"
    if [[ -n "$helper" ]]; then
        doctor_ok "AUR helper: $helper"
    else
        doctor_warn "没有 paru / yay —— 装 AUR 包时会先自动装 yay"
    fi

    status_resolve_session
    doctor_head "── 会话（$(status_session_label)）──"
    local cfg=""
    case "$COMPOSITOR" in
        niri)
            have niri && doctor_ok "niri 可用" || doctor_bad "niri 缺失"
            cfg="$HOME/.config/niri/config.kdl" ;;
        *)
            have Hyprland && doctor_ok "Hyprland 可用" || doctor_bad "Hyprland 缺失"
            cfg="$HOME/.config/hypr/hyprland.lua" ;;
    esac
    [[ -n "$cfg" ]] && { [[ -e "$cfg" ]] && doctor_ok "配置入口 ${cfg/#$HOME/\~}" || doctor_warn "配置入口不存在：${cfg/#$HOME/\~}（还没装？）"; }
    if [[ "$QS_SHELL" == "dms" ]]; then
        have dms && doctor_ok "dms 可用" || doctor_bad "dms 缺失"
    else
        have qs && doctor_ok "quickshell（qs）可用" || doctor_bad "quickshell 缺失"
        [[ -e "$HOME/.config/quickshell/end4-PC/shell.qml" || -e "$HOME/.config/quickshell/caelestia/shell.qml" ]] \
            && doctor_ok "shell 差异层已部署" \
            || doctor_warn "shell 差异层未部署（$QS_SHELL）"
    fi

    doctor_head "── 依赖包缺口 ──"
    local -a missing=()
    local p
    while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        have pacman || break
        pacman -Q "$p" >/dev/null 2>&1 || missing+=("$p")
    done < <(deps_collect pacman; deps_collect aur)
    if (( ${#missing[@]} == 0 )); then
        doctor_ok "本会话依赖齐全"
    else
        doctor_warn "${#missing[@]} 个包未安装：${missing[*]}"
        printf '     补齐：%s update --with-packages（只补不卸）\n' "$0"
    fi

    doctor_head "── QML 模块自检 ──"
    if [[ "$QS_SHELL" == "dms" ]]; then
        doctor_ok "dms 会话不需要 QML 模块自检"
    elif [[ ! -f "$SRC/check-qml-deps.py" ]]; then
        doctor_warn "check-qml-deps.py 不在仓库里，跳过"
    elif ! have python3; then
        doctor_warn "没有 python3，跳过（QML 自检是 Python 脚本）"
    else
        local report
        if report="$(python3 "$SRC/check-qml-deps.py" --quiet 2>&1)"; then
            doctor_ok "QML 模块齐全"
        else
            doctor_bad "QML 模块有缺口："
            printf '%s\n' "$report" | sed 's/^/      /'
        fi
    fi

    doctor_head "── 备份目录 ──"
    if [[ -w "$BACKUP_ROOT" ]]; then
        doctor_ok "$BACKUP_ROOT 可写"
    elif [[ -w "$(dirname "$BACKUP_ROOT")" ]]; then
        doctor_ok "$BACKUP_ROOT 尚不存在，父目录可写"
    else
        doctor_bad "$BACKUP_ROOT 不可写 —— snapshot / rollback 会失败"
    fi

    doctor_head "── 结论 ──"
    if (( DOCTOR_FAIL == 0 && DOCTOR_WARN == 0 )); then
        printf '  一切正常。\n'
    else
        printf '  %d 项需要注意，%d 项必须处理。\n' "$DOCTOR_WARN" "$DOCTOR_FAIL"
    fi
    (( DOCTOR_FAIL == 0 )) || return 1
    return 0
}
