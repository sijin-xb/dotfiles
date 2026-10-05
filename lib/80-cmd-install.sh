# ============================================================
# 子命令 install（原 §3）
# ============================================================
# ============================================================
# 3. 安装（7 步流程，封装进 cmd_install）
# ============================================================
cmd_install() {
    # install 不接收位置参数；多打了参数（如 install niri）多半是想表达
    # SESSION —— 提醒正确的用法，静默忽略会让人以为参数生效了。
    if (($#)); then
        warn "install 不接受参数，已忽略: $*（选会话请用 SESSION=dms|caelestia|end4pc $0 install）"
    fi
    [[ -f /etc/arch-release ]] || die "本安装器仅支持 Arch Linux 系发行版（CachyOS / Arch 等）。"
    [[ ${EUID} -eq 0 ]] && die "请勿用 root 运行（makepkg/AUR 步骤需要普通用户）。"
    have pacman || die "找不到 pacman。"

    ensure_repo "$@"          # 单文件运行时自举拉仓库并 exec 重跑
    ensure_dirs
    session_warning_if_running

    # 关键：在部署之前先保存原始配置快照（回档的基础）
    say "[0/7] 安装前自动保存当前配置快照（回档用）"
    snapshot_current "$PRE_INSTALL_PREFIX" current || warn "创建 pre-install 快照失败（可继续安装，但 rollback 将不可用）"

    # ---------- [1/7] 基础工具 + 会话依赖（一次 pacman 搞定） ----------
    say "[1/7] 安装基础工具与会话依赖"
    # 合成器本体与 portal 由 choose_session 的结果决定，单独追加到最后
    choose_session
    choose_fonts
    # 固定列表见 fixed_pacman_pkgs()（抽成函数是为了让 update 复用同一份）。
    # 每个包的「为什么必须要」也记在那里。
    mapfile -t PACMAN_PKGS < <(fixed_pacman_pkgs)
    # 追加合成器相关包（niri 或 hyprland + 对应 portal）
    # shellcheck disable=SC2207
    PACMAN_PKGS+=($(compositor_pkgs))
    say "    合成器相关包: $(compositor_pkgs)"
    # 追加 shell 专属包（dms 的录屏工具；caelestia / end4-pC 无）
    local _shell_pkgs; _shell_pkgs="$(shell_pacman_pkgs)"
    if [[ -n "$_shell_pkgs" ]]; then
        # shellcheck disable=SC2207
        PACMAN_PKGS+=($_shell_pkgs)
        say "    $QS_SHELL 专属包: $_shell_pkgs"
    fi
    # 追加 quickshell 会话公共包（Caelestia 插件编译 / 运行依赖）。
    # ⚠ end4-pC 也编这个插件（锁屏硬依赖），所以不在 shell 分支里。
    local _base_pkgs; _base_pkgs="$(base_pacman_pkgs)"
    if [[ -n "$_base_pkgs" ]]; then
        # shellcheck disable=SC2207
        PACMAN_PKGS+=($_base_pkgs)
        say "    Caelestia 插件依赖: $_base_pkgs"
    fi
    # 字体包是可选项（见 choose_fonts）：不想被塞 200MB+ 的字体链就 FONTS=0。
    #   ttf-jetbrains-mono-nerd  kitty 终端的 Nerd 图标
    #   noto-fonts-cjk           按语言切换 CJK 字形的全部地区变体（JP/KR/TC/HK），
    #                            装包本身会自动 fc-cache
    #   adobe-source-han-sans-cn 思源黑体 CN：不再走 fontconfig 别名，但 GTK
    #                            settings.ini 与 fcitx5 classicui.conf 硬编码了它
    if fonts_enabled; then
        # 字体包列表见 font_pacman_pkgs()（见 choose_fonts）：不想被塞 200MB+ 的
        # 字体链就 FONTS=0。
        local _font_pkgs
        mapfile -t _font_pkgs < <(font_pacman_pkgs)
        PACMAN_PKGS+=("${_font_pkgs[@]}")
        say "    字体（pacman）: Nerd Mono / Noto CJK / 思源黑体"
    else
        say "    字体: 已跳过（FONTS=0），不安装任何系统字体包"
    fi
    # 默认只安装缺失的包，不做全系统升级（避免在你没准备时滚动整个系统）。
    # 需要全量升级时：FULL_UPGRADE=1 ./install.sh install
    if [[ "${FULL_UPGRADE:-0}" == "1" ]]; then
        say "    FULL_UPGRADE=1：执行全系统升级（pacman -Syu）"
        "${SUDO:-sudo}" pacman -Syu --needed --noconfirm "${PACMAN_PKGS[@]}" \
            || die "全系统升级失败。常见原因是镜像未同步或密钥过期：先手动执行 sudo pacman -Syu && sudo pacman -S archlinux-keyring 后重试。"
    else
        "${SUDO:-sudo}" pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}" \
            || die "依赖安装失败。若提示找不到包，先手动执行 sudo pacman -Syu 更新软件库后重试。"
    fi

    # ---------- [2/7] AUR 包（通用 + 所选 shell 专属） ----------
    say "[2/7] AUR 依赖"
    if ! have yay && ! have paru; then
        say "    未找到 AUR helper，引导安装 yay（编译约 1-2 分钟，需要 base-devel）"
        tmpdir="$(mktmpd)"
        git clone --depth=1 https://aur.archlinux.org/yay.git "$tmpdir/yay" \
            || die "克隆 yay 失败（检查网络后重试；也可先手动安装 paru/yay，装好后重跑会跳过本步）"
        (cd "$tmpdir/yay" && makepkg -si --noconfirm) \
            || die "yay 编译/安装失败，见上方输出。手动装好 paru 或 yay 后重跑即可跳过本步。"
        rm -rf "$tmpdir"
    fi
    # 通用 AUR 包：
    #   matugen                壁纸 → Material 3 全局取色
    #   mpvpaper               视频壁纸
    #   walker                 Hyprland 侧的启动器/剪贴板前端。三处都依赖它：
    #                            hypr/custom/keybinds.lua  SUPER+V → `walker -m clipboard`
    #                            hypr/hyprland/rules.lua   layer rule（namespace="walker"）
    #                            matugen/config.toml       [templates.walker] → ~/.config/walker/themes/matugen
    #                          缺了就是「SUPER+V 按了没反应」+ walker 主题目录不存在。
    # catppuccin-sddm-theme-mocha：SDDM 登录界面主题（Qt6，需 SDDM 走 Wayland）
    # qt6-svg / qt6-declarative / qt5-quickcontrols2 是它的依赖，AUR 包会带入。
    # catppuccin-cursors-mocha：光标主题模板源。generate_cursor_theme.py 以
    #   catppuccin-mocha-pink-cursors 为底、按 matugen 主色重着色生成
    #   ~/.local/share/icons/Matugen-Cursors（环境里 XCURSOR_THEME 引用的就是它）。
    #   缺了脚本直接 "generation failed"，光标永远回退默认。
    # 固定 AUR 列表见 fixed_aur_pkgs()。
    mapfile -t AUR_PKGS < <(fixed_aur_pkgs)
    # 字体链（可选，见 choose_fonts；偏好链在 ~/.config/fontconfig/fonts.conf）：
    #   otf-misans             sans-serif 默认（MiSans）
    #   maplemononormal-nf-cn  monospace 默认（自带 Nerd 图标 + 中文）
    #   ttf-lxgw-wenkai-screen serif 回退链第二位
    #   ttf-lxgw-wenkai-tc     繁中衬线（lang=zh-tw / zh-hk 时启用）
    #   ttf-lxgw-wenkai        楷体，供硬编码霞鹜文楷的组件回退
    # ⚠ AUR 包名不规则：上游 README 写的 ttf-maplemononormal-nf-cn 并不存在，
    #   实际是 maplemononormal-nf-cn（无 ttf- 前缀）。
    if fonts_enabled; then
        local _font_aur
        mapfile -t _font_aur < <(font_aur_pkgs)
        AUR_PKGS+=("${_font_aur[@]}")
        say "    字体（AUR）  : MiSans / Maple Mono NF / 霞鹜文楷三兄弟"
    fi
    # 追加合成器本体的 AUR 包（见 compositor_aur_pkgs：
    #   niri → niri-shorin-fork-git，hyprland → 官方仓库已装，无）
    local _comp_aur; _comp_aur="$(compositor_aur_pkgs)"
    if [[ -n "$_comp_aur" ]]; then
        # fork 声明 conflicts niri，所以官方 niri / niri-bin / niri-spicy-git
        # 在的话 AUR helper 会因冲突直接失败（且 --noconfirm 下无法自动确认卸载）。
        # 这里只提示不代劳：卸载合成器会停掉当前会话，得你自己决定时机。
        # 用 -Rdd 是为了不连带卸掉依赖 niri 的 dms-shell-niri。
        local _conflict
        for _conflict in niri niri-bin niri-spicy-git; do
            if pacman -Q "$_conflict" >/dev/null 2>&1; then
                warn "已装 $_conflict，与 $_comp_aur 冲突（conflicts niri）"
                say "    先卸掉再继续：sudo pacman -Rdd $_conflict"
                say "    （-Rdd 跳过依赖检查，避免连带卸掉 dms-shell-niri）"
            fi
        done
        # shellcheck disable=SC2207
        AUR_PKGS+=($_comp_aur)
        say "    合成器本体（AUR）: $_comp_aur"
    fi
    # 追加 shell 专属 AUR 包（见 shell_aur_pkgs：
    #   caelestia → 无（与 end4-pC 共用公共列表）
    #   dms       → dms-shell-git dms-shell-niri）
    # shellcheck disable=SC2207
    AUR_PKGS+=($(shell_aur_pkgs))
    # quickshell 会话公共 AUR 包（libcava / qt6-m3shapes-git）。
    # ⚠ end4-pC 也需要：Caelestia 插件编译 + 锁屏 MaterialShape 形变动画。
    # shellcheck disable=SC2207
    AUR_PKGS+=($(base_aur_pkgs))
    for p in "${AUR_PKGS[@]}"; do
        if pacman -Q "$p" >/dev/null 2>&1; then
            echo "    已安装: $p"
        elif aur_install "$p"; then
            echo "    AUR 安装成功: $p"
        else
            warn "$p 安装失败（不影响其余功能，可稍后手动安装）"
        fi
    done
    have fcitx5 || warn "fcitx5 未就绪，中文输入暂不可用（fcitx5-rime 依赖应已带入）"

    # ---------- [3/7] quickshell 三级回退 ----------
    say "[3/7] quickshell"
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
    install_quickshell
    have qs || die "quickshell 安装失败，请检查上方输出。"

    # ---------- [4/7] 桌面 Shell（按 choose_session 的结果三选一） ----------
    say "[4/7] 桌面 Shell（$QS_SHELL）"

    # ---------- [4a/7] Caelestia QML 插件（end4-pC 与 caelestia 都需要） ----------
    #
    # ⚠ 这不是 caelestia 专属步骤 —— 它是 end4-pC 的硬前置。
    #
    # end4-pC 差异层里的锁屏（modules/ii/lock/caelestia/**）是从
    # caelestia-dots/shell 原样 vendor 过来的，其中 **56 个文件**写着
    # `import Caelestia.Config`（Tokens.anim.* / AnimCurves）。QML 的
    # `import <模块>` 是硬依赖：模块解析不到时，该文件里的类型全部 unavailable，
    # 错误沿
    #     CaelestiaLockSurface → Lock → IllogicalImpulseFamily → shell.qml
    # 一路上抛，最终 `qs -c end4-pC` 直接 "Failed to load configuration"，
    # 表现为**登录后桌面残缺或只剩光标**。
    #
    # 历史写法是按 $QS_SHELL 分支决定编不编这个插件（只在 caelestia 分支编），
    # 于是选 end4-pC 的机器永远拿不到插件 —— 这就是本次要修的 bug。
    #
    # 插件 QML 源码在 caelestia-dots/shell 仓库的 plugin/ 下；本仓库的覆盖层
    # （dot_config/quickshell/caelestia/）提供汉化 po 与改过的 CMakeLists。
    # 所以这里无论如何都要：拿到源码 → 应用覆盖层 → out-of-source 编译到
    # $HOME/src/caelestia-build。
    #
    # ── 存放规则（单一事实来源，改这里要连带改下面这张表的所有读者）──────
    #
    #   | 用途                | 路径                              | 谁写      | 进快照/归档 |
    #   |---------------------|-----------------------------------|-----------|-------------|
    #   | 编译源码（构建输入）| ~/src/caelestia-plugin-src        | [4a/7]    | 否          |
    #   | 编译产物（QML 模块）| ~/src/caelestia-build/qml         | [4a/7]    | 否          |
    #   | 覆盖层（仓库内）    | dot_config/quickshell/caelestia/  | 仓库      | —           |
    #   | end4-PC shell 配置  | ~/.config/quickshell/end4-pC      | [4b/7]+[5/7] | 是       |
    #   | caelestia shell 配置| ~/.config/quickshell/caelestia    | [4b/7]+[5/7] | 是       |
    #
    # 两条硬规则：
    #   1. **源码与产物都在 $HOME/src，不在 $HOME/.config/quickshell 下。**
    #      后者是 quickshell 的配置命名空间（quickshell 按
    #      `<config>/quickshell/<名字>/shell.qml` 发现配置），往里放 clone 等于
    #      凭空多出一套可运行的 shell（`qs -c caelestia`），而且会被
    #      SNAP_PATHS / EXTRA_ARCHIVE_PATHS 整包打进快照与归档。
    #      旧版本正是把源码放在 ~/.config/quickshell/caelestia（复用 caelestia
    #      shell 的 clone），既污染命名空间，又让"哪些文件是配置、哪些是构建
    #      输入"彻底糊在一起。
    #   2. **只有 ~/src/caelestia-build/qml 会被 QML2_IMPORT_PATH 指向。**
    #      读者只有两处：fish/config.fish（手动跑 qs）与
    #      hyprland/scripts/start_quickshell.sh（会话自启）。
    #      换位置要同步改那两处 —— 以前注释里还写着 execs.lua，早就不存在了。
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
        local overlay="$SRC/dot_config/quickshell/caelestia"
        local ovl_hash=""
        if [[ -d "$overlay" ]]; then
            while IFS= read -r -d '' rel; do
                mkdir -p "$src/$(dirname "${rel#./}")"
                cp -a "$overlay/$rel" "$src/${rel#./}"
            done < <(cd "$overlay" && find . -type f -print0)
            ovl_hash="$(cd "$overlay" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16)"
            echo "    已应用 caelestia 覆盖层（$(cd "$overlay" && find . -type f | wc -l) 个文件）"
        fi

        # 3) 编译。幂等：已有 .so 产物**且覆盖层没变**才跳过 —— 否则改了
        #    po/CMakeLists 却不重编，会静默停留在旧版本。
        local stamp="$build/.overlay-stamp"
        if compgen -G "$build/qml/Caelestia/*.so" >/dev/null \
            && [[ -f "$stamp" && "$(cat "$stamp")" == "$ovl_hash" ]]; then
            echo "    已编译: $build/qml（覆盖层无变化）"
            return 0
        fi

        # 3a) 构建目录与源码路径必须配对。
        #     CMakeCache.txt 里记着 CMAKE_HOME_DIRECTORY（= 上次 -S 的源码目录）。
        #     源码位置换过（旧版本是 ~/.config/quickshell/caelestia）之后直接复用
        #     旧构建目录，CMake 会拿缓存里的老路径去找 CMakeLists —— 表现为
        #     "配置失败" 或更糟：配置通过、链接到已删除的目标文件。
        #     检测到不匹配就整个清掉重配。这也是"编译流程与存放规则一致"的一部分：
        #     源码路径是这条链的单一事实来源，改它必须连带作废旧构建。
        if [[ -f "$build/CMakeCache.txt" ]]; then
            local _cached_src
            _cached_src="$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "$build/CMakeCache.txt" | head -1)"
            if [[ -n "$_cached_src" && "$_cached_src" != "$src" ]]; then
                warn "构建目录的源码路径已变（$_cached_src → $src），清空后重新配置"
                rm -rf "$build"
            fi
        fi

        have cmake && have ninja || die "缺少 cmake/ninja，无法编译 Caelestia 插件（end4-pC 锁屏硬依赖）。"
        # 上游 CMakeLists 对 git 有硬依赖：`git describe --tags` 拿 VERSION、
        # `git rev-parse HEAD` 拿 GIT_REVISION，任一为空就 FATAL_ERROR 中断安装。
        # shallow clone 默认没有 tag；源码若是被拷进来的（无 .git）两个都拿不到。
        # 所以两个变量都由这里显式算出并传入，CMakeLists 的 git 调用就走不到了。
        ( cd "$src" && git fetch --tags --depth=1 --quiet 2>/dev/null ) || true
        local _cv="" _rev=""
        _cv="$(cd "$src" && git describe --tags --abbrev=0 2>/dev/null || true)"
        _rev="$(cd "$src" && git rev-parse HEAD 2>/dev/null || true)"
        [[ -z "$_cv" ]] && _cv="0.0.0"
        [[ -z "$_rev" ]] && _rev="unknown"
        say "    编译 Caelestia QML 插件（约 1-3 分钟），version=$_cv rev=${_rev:0:7}"
        # ⚠ -DENABLE_MODULES=plugin 是必须的，不是优化：
        #   上游根 CMakeLists 默认 ENABLE_MODULES="extras;plugin;shell"，
        #   其中 shell 会 add_subdirectory 整个 caelestia shell 应用
        #   （assets/components/modules/services/utils）。我们要的只是 QML 模块
        #   （Caelestia.Config / .Services / .Components / .Images / .Models /
        #   .Blobs / .I18n），它们全在 plugin/ 下，与 shell/ 无依赖关系。
        #   不限定的话会白编一个用不到的桌面 shell，多花几分钟，还多一堆
        #   只有 shell 才需要的依赖。
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

        # 3b) 产物自检。没有它的话，一次"看起来成功但没产出"的编译会把 stamp
        #     写下去，下一轮直接被当成"已编译"跳过 —— 插件对 qs 而言永远不存在，
        #     而且是静默的。
        if ! compgen -G "$build/qml/Caelestia/*.so" >/dev/null; then
            die "编译结束但 $build/qml/Caelestia/*.so 不存在 —— 插件没有真正产出，见上方 cmake 输出。"
        fi
        printf '%s\n' "$ovl_hash" > "$stamp"
        echo "    编译完成: $build/qml（由 fish/config.fish 与 start_quickshell.sh 自动加载）"
    }

    # end4-PC 底盘（end-4 illogical-impulse 定制 fork，pctrade/end4-PC）：
    # 本仓库只跟踪差异层（dot_config/quickshell/end4-pC），底盘本体从这里拉。
    # 完整性自检见顶层函数 end4pc_base_missing()（放在顶层是为了能单独测）。
    install_end4pc_shell() {
        local dst="$HOME/.config/quickshell/end4-pC"
        # 无条件先清：即使底盘判定为"完整"而提前 return，历史上误拷进来的
        # .git 也该走（它从来没被用过，只会占空间并被快照整包打包）。
        cleanup_stray_git "$dst"
        # ⚠ 命令替换里 set -e 不生效，但赋值语句的退出码取自替换结果，
        #   所以 `|| true` 不能省：end4pc_base_missing 返回 1（=完整）时
        #   会让 `missing=...` 整体非零退出。
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
        # 注意：不能直接 clone 进 $dst —— 目录已存在且非空时 git clone 会失败，
        # 而 set -e 会让整个安装中断。先克隆到临时目录再合并进去。
        local tmp; tmp="$(mktmpd)"
        if git clone --depth=1 https://github.com/pctrade/end4-pC.git "$tmp/end4-PC"; then
            merge_clone_into "$tmp/end4-PC" "$dst"
            # 覆盖完立刻自检：网络中断 / 磁盘满都可能让 cp 半途而废，
            # 别让用户拿到一个"看起来装好了"的残缺树。
            # ⚠ 基准是刚 clone 下来的那份（而不是硬编码清单），并且必须在
            #   `rm -rf "$tmp"` 之前取值。
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

    # caelestia shell：本体 clone（QML 插件由 [4a/7] install_caelestia_plugin 统一处理）。
    #
    # ⚠ 这是**唯一**应该出现在 ~/.config/quickshell/ 下的东西，且只在选了
    #   caelestia 时才 clone。[4a/7] 现在把插件源码放在 $HOME/src，不再顺带
    #   往这里塞 clone，所以本体得自己拉。
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

    install_shell() {
        case "$QS_SHELL" in
            caelestia) install_caelestia_shell ;;
            dms)       echo "    DMS 由 AUR 安装（dms-shell-git + dms-shell-niri），无需额外部署" ;;
            *)         install_end4pc_shell ;;
        esac
    }
    # ⚠ 顺序：插件必须先于 shell 本体处理（end4-pC 的锁屏硬依赖它，见 [4a/7]）。
    #    dms 不走 quickshell，跳过 —— 不给纯 niri 用户多拉一份 caelestia 源码。
    if [[ "$QS_SHELL" != "dms" ]]; then
        install_caelestia_plugin
    fi
    install_shell

    # ---------- [5/7] 部署 dotfiles ----------
    say "[5/7] 部署配置文件"
    backup_dir="$BACKUP_ROOT/$(now_ts)"
    installed=0; backed=0; skipped=0; skipped_shell=0
    ignored_skip=0; ignored_keep=0
    DEPLOYED_RELPATHS=()
    # 遍历 + 过滤 + 部署 + 记录清单，全部收敛在 walk_sources/deploy_and_record
    # 里，和 update 共用同一份逻辑（避免两处各维护一遍过滤规则）。
    walk_sources deploy_and_record
    say "已部署 $installed 个文件；$backed 个有差异的旧文件备份于 $backup_dir"
    sync_wallpapers
    # 写部署清单与版本记录 —— update 靠它们做增量比对。
    # 首次 install 时清单是新建的；重跑 install 会覆盖成最新状态。
    manifest_write "${DEPLOYED_RELPATHS[@]}"
    record_revision
    echo "    部署清单: $(manifest_path)（${#DEPLOYED_RELPATHS[@]} 条）"
    if ((ignored_skip || ignored_keep)); then
        echo "    按 .chezmoiignore 跳过 $ignored_skip 个（缓存/字节码/插件元数据/UI 写回的配置）；"
        echo "    $ignored_keep 个运行时生成物已存在，保留当前值不覆盖（matugen 配色等）。"
        echo "    想强制用仓库快照覆盖它们：先删掉目标文件再重跑安装。"
    fi
    if ((skipped)); then
        if [[ "$COMPOSITOR" == "niri" ]]; then other=hypr; else other=niri; fi
        warn "已跳过 $skipped 个文件：未选择的另一套合成器 ~/.config/$other 原样保留，一个字节都没动。"
        warn "  想两套都部署：INSTALL_BOTH_COMPOSITORS=1 ./install.sh install"
    fi
    if ((skipped_shell)); then
        warn "已跳过 $skipped_shell 个文件：不属于所选 shell（$QS_SHELL）的差异层原样保留。"
    fi

    # ---------- [6/7] 拼音搜索环境与歌词缓存 ----------
    say "[6/7] 运行环境与歌词缓存"
    # 霞鹜臻楷 GB：serif 别名首选字体，AUR 没有对应包，只能从上游 GitHub Release
    # 取。放在 fc-cache 之前，装完当次就能进缓存；已存在则跳过（不重复下载 17MB）。
    # 与字体链绑定（见 choose_fonts）：FONTS=0 时一个字节都不下。
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

    # 字体缓存：pacman 装字体包时本身有 hook 会自动跑，这里再显式兜底一次，
    # 让用户手动放进 ~/.local/share/fonts/ 的字体在重跑脚本后也能生效。
    # 跳过字体时也跑：不动配置，只刷新缓存，对已有字体无副作用。
    if have fc-cache; then
        fc-cache -f >/dev/null 2>&1 || true
        echo "    字体缓存已刷新（fc-cache -f）"
    fi
    # 文泉驿的系统级配置（65-wqy-zenhei.conf）编号 65，晚于用户配置的
    # 50-user.conf 加载，会用 <prefer> 把文泉驿 / DejaVu 顶到
    # serif / sans-serif / monospace 最前面，压制 ~/.config/fontconfig 的设置。
    # 现在 sans-serif / serif / monospace 都有明确首选（MiSans / 霞鹜臻楷 / Maple Mono），
    # 文泉驿属于更低质量的兜底，去掉它。
    # 失败不影响安装。
    # ⚠ 只在装了推荐字体时才动：FONTS=0 时文泉驿是系统里唯一的中文兜底，
    #   禁掉会让中文衬线/无衬线直接掉回默认字体，比不动更糟。
    # ⚠ 这里曾经是 `rm -f`：删掉系统文件不可逆，而且 /etc 是**整机共享**的，
    #   隔壁 niri/DMS 那套会话、甚至其它用户都会跟着变 —— 安装脚本只该管
    #   自己的 $HOME。改成改名禁用：fontconfig 只加载 `*.conf`，
    #   后缀一变就不再生效，文件仍在，一条命令就能恢复。
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
    # pypinyin            → 启动器的 app 中文名拼音搜索
    # dbus-python         → 同上（走 D-Bus 拿窗口/应用信息）
    # kde-material-you-colors → KDE/Qt 取色。switchwall.sh 会调
    #   matugen/templates/kde/kde-material-you-colors-wrapper.sh，而那个 wrapper
    #   第 70 行是 `command -v kde-material-you-colors || 跳过` —— 它是个 **pip 包**
    #   不是系统包，以前 venv 里没装，于是 KDE/Qt 配色每次都被静默跳过
    #   （日志里只有一句 "not installed in venv, skipping"，很容易漏掉）。
    "$VENV/bin/pip" install --upgrade --quiet pypinyin dbus-python kde-material-you-colors \
        || warn "venv 依赖安装失败——启动器的 app 中文名拼音搜索、KDE/Qt 取色会受影响，其余功能不受影响"

    # 图标主题：WhiteSur-dark 提供全部图标，文件夹由 matugen 的
    # [templates.gtk-folder] 每次换壁纸重新着色（生成
    # ~/.local/share/icons/WhiteSur-Matugen-{A,B}，Inherits=WhiteSur-dark）。
    # 这里只负责触发一次，让新机器装完就有主题，不用等用户手动换壁纸。
    # switchwall.sh 是 end4-PC 底盘里的脚本，只有选了 end4-pC 才有；
    # caelestia / DMS 各自在首次换壁纸时触发 matugen，不需要这里代劳。
    if [[ "$QS_SHELL" == "end4-pC" && -f "$HOME/.config/illogical-impulse/config.json" ]]; then
        nohup bash "$HOME/.config/quickshell/end4-pC/scripts/colors/switchwall.sh" --noswitch \
            >/dev/null 2>&1 &
        echo "    已触发一次 matugen 渲染（后台执行，图标主题会随之生成）"
    fi

    # ---------- QML 模块依赖自检 ----------
    # QML 的模块依赖是运行时解析的：缺一个 import 不会让 shell 启动失败，只会让
    # 「那一个文件」unavailable，然后引用它的东西连带失败 —— 日志里只有一行
    # `WARN scene: ... unavailable`，没有 ERROR，肉眼看到的是「某个组件凭空消失」。
    # 历史上踩过两次：Caelestia 插件（锁屏整个加载不出来）、kirigami
    # （AppIcon.qml 的根类型就是 Kirigami.Icon → Bar 的 workspaces 消失）。
    #
    # 更麻烦的是这类缺失在**装过 KDE/Plasma 的机器上不会暴露**（被全家桶顺带补上），
    # 只有纯净安装才看得见。所以这里显式核一遍，把缺的包名和补救命令直接打出来。
    #
    # 只对 quickshell 会话跑：dms 不用 quickshell，没有这套 QML 模块。
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
    say "[7/7] 完成！接下来的步骤："
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

