# ============================================================
# Python 引擎（dotctl）的调用入口
# ============================================================
# 部分子命令已迁到 dotctl（纯标准库 Python），其余仍在 bash。
# lib/8x-cmd-*.sh 里已迁的只剩一行转发，实现看 dotctl/commands/。
#
# 用 PYTHONPATH 而不是 cd：后者会改工作目录，而脚本里所有相对路径都以调用者
# 的 cwd 为准，换目录行为会跟着变。
#
# 下面这些环境变量必须显式传，Python 子进程拿不到：
#   DOTCTL_SELF           调用者看到的安装器路径，提示语里要用
#   DOTCTL_COLOR          按 install.sh 的 fd 1 算好的颜色开关。
#                         子进程自己判 isatty() 会得出相反结论
#   DOTCTL_BASH_VERSION   doctor 要显示 bash 版本
#   DOTCTL_BACKUP_ROOT / _SNAP_ROOT / _STATE_DIR
#                         这三个在 bash 侧是 source 时冻结的常量。
#                         Python 若按 $HOME 动态推，改 HOME 后再调就会分叉
#   TMPRUN                当前这次运行的临时目录，clean 要跳过它
dotctl_run() {
    have python3 || die "该子命令已迁到 Python 实现，需要 python3 3.11+（sudo pacman -S python）"
    # TMPRUN 要显式传：它是 lib/10-util.sh 里的普通变量（没 export），而
    # clean 必须能认出「当前这次运行自己的临时目录」并跳过它 —— 删了它，
    # 本次运行后续的 mktmp 全部失效，EXIT trap 也没东西可清。
    # DOTCTL_BASH_VERSION 同理：doctor 里那一行「bash 5.3」取自 BASH_VERSINFO，
    # 而它也不是导出变量，Python 侧只能由这里递过去。
    #
    # DOTCTL_COLOR：把 bash 侧已经算好的颜色开关递过去。它按 install.sh 启动
    # 时的 fd 1 判定，而 Python 是子进程 —— 自己判 isatty() 会得出相反的结论
    # （同一份输出一边带 ANSI 一边不带；archive 的计划清单实测踩到）。
    # DOTCTL_BACKUP_ROOT / _SNAP_ROOT / _STATE_DIR：bash 侧这三个路径是 source
    # 时算好的**常量**，之后不再随 $HOME 变。Python 若自己按 $HOME 动态推，会在
    # 「改了 HOME 再调函数」的场景下与 bash 分道扬镳 —— archive 的测试就是
    # 这么暴露的：子 shell 里换 HOME 后，bash 仍用旧 HOME 的备份目录（于是
    # 「无可打包路径」→ 返回 1），Python 动态读新 HOME、被 ensure_dirs 建出目录
    # → 变成有路径 → 返回 0。传下来才与 bash 一致。
    DOTCTL_SELF="${DOTCTL_SELF:-$0}" \
    DOTCTL_COLOR="$([[ -n $C_GREEN ]] && echo 1 || echo 0)" \
    DOTCTL_BASH_VERSION="${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}" \
    DOTCTL_BACKUP_ROOT="$BACKUP_ROOT" \
    DOTCTL_SNAP_ROOT="$SNAP_ROOT" \
    DOTCTL_STATE_DIR="$STATE_DIR" \
    TMPRUN="${TMPRUN:-}" \
    PYTHONPATH="$SRC${PYTHONPATH:+:$PYTHONPATH}" python3 -m dotctl "$@"
}

# 归档涉及的路径清单（SNAP_PATHS + EXTRA_ARCHIVE_PATHS），一行一个。
# 供 dotctl 的 archive 读取 —— 与 deps_collect 同理：清单留在 bash 侧当唯一
# 来源，Python 不另抄一份，否则两边迟早不一致（改了 bash 忘改 Python，
# 归档范围就与快照/卸载范围对不上）。
dotctl_archive_paths() {
    printf '%s\n' "${SNAP_PATHS[@]}" "${EXTRA_ARCHIVE_PATHS[@]}"
}

# EXTRA_ARCHIVE_PATHS（快照目录 / quickshell 状态 / 缓存），一行一个。
# 与 dotctl_archive_paths 分开：archive 的 --delete 只删这一份 + 当前会话的
# active_snap_paths，不删 SNAP_PATHS 全集。
dotctl_extra_paths() {
    printf '%s\n' "${EXTRA_ARCHIVE_PATHS[@]}"
}

# 用冻结的路径常量建目录，不走 ensure_dirs。
# ensure_dirs 按运行时 $HOME 算，改 HOME 后与 BACKUP_ROOT 等常量分叉，
# 会让「无可打包路径」的场景变成有路径。
dotctl_ensure_frozen_dirs() {
    mkdir -p "$BACKUP_ROOT" "$SNAP_ROOT" "$STATE_DIR"
}

# uninstall 用：在同一个 bash 进程里选范围并算删除清单。
#
# 必须一次 fork 完成：uninstall_*_scope 设置的 COMPOSITOR / QS_SHELL /
# INSTALL_BOTH_COMPOSITORS 正是 active_snap_paths 的输入。分两次 fork
# 第二次看不到这些值，会把另一套会话的配置也删掉。
#
# 结果写文件而不是 stdout：那两个函数要从 stdin 读答案，用命令替换捕获
# 输出会吞掉提示、并让 read 拿到空 stdin。
dotctl_uninstall_plan() {
    local outfile="$1"
    uninstall_compositor_scope
    uninstall_shell_scope
    {
        printf 'SCOPE=%s|%s|%s\n' "${QS_SHELL:-}" "${COMPOSITOR:-}" "${INSTALL_BOTH_COMPOSITORS:-0}"
        active_snap_paths
    } > "$outfile"
}

# ============================================================
# install 的外部流程（供 dotctl 经 bashsrc 调用）
# ============================================================
# 这几段以调外部命令为主（pacman / git clone / cmake / qs），留在 bash 侧
# 由 Python 编排调用。
#
# 提到顶层而不是 cmd_install 的嵌套函数，否则 bashsrc 调不到。
# install_caelestia_plugin 输出直接进终端，调用方用 call_streaming。

install_quickshell() {
    if have qs; then
        echo "    已安装: $(qs --version 2>/dev/null | head -1)"
        return 0
    fi
    if in_sync_db quickshell; then
        echo "    从二进制仓库安装"
        "${SUDO:-sudo}" pacman -S --needed --noconfirm quickshell && return 0
    fi
    if [[ -n $(aur_helper) ]] && aur_install quickshell-git; then
        echo "    已从 AUR 安装 quickshell-git"
        return 0
    fi
    echo "    从源码编译（tag v0.3.1，需要几分钟）"
    "${SUDO:-sudo}" pacman -S --needed --noconfirm cmake ninja qt6-base qt6-declarative qt6-wayland qt6-5compat qt6-shadertools qt6-svg wayland-protocols
    local src; src="$(mktmpd)"
    git clone --depth=1 --branch v0.3.1 https://github.com/outfoxxed/quickshell.git "$src" \
        || git clone --depth=1 https://github.com/outfoxxed/quickshell.git "$src" \
        || die "克隆 quickshell 源码失败（检查网络后重试；也可以从 GitHub Releases 手动下载二进制放进 PATH）"
    cmake -S "$src" -B "$src/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
        || die "quickshell CMake 配置失败，见上方输出（通常是缺 Qt6 组件）。"
    cmake --build "$src/build" --parallel \
        || die "quickshell 编译失败，见上方输出。"
    "${SUDO:-sudo}" cmake --install "$src/build" \
        || die "quickshell 安装到 /usr/local 失败，见上方输出。"
    rm -rf "$src"
}

install_caelestia_plugin() {
    local src="$HOME/src/caelestia-plugin-src"
    local build="$HOME/src/caelestia-build"

    # 1) 插件源码来源：浅克隆一份独立的源码树。只用到 plugin/ 子目录
    #    （编译时由 -DENABLE_MODULES=plugin 限定，见第 3 步），
    #    不需要 caelestia 的 shell 本体。
    if [[ ! -d "$src/plugin" ]]; then
        say "    克隆 caelestia 源码（为编译 Caelestia QML 插件）"
        mkdir -p "$(dirname "$src")"
        git clone --depth=1 https://github.com/caelestia-dots/shell.git "$src" \
            || die "克隆 caelestia-dots/shell 失败（Caelestia 插件源码，检查网络后重试）。"
    else
        echo "    已存在插件源码: $src/plugin"
    fi

    # 2) 本地覆盖层（汉化 po / 改过的 CMakeLists）。
    #    ⚠ 必须在编译前应用：晚一步这些文件赶不上这次编译，翻译会静默不生效。
    local overlay="$SRC/config/desktop/quickshell/caelestia"
    local ovl_hash=""
    if [[ -d "$overlay" ]]; then
        while IFS= read -r -d '' rel; do
            mkdir -p "$src/$(dirname "${rel#./}")"
            cp -a "$overlay/$rel" "$src/${rel#./}"
        done < <(cd "$overlay" && find . -type f -print0)
        ovl_hash="$(cd "$overlay" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16)"
        echo "    已应用 caelestia 覆盖层（$(cd "$overlay" && find . -type f | wc -l) 个文件）"
    fi

    # 幂等：已有 .so 且覆盖层 hash 未变才跳过。只看 .so 会漏掉
    # po/CMakeLists 的改动，静默停留在旧版本。
    local stamp="$build/.overlay-stamp"
    if compgen -G "$build/qml/Caelestia/*.so" >/dev/null \
        && [[ -f "$stamp" && "$(cat "$stamp")" == "$ovl_hash" ]]; then
        echo "    已编译: $build/qml（覆盖层无变化）"
        return 0
    fi

    # CMakeCache.txt 记录上次的源码目录。源码位置换过后复用旧构建目录，
    # CMake 会拿缓存里的老路径找 CMakeLists，表现为配置失败或链接到
    # 已删除的目标文件。不匹配就整个清掉重配。
    if [[ -f "$build/CMakeCache.txt" ]]; then
        local _cached_src
        _cached_src="$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "$build/CMakeCache.txt" | head -1)"
        if [[ -n "$_cached_src" && "$_cached_src" != "$src" ]]; then
            warn "构建目录的源码路径已变（$_cached_src → $src），清空后重新配置"
            rm -rf "$build"
        fi
    fi

    have cmake && have ninja || die "缺少 cmake/ninja，无法编译 Caelestia 插件（end4-pC 锁屏硬依赖）。"
    # 上游 CMakeLists 用 git describe / rev-parse 取 VERSION 和 GIT_REVISION，
    # 任一为空就 FATAL_ERROR。shallow clone 没有 tag，源码若被拷贝则无 .git。
    # 这里显式算好传入，绕开 CMakeLists 里的 git 调用。
    ( cd "$src" && git fetch --tags --depth=1 --quiet 2>/dev/null ) || true
    local _cv="" _rev=""
    _cv="$(cd "$src" && git describe --tags --abbrev=0 2>/dev/null || true)"
    _rev="$(cd "$src" && git rev-parse HEAD 2>/dev/null || true)"
    [[ -z "$_cv" ]] && _cv="0.0.0"
    [[ -z "$_rev" ]] && _rev="unknown"
    say "    编译 Caelestia QML 插件（约 1-3 分钟），version=$_cv rev=${_rev:0:7}"
    # -DENABLE_MODULES=plugin 是必须的。上游默认编 extras;plugin;shell，
    # shell 会 add_subdirectory 整个桌面应用。我们只要 plugin/ 下的 QML 模块，
    # 不限定会白编一个用不到的 shell。
    local _cmake_args=(
        -S "$src" -B "$build" -G Ninja
        -DCMAKE_BUILD_TYPE=RelWithDebInfo
        -DENABLE_MODULES=plugin
        -DVERSION="${_cv#v}" -DGIT_REVISION="$_rev"
    )
    cmake "${_cmake_args[@]}" \
        || die "Caelestia 插件 CMake 配置失败，见上方输出。"
    cmake --build "$build" --parallel \
        || die "Caelestia 插件编译失败，见上方输出。手动重试：cmake ${_cmake_args[*]} && cmake --build $build"

    # 产物自检。少了它，一次没真正产出的编译会写下 stamp，
    # 下一轮被当成已编译跳过，插件永远不存在且静默。
    if ! compgen -G "$build/qml/Caelestia/*.so" >/dev/null; then
        die "编译结束但 $build/qml/Caelestia/*.so 不存在 —— 插件没有真正产出，见上方 cmake 输出。"
    fi
    printf '%s\n' "$ovl_hash" > "$stamp"
    echo "    编译完成: $build/qml（由 fish/config.fish 与 start_quickshell.sh 自动加载）"
}

install_end4pc_shell() {
    local dst="$HOME/.config/quickshell/end4-pC"
    # 先清 .git：即使底盘完整提前 return，历史上误拷进来的 .git
    # 也该走，它只会占空间并被快照整包打包。
    cleanup_stray_git "$dst"
    # || true 不能省：赋值语句的退出码取自命令替换，
    # end4pc_base_missing 返回 1（完整）会让整个赋值非零退出。
    local missing=""
    if [[ -e "$dst/shell.qml" ]]; then
        missing="$(end4pc_base_missing || true)"
        if [[ -z "$missing" ]]; then
            echo "    已存在且完整: $dst"
            return 0
        fi
        warn "底盘不完整（缺少 $missing），重新拉取一份覆盖"
        warn "  旧目录已在 [0/7] 的 pre-install 快照里（$SNAP_ROOT），"
        warn "  需要还原时跑：./install.sh rollback"
    fi
    say "    拉取 quickshell 底盘 (pctrade/end4-PC)"
    # 不能直接 clone 进 $dst：目录非空时 git clone 失败，
    # set -e 会中断整个安装。先克隆到临时目录再合并。
    local tmp; tmp="$(mktmpd)"
    if git clone --depth=1 https://github.com/pctrade/end4-pC.git "$tmp/end4-PC"; then
        merge_clone_into "$tmp/end4-PC" "$dst"
        # 覆盖后立刻自检。基准是刚 clone 下来的那份而非硬编码清单，
        # 且必须在 rm -rf "$tmp" 之前取值。
        missing="$(base_tree_missing "$tmp/end4-PC" "$dst" || true)"
    else
        rm -rf "$tmp"
        die "拉取 quickshell 底盘失败（检查网络后重试，或手动 clone 到 $dst）"
    fi
    rm -rf "$tmp"
    if [[ -n "$missing" ]]; then
        die "底盘拉取后仍缺少 $missing —— 请检查网络与磁盘空间后重跑。"
    fi
    echo "    底盘完整"
}

install_caelestia_shell() {
    local dst="$HOME/.config/quickshell/caelestia"
    # 同 install_end4pc_shell：先清掉可能存在的历史遗留 .git
    cleanup_stray_git "$dst"
    if [[ -f "$dst/shell.qml" ]]; then
        echo "    已存在: $dst"
        return 0
    fi
    say "    拉取 caelestia shell 本体"
    # 同 end4-PC：目录可能已存在且非空，先克隆到临时目录再合并。
    local tmp; tmp="$(mktmpd)"
    if git clone --depth=1 https://github.com/caelestia-dots/shell.git "$tmp/shell"; then
        merge_clone_into "$tmp/shell" "$dst"
    else
        rm -rf "$tmp"
        die "拉取 caelestia shell 失败（检查网络后重试，或手动 clone 到 $dst）"
    fi
    rm -rf "$tmp"
    [[ -f "$dst/shell.qml" ]] || die "caelestia shell 本体仍然缺失：$dst/shell.qml"
    echo "    已拉取: $dst"
}

# [6/7] 运行环境与歌词缓存（外部命令密集：curl 下载 / fc-cache / venv / pip）。
# 参数 $1 = 1 表示装字体（对应 FONTS=1），0 表示跳过。
dotctl_setup_runtime() {
    local fonts_wanted="$1"
    FONTS="$fonts_wanted"
# 霞鹜臻楷 GB：serif 首选字体，AUR 无包，只能从 GitHub Release 取。
# 放在 fc-cache 之前，装完当次进缓存。FONTS=0 时跳过。
if fonts_enabled; then
    lxgw_zhenkai="$HOME/.local/share/fonts/LXGWZhenKaiGB-Regular.ttf"
    if [[ ! -e "$lxgw_zhenkai" ]]; then
        mkdir -p "$HOME/.local/share/fonts"
        if have curl && curl -fsSL --retry 3 -o "$lxgw_zhenkai" \
            https://github.com/lxgw/LxgwZhenKai/releases/download/v0.825/LXGWZhenKaiGB-Regular.ttf; then
            echo "    已下载霞鹜臻楷 GB（serif 首选字体）"
        else
            rm -f "$lxgw_zhenkai"
            warn "霞鹜臻楷 GB 下载失败；serif 会回退到霞鹜文楷屏幕阅读版"
        fi
    fi
fi

# pacman 装字体有 hook 会跑 fc-cache，这里兜底一次，
# 让手动放进 ~/.local/share/fonts/ 的字体也能生效。
if have fc-cache; then
    fc-cache -f >/dev/null 2>&1 || true
    echo "    字体缓存已刷新（fc-cache -f）"
fi
# 65-wqy-zenhei.conf 编号 65，晚于用户的 50-user.conf，用 <prefer> 把文泉驿
# 顶到 serif/sans-serif/monospace 最前，压制 ~/.config/fontconfig 的设置。
#
# 只在装推荐字体时才动：FONTS=0 时文泉驿是唯一的中文兜底，禁掉更糟。
# 改名禁用而不是 rm：/etc 是整机共享的，且删除不可逆。
wqy_conf="/etc/fonts/conf.d/65-wqy-zenhei.conf"
if fonts_enabled && [[ -e $wqy_conf ]]; then
    if "${SUDO:-sudo}" mv -f "$wqy_conf" "$wqy_conf.disabled-by-dotfiles" 2>/dev/null; then
        have fc-cache && fc-cache -f >/dev/null 2>&1 || true
        echo "    已禁用 /etc/fonts/conf.d/65-wqy-zenhei.conf（避免劫持 serif/中文字体）"
        echo "    恢复：sudo mv $wqy_conf.disabled-by-dotfiles $wqy_conf"
    else
        warn "未能禁用 65-wqy-zenhei.conf（需要 root）；serif 别名可能仍被文泉驿占用"
    fi
fi
mkdir -p "$HOME/.cache/quickshell/kugou_lyrics"
VENV="$HOME/.local/state/quickshell/.venv"
if [[ ! -x "$VENV/bin/python" ]]; then
    mkdir -p "$HOME/.local/state/quickshell"
    python -m venv "$VENV" \
        || die "创建 Python venv 失败（$VENV）。检查 python 是否完整（pacman -Q python）与磁盘是否可写。"
fi
# pypinyin                启动器的中文名拼音搜索
# dbus-python             同上，走 D-Bus 拿窗口与应用信息
# kde-material-you-colors KDE/Qt 取色。switchwall.sh 调的 wrapper 用
#   command -v 探测它，是 pip 包不是系统包。缺了 KDE/Qt 配色会静默跳过。
"$VENV/bin/pip" install --upgrade --quiet pypinyin dbus-python kde-material-you-colors \
    || warn "venv 依赖安装失败——启动器的 app 中文名拼音搜索、KDE/Qt 取色会受影响，其余功能不受影响"

# 触发一次 matugen 渲染，让新机器装完就有图标主题，不用等用户换壁纸。
# switchwall.sh 只存在于 end4-PC 底盘；caelestia 与 DMS 在首次换壁纸时自行触发。
if [[ "$QS_SHELL" == "end4-pC" && -f "$HOME/.config/illogical-impulse/config.json" ]]; then
    nohup bash "$HOME/.config/quickshell/end4-pC/scripts/colors/switchwall.sh" --noswitch \
        >/dev/null 2>&1 &
    echo "    已触发一次 matugen 渲染（后台执行，图标主题会随之生成）"
fi

# ---------- QML 模块依赖自检 ----------
# QML 模块缺失不会让 shell 启动失败，只会让那个文件 unavailable，
# 引用它的组件连带消失，日志里只有一行 WARN scene。
#
# 这类缺失在装过 Plasma 的机器上不会暴露（被全家桶补上），只有纯净安装才看得见。
#
# 只对 quickshell 会话跑，dms 不用这些模块。
if [[ "$QS_SHELL" != "dms" && -x "$SRC/check-qml-deps.py" ]]; then
    local qml_report qml_rc
    qml_report="$("$SRC/check-qml-deps.py" --quiet 2>&1)"
    qml_rc=$?
    if (( qml_rc != 0 )); then
        echo
        warn "QML 模块依赖不全 —— 下面这些组件启动后会静默消失（不会报错）"
        printf '%s\n' "$qml_report"
        echo
        warn "装上补救命令里的包后重跑本脚本，或手动再跑：$SRC/check-qml-deps.py"
    else
        echo "    QML 模块依赖自检：齐全"
    fi
fi

# ---------- [7/7] 完成 ----------
}

# [7/7] 收尾指引（纯文本输出）
dotctl_install_outro() {
# 第 1 步与所选合成器相关，单独输出
if [[ "$COMPOSITOR" == "niri" ]]; then
    echo "  1. 注销并重新登录，会话选择 \"niri\""
    echo "     （配置入口 ~/.config/niri/config.kdl；DMS 由 niri 的"
    echo "      spawn-at-startup 自启，登录界面为 plasmalogin）"
else
    echo "  1. 注销并重新登录，会话选择 \"Hyprland\""
    echo "     （配置入口 ~/.config/hypr/hyprland.lua，Quickshell 随会话自启）"
fi
cat <<'EOF'
  2. 中文输入：fcitx5 + rime（SUPER+F1 可重启输入法）
  3. 键位速览：
       SUPER+L      锁屏
       SUPER+T      终端召唤（居中浮动，再按隐藏）
       SUPER+S      scratchpad
       SUPER        启动器（支持中文拼音搜索）
  4. 桌面歌词开关：设置 → 桌面 → 小部件
     （桌面歌词已解耦，自动适配 KA Music / Spotify / 浏览器等任意播放器）
  5. fish 设为默认 shell（可选）: chsh -s "$(command -v fish)"
EOF
# 第 6 条按所选 shell 输出（三套各不相同）
case "$QS_SHELL" in
    caelestia)
        cat <<'EOF'
  6. Caelestia QML 插件：已编译到 ~/src/caelestia-build/qml，
     由会话自启（start_quickshell.sh 注入 QML2_IMPORT_PATH）与 fish config.fish 自动加载。
EOF
        ;;
    dms)
        cat <<'EOF'
  6. DMS（DankMaterialShell）：由 niri 自启，配置在 ~/.config/DankMaterialShell，
     键位见 ~/.config/niri/dms/binds.kdl，插件在 ~/.config/DankMaterialShell/plugins。
EOF
        ;;
    *)
        cat <<'EOF'
  6. Caelestia QML 插件：已编译到 ~/src/caelestia-build/qml（end4-PC 锁屏
     （Caelestia 风格）硬依赖它），由 start_quickshell.sh 与 fish config.fish
     通过 QML2_IMPORT_PATH 自动加载。
     end4-PC 岛屿 + 仪表盘：栏中央那颗胶囊，点一下从 Bar 里生长成面板，
     Home / System / Weather / GitHub 四页。
     想增删：设置 → 栏 → 组件列表里的「Island」（删掉即整座岛隐藏）。
     命令行：qs -c end4-pC ipc call islanddashboard toggle
     锁屏依赖的 Caelestia QML 插件已编译到 ~/src/caelestia-build/qml，
     手动跑 qs 前请先在 fish 里开个新终端（config.fish 自动注入
     QML2_IMPORT_PATH），或 export QML2_IMPORT_PATH=~/src/caelestia-build/qml。
     ⚠ 插件缺失时 shell 不再整体起不来：面板族里的 Lock / IslandHost 已改成
       运行时创建（panelFamilies/CaelestiaPluginProbe.qml 探针），只会少锁屏
       与灵动岛，其余面板照常。qs 输出里搜「Caelestia QML 插件不可用」确认。
EOF
        ;;
esac
cat <<'EOF'
  7. 键盘按键显示（可选，默认关闭）：需要读 /dev/input/event*，把当前用户
     加进 input 组后重新登录，再到 设置 → 桌面 → 按键显示 打开开关：
       sudo usermod -aG input "$USER"
     用 id -nG 确认组已生效。没加组也能装，只是开关打开后读不到按键。
  8. 图标主题：WhiteSur（AUR whitesur-icon-theme）为底盘，文件夹由 matugen
     自动着色（换壁纸时重渲），主题名为 WhiteSur-Matugen-A / WhiteSur-Matugen-B
     （交替）。想手动换：设置 → 外观 → 图标主题。
EOF
}

# 未找到 AUR helper 时引导安装 yay。
dotctl_bootstrap_yay() {
    local tmpdir; tmpdir="$(mktmpd)"
    git clone --depth=1 https://aur.archlinux.org/yay.git "$tmpdir/yay" || {
        warn "克隆 yay 失败（检查网络后重试；也可先手动安装 paru/yay）"
        rm -rf "$tmpdir"; return 1
    }
    (cd "$tmpdir/yay" && makepkg -si --noconfirm) || {
        warn "yay 编译/安装失败，见上方输出。手动装好 paru 或 yay 后重跑即可跳过本步。"
        rm -rf "$tmpdir"; return 1
    }
    rm -rf "$tmpdir"
    return 0
}

# 按会话分发 shell 本体安装。
dotctl_install_shell() {
    case "$1" in
        caelestia) install_caelestia_shell ;;
        dms)       echo "    DMS 由 AUR 安装（dms-shell-git + dms-shell-niri），无需额外部署" ;;
        *)         install_end4pc_shell ;;
    esac
}

# 选会话并把结果**打印出来**给 Python 侧回读。
#
# ⚠ 为什么需要这个：choose_session 会把结果写进 bash 变量 QS_SHELL /
#   COMPOSITOR，而 dotctl 是独立进程 —— 子进程里设的变量父进程看不到。
#   直接调 choose_session 的话，Python 侧读 os.environ['QS_SHELL'] 永远是空，
#   于是 [4/7] 打印「桌面 Shell（）」、shell 分支也走错。
#   这里在同一个 bash 进程里选完再输出，Python 解析最后一行。
#   交互提示仍直接进终端（stdout 不捕获），结果走 stderr 之外的一行。
dotctl_choose_session() {
    choose_session
    printf 'DOTCTL_SESSION=%s|%s\n' "${QS_SHELL:-}" "${COMPOSITOR:-}" >&2
}

# 批量判定哪些 rel 该按会话跳过。
# ⚠ 逐条 fork 太慢（源树上千个文件 × 两次 fork），所以一次问完整份清单。
#   两个 skip_by_* 读的是 bash 变量（COMPOSITOR / QS_SHELL /
#   INSTALL_BOTH_COMPOSITORS），Python 侧看不到 —— 必须在这边判。
# 输入：stdin 逐行 rel；输出：该跳过的 rel 逐行。
dotctl_skip_rels() {
    local rel
    while IFS= read -r rel; do
        [[ -z $rel ]] && continue
        if skip_by_compositor "$rel" || skip_by_shell "$rel"; then
            printf '%s\n' "$rel"
        fi
    done
}
