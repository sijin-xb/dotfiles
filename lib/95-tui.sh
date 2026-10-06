# ============================================================
# TUI 二级菜单（原 §6）
# Welcome / Splash / Main / Detail / Help。
# ============================================================
# ============================================================
# 6. TUI 二级菜单（Welcome / Splash / Main / Detail / Help）
# ============================================================

# TUI 颜色（tput fallback：失败就跳过）
tc() { tput "$@" 2>/dev/null || true; }
TC_BOLD="$(tc bold)"; TC_RESET="$(tc sgr0)"
TC_RED="$(tc setaf 1)"; TC_GREEN="$(tc setaf 2)"
TC_YELLOW="$(tc setaf 3)"; TC_BLUE="$(tc setaf 4)"; TC_MAG="$(tc setaf 5)"; TC_CYAN="$(tc setaf 6)"
# 行内高亮用的背景色。以前只在详情页写 `${TC_BG_BLACK:-}`，这里却从来没定义过，
# 于是那个"注意事项"提示永远没有底色（=静默失效）。一并补上。
TC_BG_BLACK="$(tc setab 0)"

tui_clear() { clear 2>/dev/null || printf '\n\n\n\n'; }

# 逐字符打印分隔线：
# 旧实现用 `tr ' ' "$ch"`，在多字节 locale 下 tr 按字节替换，
# '─'(E2 94 80) 会被拆成 3 个字节分别映射，产生非法 UTF-8 乱码。
# ⚠ 宽度不能用 ${COLUMNS:-80}：bash 只在**交互式** shell 里维护 COLUMNS，
#   脚本里通常为空 → 分隔线永远是 80 格，宽终端上短一截、窄终端上折行。
#   改成向终端问一次（tput cols），问不到（重定向 / 非 tty）才退回 80。
draw_line() {
    local ch="${1:--}" w="${COLUMNS:-0}" pad
    if (( w <= 0 )); then w="$(tput cols 2>/dev/null || echo 0)"; fi
    if (( w <= 0 )); then w=80; fi
    # 一次成型，不用 for 逐字符 printf（300 列终端 = 300 次 fork 级调用）。
    # 也不用 tr：多字节 locale 下 tr 按字节替换，'─'(E2 94 80) 会被拆成
    # 3 个字节分别映射，产生非法 UTF-8。bash 自己的参数展开没这个问题。
    printf -v pad '%*s' "$w" ''
    printf '%s\n' "${pad// /$ch}"
}

# 打印一个带标题的分隔框；参数：标题
# 旧实现用 cut -c$((...+${#title}))，${#title} 是字节数而 cut -c 也按字节切，
# 中文标题会被从多字节字符中间切开产生乱码。这里改为不填满整行，避免截断。
draw_header() {
    local title="${1:-}"
    printf '%s=== %s ===%s\n' "${TC_BOLD}${TC_GREEN}" "$title" "${TC_RESET}"
}

# 欢迎页 / Splash
show_splash() {
    tui_clear
    draw_header "sijin-xb's dotfiles · Rice ${RICE_VERSION}"
    cat <<'EOF'

          _____ _ _   _           _        _ _         __  _  ____
         / ____(_) | (_)         | |      (_) |       /_ |/ |/ ___|
        | (___  _| |_ _ _ __   __| |_ __   _| | ___    | || | |
         \___ \| | __| | '_ \ / _` | '_ \ | | |/ _ \   | || | |
         ____) | | |_| | | | | (_| | | | || | | (_) |  | || | |___
        |_____/|_|\__|_|_| |_|\__,_|_| |_|/ |_|\___/   |_||_|\____|
                                           _/ |
                                          |__/

        Arch Linux · Hyprland / niri · Quickshell / DMS

EOF
    draw_header "✨ 核心特性"
    printf '  %s%s%1s 桌面歌词%s             逐字计时（酷狗 KRC），自动适配任意 MPRIS 播放器\n' "${TC_BOLD}" "${TC_GREEN}" "·" "${TC_RESET}"
    printf '  %s%s%1s 拼音搜索启动器%s     支持中文拼音搜索 + 窗口缩略图悬浮信息卡\n' "${TC_BOLD}" "${TC_YELLOW}" "·" "${TC_RESET}"
    printf '  %s%s%1s 终端召唤%s             SUPER+T 居中浮动，状态保留（kitty-quake）\n'   "${TC_BOLD}" "${TC_BLUE}" "·" "${TC_RESET}"
    printf '  %s%s%1s Material 3 取色%s     matugen 壁纸→全局配色（11+ 应用联动）\n'        "${TC_BOLD}" "${TC_RED}" "·" "${TC_RESET}"
    echo
    draw_header "🖥️  适配环境"
    printf '  OS       : Omarchy / CachyOS / Arch Linux / EndeavourOS（需要 /etc/arch-release）\n'
    printf '  会话     : Wayland · Hyprland + end4-PC / caelestia，或 niri + DMS\n'
    printf '  GPU 建议 : Intel 核显 UHD 620+ / AMD Vega 3+ / NVIDIA（需开启 modeset）\n'
    echo
    printf '%s按任意键进入主菜单 ...%s' "${TC_BOLD}${TC_YELLOW}" "${TC_RESET}"
    IFS= read -r -n 1 -s || true
    echo
}

show_help() {
    tui_clear
    draw_header "帮助 / 使用说明"
    echo
    echo "【① 适配环境】"
    echo "  · OS: Omarchy / CachyOS / Arch / EndeavourOS（/etc/arch-release 必须存在）"
    echo "  · 会话: Wayland · Hyprland（end4-PC / caelestia）或 niri（DMS）"
    echo "  · 建议 GPU: ≥ Intel UHD 620（模糊 + 壁纸视差要一点 GPU 算力）"
    echo
    echo "【② 键位速览】"
    echo "  SUPER         启动器（中文拼音搜索 + 窗口缩略图信息卡）"
    echo "  SUPER+T       终端召唤（居中浮动半透明，再按隐藏）"
    echo "  SUPER+S       Scratchpad（临时工作区）"
    echo "  SUPER+L       锁屏（Quickshell LockSurface / caelestia lock）"
    echo "  SUPER+F1      重启 fcitx5 输入法（rime 卡住时用）"
    echo "  SUPER+ESC     打开 quickshell 设置面板"
    echo "  SUPER+方向键  切换工作区 / 移动窗口焦点（配合 SHIFT 则移动窗口）"
    echo
    echo "【③ 目录说明】"
    echo "  ~/.config/hypr/hyprland.lua            Hyprland 配置总入口"
    echo "    ├── hyprland/   默认模板层（由 quickshell/上游管理，建议只读）"
    echo "    ├── custom/     用户差异层（blur / shadow 细项在 custom/general.lua）"
    echo "    └── shellOverrides/main.lua    由 quickshell 设置面板写入，优先级最高"
    echo "  ~/.config/quickshell/end4-pC/         quickshell 底盘 + 差异层（end4-PC）"
    echo "  ~/.config/quickshell/caelestia/       caelestia shell 本体（仅 caelestia）"
    echo "  ~/src/caelestia-plugin-src/           Caelestia QML 插件源码（编译用）"
    echo "  ~/src/caelestia-build/qml/            插件编译产物（QML2_IMPORT_PATH）"
    echo "  ~/.config/niri/config.kdl             niri 配置入口（DMS）"
    echo "  ~/.local/state/dotfiles-backup/       备份根（snapshots/ + state/）"
    echo
    echo "【④ 常见问题 FAQ】"
    echo "  Q: 回档后想再换回 rice？"
    echo "  A: 执行 ./install.sh restore（rollback 前自动保存的 pre-rollback 快照会被还原）"
    echo "  Q: 卸载存档放在哪？"
    echo "  A: 默认 \$HOME/dotfiles-archive-时间戳.tar.gz；可用 -o 自定义"
    echo "  Q: 面板模糊效果太浓 / 太淡？"
    echo "  A: quickshell 设置 → 配置文件 → Hyprland：模糊半径(10→8/12)，"
    echo "     活动不透明度(82→更高更清晰或更低更通透)；细项在 ~/.config/hypr/custom/general.lua"
    echo
    printf '%s按任意键返回主菜单%s' "${TC_BOLD}${TC_YELLOW}" "${TC_RESET}"
    IFS= read -r -n 1 -s || true
    echo
}

# 二级详情页模板：输入标题 + 说明段 + 当前状态渲染函数名 + 动作函数名
# 但为了避免 bash 里"传递函数名又保持可读"，直接用 4 个独立函数保持简单

detail_install() {
    local cont=y
    while [[ $cont == y ]]; do
        tui_clear
        draw_header "菜单 1/4 · 执行安装（7 步流程）"
        echo
        cat <<'EOF'
【功能说明】
  从零部署 sijin-xb's dotfiles：
    [1/7] pacman 基础依赖（hyprland / kitty / fish / fcitx5 / cmake ...）
          niri 本体不在这里，走 [2/7] 的 AUR fork 包 niri-shorin-fork-git
          end4-PC 会话额外装 kvantum / kvantum-qt5（Qt 主题引擎）
          默认只装缺失项；FULL_UPGRADE=1 ./install.sh install 可全系统升级
    [2/7] AUR 包（niri 本体 niri-shorin-fork-git / matugen / mpvpaper
          + Caelestia 插件依赖（libcava / qt6-m3shapes-git，end4-pC 也需要）
          + 所选 shell 专属包（end4-PC 的 plasma6-themes-colloid-git 等）
          + 引导 yay）
    [3/7] quickshell 三级回退（已装→仓库→AUR→源码编译）
    [4/7] 桌面 Shell：
          [4a] Caelestia QML 插件 —— end4-pC 与 caelestia 都编（锁屏硬依赖
               import Caelestia.Config，跳过会导致 shell 加载失败）
          [4b] shell 本体：end4-PC 拉底盘 / caelestia clone
               （dms 无此步，DMS 由 [2/7] 的 AUR 包提供）
    [5/7] dot_ 前缀 → $HOME 部署（按会话过滤）；有差异的旧文件自动备份
    [6/7] 拼音搜索 Python venv + pypinyin / dbus-python
    [7/7] 输出后续指引（注销重新登录 · fish chsh · 键位速览）
  · 开始前自动保存 pre-install 快照（./install.sh rollback 的基线）
  · 幂等：重复 2 次结果一致（已在的包/文件跳过）

【当前状态】
EOF
        echo "  · 用户         : ${USER:-unknown}"
        echo "  · \$HOME       : $HOME"
        # 以前这里写的是 `echo ✓' 满足'`，引号错位只是碰巧能跑；而且只报"是不是
        # Arch 系"、不报**是哪个发行版**，Omarchy 上看着像是没被识别。改为读
        # os-release 打印真实名字。
        local osname="未知"
        [[ -r /etc/os-release ]] && osname="$( . /etc/os-release && printf '%s' "${PRETTY_NAME:-${ID:-未知}}" )"
        if [[ -f /etc/arch-release ]]; then
            echo "  · 发行版检测   : ✓ $osname（Arch 系）"
        else
            echo "  · 发行版检测   : ✗ $osname（非 Arch 系，本脚本将拒绝运行）"
        fi
        # sudo 可用性单独一行说明：有 sudo 用 sudo（可用 SUDO 环境变量覆盖），
        # 没有则明确告知装不了，别再输出一串字面量。
        if have sudo; then
            echo "  · sudo 可用?   : ✓（将使用 \${SUDO:-sudo} 提权执行 pacman）"
        else
            echo "  · sudo 可用?   : ✗（找不到 sudo，[1/7] 依赖安装会失败）"
        fi
        echo "  · 已存在的 rice 路径数:"
        local cnt=0 p
        # 注意：不能用 `[[ ... ]] && cnt=$((cnt+1))` 作为 for 体最后一条命令，
        # 最后一次 [[ ]] 失败会让 for 返回 1，配合 set -e 直接杀掉整个脚本。
        for p in "${SNAP_PATHS[@]}"; do
            if [[ -e "$HOME/$p" ]]; then cnt=$((cnt+1)); fi
        done
        echo "                 : $cnt / ${#SNAP_PATHS[@]}（新机器通常为 0~2；现有 rice 安装通常 ≥ 10）"
        [[ -r "$STATE_DIR/current" ]] && echo "  · 上次快照基线 : $(<"$STATE_DIR/current")" || echo "  · 快照基线     : 尚未安装过，本次运行将生成 rollback 可用基线"
        # 字体开关：env FONTS 有预设就沿用，否则默认「装」，按 f 切换。
        # 这里顺手把 FONTS_ASKED 置 1，下面 ( cmd_install ) 里的 choose_fonts
        # 才不会再问第二遍（子 shell 会继承 FONTS 与 FONTS_ASKED）。
        if [[ -z $FONTS ]]; then FONTS=1; fi
        FONTS_ASKED=1
        echo "  · 字体安装     : $(fonts_label)（按 f 切换）"
        echo
        printf '%s 注意事项%s：默认只装缺失依赖（首次可能 5-15 分钟）；quickshell 源码编译 5-15 分钟；Caelestia 插件编译 1-3 分钟（end4-pC / caelestia 都要）。\n' "${TC_BOLD}${TC_YELLOW}${TC_BG_BLACK:-}" "${TC_RESET}"
        echo
        # 二次确认 + 字体开关 + 返回
        # 这里不复用 confirm_3way：安装页要多给一个 f 键做字体切换，
        # 换选项就得重绘本页（外层 while 重新循环）。
        local ans=""
        printf '%s确认开始执行安装？%s [y=开始 / f=切换字体 / b=返回主菜单] ' \
            "${TC_BOLD}${TC_YELLOW}" "${TC_RESET}"
        IFS= read -r ans || ans="b"
        case "$ans" in
            y|Y|yes|YES|Yes)
                # 用子 shell 包裹：cmd_install 内部的 die 只会退出子 shell，
                # 不会再连带把 TUI 一起 exit 掉（之前界面"卡死"的根因之一）。
                local rc=0
                set +e; ( cmd_install ); rc=$?; set -e
                ((rc != 0)) && warn "安装返回码 ${rc}（详情见上方输出）" || true
                tui_clear
                read -r -p "按回车返回主菜单 ..." _ || true
                cont=n ;;
            f|F) fonts_toggle; continue ;;
            b|B) cont=n ;;
            *)   read -r -p "已取消，按回车返回主菜单 ..." _ || true; cont=n ;;
        esac
    done
}

detail_uninstall() {
    local cont=y
    while [[ $cont == y ]]; do
        tui_clear
        draw_header "菜单 2/4 · 执行卸载（可选存档）"
        echo
        cat <<'EOF'
【功能说明】
  移除 rice 相关的配置/数据文件（可选先打包存档）：
    1) 可选：打包存档为 dotfiles-archive-uninstall-时间戳.tar.gz
    2) 删除 ~/.config/hypr 或 niri / quickshell / DankMaterialShell / fish / kitty / matugen ... 等 rice 管理目录
    3) 不删除 ~/ 下其他非 rice 用户文件
  · 系统程序（hyprland / qs / pacman 安装的二进制）保留，如需清理请自行 pacman -Rns

【当前状态】
EOF
        # 这里问一次删除范围，cmd_uninstall 在同一 shell 里沿用，不会重复提问
        uninstall_compositor_scope
        local paths=() p
        mapfile -t paths < <(active_snap_paths)
        local cnt=0
        for p in "${paths[@]}" "${EXTRA_ARCHIVE_PATHS[@]}"; do
            if [[ -e "$HOME/$p" ]]; then cnt=$((cnt+1)); fi
        done
        echo "  · 将会删除的顶级路径数（存在才删）: $cnt"
        local tsize=0
        for p in "${paths[@]}" "${EXTRA_ARCHIVE_PATHS[@]}"; do
            if [[ -e "$HOME/$p" ]]; then
                local sz; sz="$(du -sk "$HOME/$p" 2>/dev/null | awk '{print $1}')"
                [[ -n ${sz:-} ]] && tsize=$((tsize + sz))
                printf '     rm -rf ~/%s (%s)\n' "$p" "$(du -sh "$HOME/$p" 2>/dev/null | cut -f1)"
            fi
        done
        echo "  · 估算释放空间: $(numfmt --to=iec "${tsize}K" 2>/dev/null || echo ${tsize}KB)"
        echo
        case "$(confirm_3way '确认进入卸载流程？')" in
            0) local rc=0
               set +e; ( cmd_uninstall ); rc=$?; set -e
               ((rc != 0)) && warn "卸载返回码 ${rc}（详情见上方输出）" || true
               tui_clear
               read -r -p "按回车返回主菜单 ..." _ || true
               cont=n ;;
            2) cont=n ;;
            *) read -r -p "已取消，按回车返回主菜单 ..." _ || true; cont=n ;;
        esac
    done
}

detail_rollback() {
    local cont=y
    while [[ $cont == y ]]; do
        tui_clear
        draw_header "菜单 3/4 · 执行回档（还原到上次 install 之前）"
        echo
        cat <<'EOF'
【功能说明】
  把系统配置还原到"最近一次 ./install.sh install 之前"的状态。
  步骤：
    1) 先保存当前配置为 pre-rollback 快照（供 restore 功能用）
    2) 读取 state/current → 解包 pre-install 快照覆盖进 $HOME
  · 只覆盖快照内包含的文件，不会删除快照外的用户文件。

【当前状态】
EOF
        local snap=""
        # ⚠ 原来这里写的是 `read_state ... || true`，把退出码抹成 0，
        # 导致下面的 else（"基线快照不存在"）成了死分支，快照缺失时照样往下走。
        if snap="$(read_state current 2>/dev/null)"; then
            local nfiles
            # grep -c 计数为 0 时会自己打印 "0" 但返回 1 —— 用 || true 压退出码
            # 即可，不能写 || echo 0（会追加第二行，变量值变成 "0\n0"）。
            nfiles="$(tar -tzf "$snap" 2>/dev/null | grep -cv '/$' || true)"
            echo "  · 基线快照   : $(basename "$snap")"
            echo "  · 创建时间   : $(stat -c '%y' "$snap" 2>/dev/null || unknown)"
            echo "  · 约含文件数 : ${nfiles}"
            echo "  · 快照大小   : $(du -h "$snap" | cut -f1)"
        else
            echo "  ⚠  基线快照不存在：请先至少运行一次 install（TUI 菜单 1）生成基线。"
            echo "     rollback 目前不可执行。"
        fi
        if [[ -r "$STATE_DIR/before-rollback" ]]; then
            echo "  · restore 基线: 已存在（之前做过回档，可用 restore 撤销回档）"
        else
            echo "  · restore 基线: 不存在"
        fi
        echo
        if [[ -z $snap ]]; then
            read -r -p "按回车返回主菜单 ..." _ || true; cont=n
        else
            case "$(confirm_3way '确认执行回档？')" in
                0) local rc=0
                   set +e; ( cmd_rollback ); rc=$?; set -e
                   ((rc != 0)) && warn "回档返回码 ${rc}（详情见上方输出）" || true
                   tui_clear
                   read -r -p "按回车返回主菜单 ..." _ || true
                   cont=n ;;
                2) cont=n ;;
                *) read -r -p "已取消，按回车返回主菜单 ..." _ || true; cont=n ;;
            esac
        fi
    done
}

detail_archive() {
    local cont=y out_path=""
    while [[ $cont == y ]]; do
        tui_clear
        draw_header "菜单 4/4 · 卸载存档打包"
        echo
        cat <<'EOF'
【功能说明】
  将 rice 相关的全部配置 / 数据 / 状态 / 备份统一打包为 tar.gz：
    ① 全部 rice 配置路径（hypr / niri / quickshell / DankMaterialShell / fish / nvim ...）
    ② ~/.local/state/quickshell/ （venv / 生成的颜色 / 状态）
    ③ ~/.local/state/dotfiles-backup/ （旧备份 / snapshots / state）
    ④ ~/.cache/quickshell/ （歌词缓存 / 通知等）
  · 包内附带 MANIFEST.txt（用户名 / 时间戳 / 源路径清单）
  · 可选：打包后清理源文件（等于卸载 + 存档合二为一）

【当前可用参数】
EOF
        [[ -z $out_path ]] && out_path="$HOME/dotfiles-archive-$(now_ts).tar.gz"
        # 旧实现 read -r -i ... 依赖 readline，未加 -e 时行为未定义/报错。
        # 改为手动提示 + 空则保留默认值。
        printf '  · 输出文件 [%s]: ' "$out_path"
        local _ans=""
        IFS= read -r _ans || true
        [[ -n "$_ans" ]] && out_path="$_ans" || true
        local p cnt=0 tsize=0
        for p in "${SNAP_PATHS[@]}" "${EXTRA_ARCHIVE_PATHS[@]}"; do
            if [[ -e "$HOME/$p" ]]; then
                cnt=$((cnt+1))
                local sz; sz="$(du -sk "$HOME/$p" 2>/dev/null | awk '{print $1}')"
                [[ -n ${sz:-} ]] && tsize=$((tsize+sz))
            fi
        done
        echo "  · 包含顶级路径: $cnt / $(( ${#SNAP_PATHS[@]} + ${#EXTRA_ARCHIVE_PATHS[@]} ))"
        echo "  · 估算打包大小: $(numfmt --to=iec "${tsize}K" 2>/dev/null || echo ${tsize}KB)"
        echo
        local dodel=0
        if confirm "打包完成后是否删除源文件（相当于先备份再卸载）？"; then dodel=1; fi
        echo
        case "$(confirm_3way '确认开始打包存档？')" in
            0) local rc=0
               if ((dodel)); then
                   set +e; ( cmd_archive -o "$out_path" --delete ); rc=$?; set -e
               else
                   set +e; ( cmd_archive -o "$out_path" ); rc=$?; set -e
               fi
               ((rc != 0)) && warn "打包返回码 ${rc}（详情见上方输出）" || true
               tui_clear
               read -r -p "按回车返回主菜单 ..." _ || true
               cont=n ;;
            2) cont=n ;;
            *) read -r -p "已取消，按回车返回主菜单 ..." _ || true; cont=n ;;
        esac
    done
}

# 三向确认：输出 0=yes / 1=no / 2=back（调用方用 case "$(confirm_3way ...)" 取值）
# ⚠ 两个坑，改之前先看这里：
#   1) 必须 echo 数字，不能只 return —— 调用方是 $( )，只捕获 stdout，
#      用 return 的话 $( ) 恒为空串，case 永远落到 *) 分支（= 按什么键都是取消）。
#   2) 提示必须写 stderr —— $( ) 连 stdout 一起吞，提示写 stdout 用户永远看不见，
#      表现就是「按了没反应」。
confirm_3way() {
    local prompt="${1:-确认？}" ans
    printf '%s [y/N/b(返回主菜单)] ' "$prompt" >&2
    IFS= read -r ans || ans=""
    case "$ans" in
        y|Y|yes|YES|Yes) printf '0' ;;
        b|B)             printf '2' ;;
        *)               printf '1' ;;
    esac
}

# 增量升级子菜单。update 是日常操作（install 会重装包、重拉底盘、冲掉本地对
# 底盘的改动），但它原来只能敲子命令，TUI 里没有入口 —— 补上。
# TUI 不暴露全部开关，只留最常用的四个组合，其余仍走命令行。
detail_update() {
    while true; do
        tui_clear
        draw_header "增量升级（update）"
        echo
        echo "  只做文件层同步：不重装包、不重拉上游底盘、不编插件。"
        echo "  升级前会自动创建快照，出问题用主菜单 [4] 回档。"
        echo
        printf '  %s[1]%s  直接同步（等价 ./install.sh update）\n'          "${TC_BOLD}${TC_GREEN}"  "${TC_RESET}"
        printf '  %s[2]%s  先看会改什么（--dry-run，一个字节都不写）\n'      "${TC_BOLD}${TC_BLUE}"   "${TC_RESET}"
        printf '  %s[3]%s  同步并补齐新增依赖（--with-packages，只补不卸）\n' "${TC_BOLD}${TC_MAG}"    "${TC_RESET}"
        printf '  %s[4]%s  先 git pull 再同步（--pull）\n'                   "${TC_BOLD}${TC_CYAN}"   "${TC_RESET}"
        echo
        printf '  %s[b]%s  返回主菜单\n' "${TC_BOLD}" "${TC_RESET}"
        draw_line '─'
        local sel=""
        printf '请选择: '
        if ! IFS= read -r sel; then echo; return 0; fi
        case "$sel" in
            1) tui_clear; cmd_update || true ;;
            2) tui_clear; cmd_update --dry-run || true ;;
            3) tui_clear; cmd_update --with-packages || true ;;
            4) tui_clear; cmd_update --pull || true ;;
            b|B|back) return 0 ;;
            *) printf '%s无效选项%s\n' "${TC_RED}" "${TC_RESET}"; sleep 0.3; continue ;;
        esac
        echo
        printf '按回车返回...'
        IFS= read -r _ || true
    done
}

# 状态与诊断子菜单：把 5 条只读命令挂上来，省得记子命令名。
# 每条命令后停一次等回车 —— 不停的话下一轮 tui_clear 会立刻把输出刷掉。
detail_diagnose() {
    while true; do
        tui_clear
        draw_header "状态与诊断"
        echo
        printf '  %s[1]%s  部署状态（status）\n'          "${TC_BOLD}${TC_GREEN}"  "${TC_RESET}"
        printf '  %s[2]%s  环境体检（doctor）\n'          "${TC_BOLD}${TC_BLUE}"   "${TC_RESET}"
        printf '  %s[3]%s  依赖缺口（deps --missing）\n'  "${TC_BOLD}${TC_MAG}"    "${TC_RESET}"
        printf '  %s[4]%s  主题一致性（theme）\n'         "${TC_BOLD}${TC_CYAN}"   "${TC_RESET}"
        printf '  %s[5]%s  清理预览（clean --dry-run）\n' "${TC_BOLD}${TC_YELLOW}" "${TC_RESET}"
        echo
        printf '  %s[b]%s  返回主菜单\n' "${TC_BOLD}" "${TC_RESET}"
        draw_line '─'
        local sel=""
        printf '请选择: '
        if ! IFS= read -r sel; then echo; return 0; fi
        # doctor 在有缺口时返回 1、clean 在中止时返回非 0 —— 都要兜住，
        # 否则 set -e 会把整个 TUI 干掉。
        case "$sel" in
            1) tui_clear; cmd_status || true ;;
            2) tui_clear; cmd_doctor || true ;;
            3) tui_clear; cmd_deps --missing || true ;;
            4) tui_clear; cmd_theme || true ;;
            5) tui_clear; cmd_clean --dry-run || true ;;
            b|B|back) return 0 ;;
            *) printf '%s无效选项%s\n' "${TC_RED}" "${TC_RESET}"; sleep 0.3; continue ;;
        esac
        echo
        printf '按回车返回...'
        IFS= read -r _ || true
    done
}

main_menu_loop() {
    while true; do
        tui_clear
        draw_header "主菜单 · sijin-xb's dotfiles ${RICE_VERSION}"
        echo
        printf '  %s[1]%s  执行安装\n'      "${TC_BOLD}${TC_GREEN}" "${TC_RESET}"
        printf '  %s[2]%s  增量升级（只同步文件层）\n' "${TC_BOLD}${TC_GREEN}" "${TC_RESET}"
        printf '  %s[3]%s  执行卸载（可先存档）\n' "${TC_BOLD}${TC_RED}"   "${TC_RESET}"
        printf '  %s[4]%s  执行回档（还原到上次 install 之前）\n' "${TC_BOLD}${TC_YELLOW}" "${TC_RESET}"
        printf '  %s[5]%s  卸载存档打包\n'      "${TC_BOLD}${TC_BLUE}"  "${TC_RESET}"
        printf '  %s[6]%s  状态与诊断（status / doctor / deps / theme / clean）\n' "${TC_BOLD}${TC_CYAN}" "${TC_RESET}"
        echo
        printf '  %s[h]%s  帮助 / 环境 · 键位 · 目录 · FAQ\n' "${TC_BOLD}${TC_MAG}" "${TC_RESET}"
        printf '  %s[q]%s  退出脚本\n'             "${TC_BOLD}"        "${TC_RESET}"
        draw_line '─'
        local sel=""
        printf '请选择: '
        # stdin EOF（例如被管道/重定向）时不要用 set -e 杀掉脚本，优雅退出
        if ! IFS= read -r sel; then
            echo
            echo "输入结束，退出。"
            return 0
        fi
        case "$sel" in
            1) detail_install ;;
            2) detail_update ;;
            3) detail_uninstall ;;
            4) detail_rollback ;;
            5) detail_archive ;;
            6) detail_diagnose ;;
            h|H|help) show_help ;;
            q|Q|quit|exit) echo "再见 👋"; return 0 ;;
            *) printf '%s无效选项，请按 1/2/3/4/5/6 / h / q%s\n' "${TC_RED}" "${TC_RESET}"
               sleep 0.3 ;;
        esac
    done
}

enter_tui() {
    # stdin 与 stdout 都要是终端：只查 stdin 的话，`./install.sh > log` 会把
    # clear 与所有 ANSI 码写进文件。
    if [[ ! -t 0 || ! -t 1 ]]; then
        warn "标准输入/输出不是终端，无法进入 TUI。请直接使用子命令："
        warn "  $0 install | update | rollback | restore | archive | uninstall"
        warn "  $0 status | doctor | deps | theme | clean"
        exit 1
    fi
    show_splash
    main_menu_loop
}

