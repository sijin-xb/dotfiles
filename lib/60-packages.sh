# ============================================================
# 包列表
# 各 *_pkgs() 只打印包名，装包流程在 cmd_install / update。
# ============================================================

# 官方仓库包：合成器本体 + 对应 portal。
# niri 本体不在这里，见 compositor_aur_pkgs。
compositor_pkgs() {
    case "$COMPOSITOR" in
        niri) echo "xdg-desktop-portal-gnome" ;;
        *)    echo "hyprland xdg-desktop-portal-hyprland" ;;
    esac
}

# 合成器本体的 AUR 包。
#
# niri-shorin-fork-git 提供本仓库 niri 配置依赖的扩展：magnifier、
# grid-overview、cursor shake-to-enlarge、screen-cast-picker 配色、单 Mod 键绑定。
# 换上游 niri 或 niri-spicy-git 会因未知配置项拒绝加载整份配置。
# 它 provides/conflicts niri，换装前先 sudo pacman -Rdd 旧包。
#
# 换分支时同步改这里，并按上述扩展增删 config/desktop/niri/ 里的节点，
# 改完跑 niri validate。
compositor_aur_pkgs() {
    case "$COMPOSITOR" in
        niri) echo "niri-shorin-fork-git" ;;
        *)    echo "" ;;
    esac
}

# 各 shell 专属的 AUR 包。
#
# libcava 与 qt6-m3shapes-git 放在 [2/7] 的公共列表（base_aur_pkgs），不按 shell 分支：
# libcava 是 Caelestia QML 插件的编译依赖，qt6-m3shapes-git 是锁屏形变动画的
# 运行时依赖。end4-PC 的锁屏从 caelestia vendor 而来，两者都需要。
#
# dms 用 -git 版：DMS 迭代快，稳定版落后几个小版本，niri 侧的 config.kdl 与
# dms/binds.kdl 按新版写，键位和 ipc 目标会对不上。
#
# nirius    niri/binds.kdl 有 4 个键位直接 spawn 它，缺了按键无反应且 niri 不报错
# awww-git  niri 侧静态壁纸后端。install.sh 只装 mpvpaper（视频壁纸），
#           没有 awww 时静态壁纸为空
#                    ⚠ 包名是 awww-git：AUR 上没有叫 awww 的包。
#
#   end4-PC: plasma6-themes-colloid-git 提供 Kvantum 的 Colloid 基底主题。
#            scripts/kvantum/materialQT.sh 把 material_colors.scss 重着色到
#            MaterialAdw（Colloid 的副本），没有基底就生成不了。
#            AUR 上没有只含 Kvantum 部分的 Colloid 包，只能装这个，
#            会顺带带上 aurorae / plasma / sddm 主题。
#            只有 end4-PC 需要，caelestia 没有 scripts/kvantum/ 链路。
shell_aur_pkgs() {
    case "$QS_SHELL" in
        caelestia) echo "" ;;
        end4-PC)   echo "plasma6-themes-colloid-git" ;;
        dms)       echo "dms-shell-git dms-shell-niri nirius awww-git" ;;
        *)         echo "" ;;
    esac
}

# quickshell 会话（end4-PC / caelestia）共用的 AUR 包，服务于 Caelestia 插件与锁屏。
# dms 不用 quickshell，跳过。
base_aur_pkgs() {
    case "$QS_SHELL" in
        dms) echo "" ;;
        *)   echo "libcava qt6-m3shapes-git" ;;
    esac
}

# 各 shell 专属的官方仓库包。
#
# aubio / libqalculate / libpipewire / lm_sensors / fftw / spirv-tools 是 Caelestia
# 插件的编译依赖（plugin/CMakeLists.txt 的 pkg_check_modules 缺一个就 FATAL_ERROR），
# end4-PC 也编这个插件，所以放在 base_pacman_pkgs。
#
# dms:  gpu-screen-recorder 是 DMS quickCapture 录屏带声音的前提，默认键位 Ctrl+Alt+R。
#       不装也能录，但回退到 wf-recorder（CPU 编码、无声音）。插件用 command -v 探测。
#
# end4-PC: kvantum + kvantum-qt5 是 Qt 的 SVG 主题引擎。取色链路末端
#       （switchwall.sh -> scripts/kvantum/materialQT.sh）把配色落到 MaterialAdw，
#       再由 kvantummanager 通知 Qt 应用重读。缺了 Qt 应用停在 Colloid 原色。
#
#       qt6-positioning / kirigami / syntax-highlighting 是 QML 模块依赖，
#       quickshell 不会带进来：
#         qt6-positioning      Weather.qml 的 import QtPositioning，缺了整个天气组件挂掉
#         kirigami             AppIcon.qml 的根类型是 Kirigami.Icon，缺了栏左侧工作区指示器消失
#         syntax-highlighting  aiChat/MessageCodeBlock.qml 的代码块高亮
#       本机看起来不缺是因为装了 Plasma 全家桶，纯净安装会缺。
#       不要挪进 base_pacman_pkgs：caelestia 不 import 这三个模块。
#       新增 import 后 [7/7] 会跑 check_qml_deps.py 扫出来。
shell_pacman_pkgs() {
    case "$QS_SHELL" in
        caelestia) echo "" ;;
        end4-PC)   echo "kvantum kvantum-qt5 qt6-positioning kirigami syntax-highlighting" ;;
        dms)       echo "gpu-screen-recorder" ;;
        *)         echo "" ;;
    esac
}

# quickshell 会话共用的官方仓库包，即 Caelestia 插件的编译与运行依赖。
base_pacman_pkgs() {
    case "$QS_SHELL" in
        dms) echo "" ;;
        *)   echo "aubio libpipewire libqalculate lm_sensors fftw spirv-tools" ;;
    esac
}

# ============================================================
# 固定包列表（与所选会话无关）
# ============================================================
#
# 抽成函数是为了让 update --with-packages 复用同一份列表，
# 否则会出现「配置更新了、依赖没装」的静默故障。
#
# 抽成函数是为了让 `update --with-packages` 也能用同一份列表：
# 升级时新版本新增的依赖必须补上，否则就是「配置更新了、依赖没装」的静默故障。
# 历史上踩过两次：Neovim 只跟踪配置没跟踪包、Caelestia 插件依赖只在
# caelestia 分支装（end4-pC 用户的锁屏直接加载不出来）。
#
# ⚠ 往下面加包之后，已装旧版本的机器要跑一次 `./install.sh update --with-packages`
#   （或 `install`）才会装上 —— update 只补不卸，不会动其它包。

fixed_pacman_pkgs() {
    printf '%s\n' \
        git base-devel github-cli \
        starship \
        kitty jq fish fuzzel \
        grim wl-clipboard wtype playerctl \
        fcitx5 fcitx5-rime fcitx5-configtool \
        xorg-xcursorgen \
        cliphist easyeffects hypridle hyprlock \
        gnome-keyring \
        python \
        procps-ng \
        psmisc \
        libnotify \
        imagemagick \
        noise-suppression-for-voice \
        ffmpeg \
        wf-recorder \
        wget \
        songrec \
        sddm \
        neovim ripgrep fd fzf lazygit tree-sitter-cli \
        neovide \
        cmake ninja \
        qt6-base qt6-declarative qt6-wayland qt6-5compat qt6-shadertools qt6-svg \
        wayland-protocols
}

# 每个包的「为什么必须要」写在这里（原来是内联在 cmd_install 的数组字面量里，
# 抽出来之后注释跟着列表走，避免两边各留一半）：
#
#   starship            fish 默认提示符（config.fish 里 starship init fish | source），
#                       matugen 还有 templates/starship.toml 取色模板。缺了就是
#                       「有 ~/.config/starship.toml、提示符却是原生 fish」这类静默故障。
#   xorg-xcursorgen     generate_cursor_theme.py 把重着色后的 SVG 重编成 XCursor
#                       主题的工具（librsvg 的 rsvg-convert 负责前半段渲染）。
#                       缺了同样卡死光标生成，报错只有一句 "required tool missing"。
#   procps-ng           提供 ps 命令，仪表盘系统页的进程列表依赖它
#                       （base 组已含，这里显式声明以防万一被精简掉）。
#   psmisc              提供 killall。hypr 的 CTRL+SUPER+R（重启 quickshell）是
#                       hl.exec_cmd("killall ydotool qs quickshell; qs -c $qsConfig &")，
#                       这是真调用不是注释；killall 属 psmisc，与 procps-ng 的
#                       pkill/pgrep 不是一个包，别指望顺带带入。
#   libnotify           提供 notify-send：19 个配置文件靠它上报结果与报错
#                       （switchwall 配色、截图、录屏、随机壁纸、强制关窗……）。
#                       缺了不只是"少个气泡"——模糊壁纸脚本把它写进 DEPENDENCIES，
#                       缺失时直接 exit 1，连"缺依赖"这件事都报不出来。
#   imagemagick         提供 magick：与上面同一个脚本的 DEPENDENCIES 里和
#                       notify-send 并列，负责总览模糊底图的高斯模糊与填充着色
#                       （IMG_BLUR_* / IMG_COLORIZE_*），缺了同样 exit 1。
#   noise-suppression-for-voice
#                       提供 LADSPA 插件 librnnoise_ladspa，
#                       pipewire.conf.d/99-input-denoising.conf 的麦克风降噪
#                       filter-chain 依赖它。⚠ 那个模块即使有 ifexists nofail
#                       兜底，缺包也只是「降噪源消失」——装上它降噪才真正生效
#                       （2026-09-30 音频全栈 failed 的根因）。
#   ffmpeg              视频缩略图 / 动态取色（DMS 的 mpvpaper 视频壁纸插件依赖它）。
#                       通用工具，别的 shell 也可能用到，保留在基础列表。
#   wf-recorder         屏幕录制。end4-PC 的录屏实现（scripts/videos/record.sh）
#                       直接调它，RegionSelection 也用 `pidof wf-recorder` 判断
#                       录制状态；dms 用 gpu-screen-recorder，多装一个不碍事。
#   wget                fish 的 `wget` 包装函数（下载进度上报灵动岛，见
#                       config/fish/functions/wget.fish）内部是 `command wget`，
#                       缺了那个函数直接失效。脚本自身只用 curl，以前一直靠依赖
#                       顺带带入。
#   songrec             Shazam 客户端，end4-PC 的音乐识别
#                       （scripts/musicRecognition/recognize-music.sh 硬依赖，
#                       翻译表里也写了「请确保你已安装 songrec」）。在 extra 里。
#   sddm                登录管理器（主题用 Catppuccin Mocha，见
#                       docs/login-screen.md）。注意：若机器上用的是 plasmalogin
#                       （KDE 新版 DM），两者可共存，切换只需 systemctl
#                       disable/enable，见文档。
#   neovim 生态         配置在 config/nvim/（LazyVim）。**编辑器本体必须在这里
#                       显式声明**：之前只跟踪了配置、没跟踪包，新机器装完是
#                       「有配置、没编辑器」，而且 install.sh 不会报任何错
#                       —— 和字体漏装是同一类静默故障。
#                       ripgrep / fd：Telescope 找文件与全局搜索的后端，缺了会
#                                     静默回退到更慢的 find。
#                       fzf：fish 的 fzf 绑定，以及 telescope-fzf-native 的构建基础。
#                       lazygit：<leader>gg 的前提，缺了那个键位根本不存在
#                                （LazyVim 有 executable 守卫）。
#                       tree-sitter-cli：手动编译/调试语法解析器用。
#   neovide             nvim 的 GUI 前端。字体对齐 kitty，见
#                       config/neovide/config.toml。
#   cmake ninja         quickshell 源码编译工具链（三级回退时使用，平时不碍事）。

# 固定 AUR 包（matugen 取色 / mpvpaper 视频壁纸 / walker 启动器 /
# Catppuccin 的 SDDM 主题与光标 / WhiteSur 图标主题）。
# WhiteSur 是图标底盘：matugen 的 [templates.gtk-folder] 只重着色它的文件夹，
# 应用图标保留原版 —— 没装它，覆盖主题的 Inherits=WhiteSur-dark 就落空。
fixed_aur_pkgs() {
    printf '%s\n' matugen mpvpaper walker catppuccin-sddm-theme-mocha catppuccin-cursors-mocha \
        whitesur-icon-theme
}

# 字体链（可选，见 choose_fonts）。分开成函数的原因同上。
#   ttf-jetbrains-mono-nerd  kitty 终端的 Nerd 图标
#   noto-fonts-cjk           按语言切换 CJK 字形的全部地区变体（JP/KR/TC/HK）
#   adobe-source-han-sans-cn 思源黑体 CN：GTK settings.ini 与 fcitx5
#                            classicui.conf 硬编码了它，不能只靠 fontconfig 别名
font_pacman_pkgs() {
    printf '%s\n' ttf-jetbrains-mono-nerd ttf-nerd-fonts-symbols \
        noto-fonts noto-fonts-cjk noto-fonts-emoji \
        adobe-source-han-sans-cn-fonts
}

# ⚠ AUR 包名不规则：上游 README 写的 ttf-maplemononormal-nf-cn 并不存在，
#   实际是 maplemononormal-nf-cn（无 ttf- 前缀）。
font_aur_pkgs() {
    printf '%s\n' otf-misans maplemononormal-nf-cn \
        ttf-lxgw-wenkai ttf-lxgw-wenkai-screen ttf-lxgw-wenkai-tc
}

