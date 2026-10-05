# ============================================================
# 删除范围与跳过矩阵（原 §2 尾部）
# 只服务删除类操作：卸载时不能连带删掉机器上另一套会话的配置。
# ============================================================
# 按 $COMPOSITOR / $QS_SHELL 过滤 SNAP_PATHS，输出到 stdout（一行一个）。
#
# 只用于**删除类**操作（uninstall / archive --delete）：卸载时不该把机器上
# 另一套合成器、或另一套桌面 shell 的既有配置一起删掉。
# 快照（snapshot）和打包（archive）**不用**它——那两步是备份，多带无妨，
# 而且 pre-install 快照发生在 choose_session 之前，过滤它反而会让
# rollback 少恢复东西。
active_snap_paths() {
    local p
    for p in "${SNAP_PATHS[@]}"; do
        if [[ "${INSTALL_BOTH_COMPOSITORS:-0}" == "1" ]]; then
            printf '%s\n' "$p"
            continue
        fi
        if [[ $p == .config/niri ]]; then
            if [[ "$COMPOSITOR" == "niri" ]]; then printf '%s\n' "$p"; fi
        elif [[ $p == .config/hypr ]]; then
            if [[ "$COMPOSITOR" != "niri" ]]; then printf '%s\n' "$p"; fi
        # ⚠ quickshell 的两个 shell 也要分开：end4-PC 与 caelestia 在
        #   ~/.config/quickshell/ 下各占一个目录，卸载其中一套不该顺手删掉
        #   另一套（以前这里只按合成器过滤，两套 shell 都被算进删除范围）。
        #   QS_SHELL 为空 = 没指定，保持旧行为（两个都算）。
        #   值 `both` = 用户在 uninstall_shell_scope 里明确选了"两套都删"。
        elif [[ $p == .config/quickshell/end4-pC ]]; then
            if [[ -z ${QS_SHELL:-} || "$QS_SHELL" == "end4-pC" || "$QS_SHELL" == "both" ]]; then
                printf '%s\n' "$p"
            fi
        elif [[ $p == .config/quickshell/caelestia ]]; then
            if [[ -z ${QS_SHELL:-} || "$QS_SHELL" == "caelestia" || "$QS_SHELL" == "both" ]]; then
                printf '%s\n' "$p"
            fi
        else
            printf '%s\n' "$p"
        fi
    done
}

# 卸载时的删除范围。COMPOSITOR 已设定（例如本次跑过 install，或用了
# COMPOSITOR=niri ./install.sh uninstall）就直接用；用户已在 TUI 卸载页选过
# 「两套都删」（INSTALL_BOTH_COMPOSITORS=1）时同样视为已定，否则交互询问。
#
# ⚠ 第三条早退条件不能省：TUI 的 detail_uninstall 渲染时会先问一次范围，
#   选「两套都删」只会置 INSTALL_BOTH_COMPOSITORS=1（COMPOSITOR 保持为空），
#   随后 cmd_uninstall 会再调一次本函数 —— 没有这条就会对同一个问题问两遍。
uninstall_compositor_scope() {
    if [[ -n ${COMPOSITOR:-} || "${INSTALL_BOTH_COMPOSITORS:-0}" == "1" ]]; then
        return 0
    fi
    echo
    echo "  要删除哪套合成器的配置？"
    echo "    1) 两套都删    ~/.config/hypr + ~/.config/niri"
    echo "    2) 只删 Hyprland  ~/.config/hypr"
    echo "    3) 只删 niri      ~/.config/niri"
    local ans=""
    printf '  请输入 1/2/3 [默认 1]: '
    read_answer ans
    case "$ans" in
        2) COMPOSITOR=hyprland ;;
        3) COMPOSITOR=niri ;;
        *) INSTALL_BOTH_COMPOSITORS=1 ;;
    esac
}

# 删除类操作的 shell 范围。与 uninstall_compositor_scope 同一套思路：
# QS_SHELL 已设定（环境变量预设，或本次 install 派生过）就直接用；否则询问。
#
# ⚠ 必要性：~/.config/quickshell/end4-pC 与 ~/.config/quickshell/caelestia
#   是两个独立目录，机器上可能同时存在（例如以前试过 caelestia 又换回
#   end4-PC）。不做这个区分的话，卸载 end4-PC 会把 caelestia 的配置一起删掉。
#   选 3 时置为字面量 both —— active_snap_paths 认这个值。
uninstall_shell_scope() {
    if [[ -n ${QS_SHELL:-} ]]; then
        return 0
    fi
    echo
    echo "  要删除哪套桌面 shell 的 quickshell 配置？"
    echo "    1) 只删 end4-PC    ~/.config/quickshell/end4-pC"
    echo "    2) 只删 caelestia  ~/.config/quickshell/caelestia"
    echo "    3) 两套都删"
    local ans=""
    printf '  请输入 1/2/3 [默认 1]: '
    read_answer ans
    case "$ans" in
        2) QS_SHELL=caelestia ;;
        3) QS_SHELL=both ;;
        *) QS_SHELL=end4-pC ;;
    esac
    echo "    shell 范围: $QS_SHELL"
}

# 依据 $COMPOSITOR 判断仓库内某个相对路径是否**跳过部署**。
#
# 两套合成器配置都在本仓库里（dot_config/hypr/** 与 dot_config/niri/**）。
# 早期版本在 [5/7] 部署时无差别全部 cp 到 $HOME —— 也就是说选了 Hyprland 的人
# 也会被覆盖掉 ~/.config/niri，选择 niri 的人同理被覆盖 ~/.config/hypr。
# 现在默认只部署选中的那套，另一套完全不动（连备份都不做，因为根本不碰）。
#
# 想两套都部署（例如机器上两个合成器都要用）：
#     INSTALL_BOTH_COMPOSITORS=1 ./install.sh install
#
# 返回 0 = 跳过，1 = 正常部署
skip_by_compositor() {
    if [[ "${INSTALL_BOTH_COMPOSITORS:-0}" == "1" ]]; then
        return 1
    fi
    local rel="$1"
    if [[ "$COMPOSITOR" == "niri" ]]; then
        if [[ $rel == dot_config/hypr/* ]]; then return 0; fi
    else
        if [[ $rel == dot_config/niri/* ]]; then return 0; fi
    fi
    return 1
}

# 依据 $QS_SHELL 判断仓库内某个相对路径是否**跳过部署**。
#
# 三个 shell 的差异层在仓库里的位置不同：
#   end4-pC   → dot_config/quickshell/end4-pC/**（本仓库跟踪的差异层）
#   caelestia → shell 本体由 [4b/7] clone 到 ~/.config/quickshell/caelestia；
#               仓库里的 dot_config/quickshell/caelestia/ 只是它的覆盖层
#   dms       → dot_config/DankMaterialShell/**（插件）
# 选了 caelestia 就不该把 end4-pC 的差异层覆盖上去（反之亦然）；DMS 插件只在选
# dms 时部署；illogical-impulse 是 end4-PC 的配置目录，非 end4-pC 时也跳过。
#
# 返回 0 = 跳过，1 = 正常部署
skip_by_shell() {
    local rel="$1"
    case "$QS_SHELL" in
        caelestia)
            # 不部署 end4-PC 差异层与 DMS 插件；caelestia 自己的定制层（若仓库里有）允许
            [[ $rel == dot_config/quickshell/end4-pC/* ]] && return 0
            [[ $rel == dot_config/DankMaterialShell/* ]] && return 0
            [[ $rel == dot_config/illogical-impulse/* ]] && return 0
            ;;
        dms)
            [[ $rel == dot_config/quickshell/* ]] && return 0
            [[ $rel == dot_config/illogical-impulse/* ]] && return 0
            ;;
        end4-pC)
            [[ $rel == dot_config/quickshell/caelestia/* ]] && return 0
            [[ $rel == dot_config/DankMaterialShell/* ]] && return 0
            ;;
    esac
    return 1
}

