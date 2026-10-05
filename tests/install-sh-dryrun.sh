#!/usr/bin/env bash
# install.sh 端到端 dry-run（不需要 sudo / 网络 / 真实包管理器）
#
# 原理：把 install.sh 去掉最后一行 `main "$@"` 当库 source，PATH 前置一层
# 假命令（pacman / paru / sudo / git / cmake / qs / fc-cache / python / curl），
# HOME 指向临时目录，然后直接调 `cmd_install`，走完 7 步。
#
# 覆盖：[1/7]~[7/7] 的控制流、分支函数取值、[4a/7] 编译分支（含构建目录与
# 源码路径配对检查）、[4b/7] 底盘完整性自检、[5/7] 部署（含 chezmoi 前缀）、
# [6/7] 开关、以及"只部署选中那套"的隔离行为。
# 不覆盖：真实包管理、真实 cmake 编译、真实网络。
#
# 用法：bash tests/install-sh-dryrun.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── 隔离：必须跑在私有 D-Bus 会话里 ────────────────────────────────────
# [6/7] 会 `nohup switchwall.sh --noswitch &`，那是**真实脚本**，它会：
#   · 通过 D-Bus 发桌面通知（report_failure → notify-send）
#   · 调 matugen / gsettings 改主题
#   · `pkill -x -9 mpvpaper` / `pkill -x -9 phonto` 干掉壁纸守护进程
# 假 $HOME 挡不住这些 —— 实测曾把一条「配色生成失败」通知漏进用户真实会话
# （假 venv 少了 bin/activate，触发了降级分支）。
# 所以：先把自己塞进 dbus-run-session，再在 PATH 前置一层假命令兜底
# （见下面 STUB 里那几个"会碰真实会话"的假体）。
if [[ -z ${DRYRUN_DBUS_ISOLATED:-} ]]; then
    if command -v dbus-run-session >/dev/null 2>&1; then
        export DRYRUN_DBUS_ISOLATED=1
        exec dbus-run-session -- "$0" "$@"
    fi
    echo "警告：找不到 dbus-run-session，无法隔离 D-Bus；[6/7] 的副作用可能漏进当前会话。" >&2
fi

# 调试用：DRYRUN_ROOT=/tmp/xxx 可保留测试目录（默认用 mktemp 并在退出时清掉）
ROOT="${DRYRUN_ROOT:-$(mktemp -d)}"
if [[ -n ${DRYRUN_ROOT:-} ]]; then
    echo "保留测试目录: $ROOT"
    trap 'true' EXIT
else
    # [6/7] 用 nohup 起的 switchwall 会活过测试，它的 argv 里带着我们的假 $HOME。
    # 按这个精确匹配收掉 —— 别用宽泛的 `pkill -f switchwall.sh`（会误杀用户自己的）。
    # ⚠ 必须用绝对路径：$STUB 里有个假的 pkill（为了挡住 switchwall 的
    #   `pkill -x -9 mpvpaper`），走 PATH 会调到那个假体，等于没杀。
    cleanup() {
        if [[ -x /usr/bin/pkill ]]; then
            /usr/bin/pkill -f "$ROOT/home/.*switchwall" 2>/dev/null || true
        fi
        rm -rf "$ROOT"
    }
    trap cleanup EXIT
fi

STUB="$ROOT/bin"; FAKEHOME="$ROOT/home"; REPOCOPY="$ROOT/repo"
mkdir -p "$STUB" "$FAKEHOME" "$REPOCOPY"

# 源树副本（[5/7] 会 find 它；用副本是为了不污染真实仓库）
cp "$REPO/install.sh" "$REPOCOPY/install.sh"
cp "$REPO/.chezmoiignore" "$REPOCOPY/.chezmoiignore"   # [5/7] 会读它，漏了测不出忽略行为
cp -a "$REPO/lib" "$REPOCOPY/lib"                      # 引导按字典序 source 它，漏了加载不起来
cp -a "$REPO/dot_config" "$REPOCOPY/dot_config"
# 整个文件拷过去当库 source。install.sh 末尾有 BASH_SOURCE 守卫，source 时
# 不会执行 main —— 以前靠 `head -n -1` 剥掉入口行，那依赖「入口恰好是最后
# 一行」：给入口加个 if 包一层，剥掉的就变成 `fi`，if 块失去闭合 → 语法错误
# → 整个测试静默失败（实测 34 项 FAIL）。
cp "$REPOCOPY/install.sh" "$REPOCOPY/lib.sh"

# ---------- 假命令 ----------
mk() { printf '%s\n' "$2" > "$STUB/$1"; chmod +x "$STUB/$1"; }

mk sudo      '#!/bin/sh
exec "$@"'
# pacman/paru 记录 argv：用来断言最终算出来的包列表里确实有配置真正依赖的那些工具。
# ⚠ `pacman -Q` 必须返回**非零**，否则 AUR 循环里的
#   `if pacman -Q "$p"; then 已安装; elif aur_install "$p"` 会把每个包都判成
#   "已安装"，paru 一次都不会被调用，AUR 分支等于没测到。
mk pacman    '#!/bin/sh
printf "pacman %s\n" "$*" >> "${PKG_STUB_LOG:-/tmp/pkg-stub.log}"
case "$1" in
    -Q) exit 1 ;;
esac
exit 0'
mk paru      '#!/bin/sh
printf "paru %s\n" "$*" >> "${PKG_STUB_LOG:-/tmp/pkg-stub.log}"
exit 0'
mk yay       '#!/bin/sh
exit 0'
mk ninja     '#!/bin/sh
exit 0'
mk fc-cache  '#!/bin/sh
exit 0'
mk hyprctl   '#!/bin/sh
exit 0'
mk curl      '#!/bin/sh
exit 1'
# ── 下面这几个是"会碰到真实会话"的假体，不是普通 stub ──────────────────
# [6/7] 会执行真实的 switchwall.sh，它会走 D-Bus / 改主题 / 杀壁纸守护进程。
# dbus-run-session 已经挡掉通知，这里再兜一层，确保它连本地状态都不改。
mk notify-send '#!/bin/sh
exit 0'
mk dbus-send   '#!/bin/sh
exit 0'
mk busctl      '#!/bin/sh
exit 0'
mk matugen     '#!/bin/sh
exit 0'
mk gsettings   '#!/bin/sh
exit 0'
mk dms         '#!/bin/sh
exit 0'
mk mpvpaper    '#!/bin/sh
exit 0'
mk phonto      '#!/bin/sh
exit 0'
mk pkill       '#!/bin/sh
# switchwall 里有 `pkill -x -9 mpvpaper|phonto`：真跑会杀掉用户的视频壁纸守护进程
exit 0'
mk qs        '#!/bin/sh
case "$*" in *"--version"*) echo "Quickshell 0.3.0 (stub)";; esac
exit 0'
# python 假体：处理 `-m venv <dir>`，造出真实 venv 该有的几个入口。
# ⚠ 三个都要有，少一个就会触发真实脚本的降级分支：
#   bin/python3  —— switchwall 用的是 python3；缺了就落到系统 python3 上真跑
#   bin/activate —— switchwall 判 `[[ -f $VENV/bin/activate ]]` 再 source 它；
#                   缺了就报"找不到 quickshell venv"并**弹一条桌面通知**
#   bin/pip      —— 记录 argv，用来断言 venv 里确实装了该装的包
cat > "$STUB/python" <<'EOF'
#!/bin/sh
if [ "$1" = "-m" ] && [ "$2" = "venv" ]; then
    mkdir -p "$3/bin"
    printf '#!/bin/sh\nexit 0\n' > "$3/bin/python"
    chmod +x "$3/bin/python"
    cp "$3/bin/python" "$3/bin/python3"
    cat > "$3/bin/activate" <<'ACTEOF'
deactivate() { :; }
ACTEOF
    cat > "$3/bin/pip" <<'PIPEOF'
#!/bin/sh
printf '%s\n' "$*" >> "${PIP_STUB_LOG:-/tmp/pip-stub.log}"
exit 0
PIPEOF
    chmod +x "$3/bin/pip"
fi
exit 0
EOF
chmod +x "$STUB/python"

# cmake 假体：解析 -S/-B，造出 build 目录 + 假产物 + CMakeCache（含源码路径）。
# 真实 cmake 会做同样两件事：创建 -B 目录、在缓存里记 CMAKE_HOME_DIRECTORY。
cat > "$STUB/cmake" <<'EOF'
#!/bin/sh
# 记下 argv：断言要验证 -DENABLE_MODULES / -DVERSION / -DGIT_REVISION 真的传了
printf '%s\n' "$*" >> "${CMAKE_STUB_LOG:-/tmp/cmake-stub.log}"
src=""; build=""; prev=""
for a in "$@"; do
    case "$prev" in
        -S) src="$a" ;;
        -B) build="$a" ;;
    esac
    prev="$a"
done
if [ -n "$build" ]; then
    mkdir -p "$build/qml/Caelestia/Config"
    : > "$build/qml/Caelestia/libcaelestia-core.so"
    : > "$build/qml/Caelestia/Config/qmldir"
    printf 'CMAKE_HOME_DIRECTORY:INTERNAL=%s\n' "$src" > "$build/CMakeCache.txt"
fi
exit 0
EOF
chmod +x "$STUB/cmake"

# git 假体：clone 时按 URL 造关键文件，其余子命令给固定输出
cat > "$STUB/git" <<'EOF'
#!/bin/sh
case "$1" in
    clone)
        for a in "$@"; do dst="$a"; done
        case "$*" in
            *end4-PC*)
                mkdir -p "$dst/modules/common" "$dst/services" "$dst/scripts/colors"
                mkdir -p "$dst/modules/ii/dashboard-caelestia/dashboard"
                mkdir -p "$dst/modules/ii/dashboard-caelestia/components/filedialog"
                mkdir -p "$dst/modules/ii/dashboard-caelestia/components/controls"
                mkdir -p "$dst/modules/ii/dashboard-caelestia/shim"
                : > "$dst/shell.qml"
                : > "$dst/modules/common/Config.qml"
                : > "$dst/modules/common/Appearance.qml"
                : > "$dst/modules/ii/dashboard-caelestia/dashboard/Content.qml"
                : > "$dst/modules/ii/dashboard-caelestia/components/filedialog/FileDialog.qml"
                : > "$dst/modules/ii/dashboard-caelestia/components/controls/ButtonBase.qml"
                : > "$dst/modules/ii/dashboard-caelestia/shim/qmldir"
                : > "$dst/scripts/colors/switchwall.sh"
                ;;
            *caelestia*)
                mkdir -p "$dst/plugin"
                : > "$dst/shell.qml"
                ;;
        esac
        exit 0 ;;
    describe) echo "v1.2.3" ;;
    rev-parse) echo "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" ;;
esac
exit 0
EOF
chmod +x "$STUB/git"

export HOME="$FAKEHOME"
export PATH="$STUB:$PATH"
export SESSION=end4pc FONTS=0
export ROOT
export CMAKE_STUB_LOG="$ROOT/cmake-argv.log"
export PKG_STUB_LOG="$ROOT/pkg-argv.log"
export PIP_STUB_LOG="$ROOT/pip-argv.log"

run_install() { # run_install <日志文件>
    set +e
    bash -c 'source "$ROOT/repo/lib.sh"; cmd_install' > "$1" 2>&1
    echo $?
    set -e
}

fail=0
chk() {
    if [[ "$2" == "$3" ]]; then printf '  OK   %s\n' "$1"
    else printf '  FAIL %s\n        实际=[%s]\n        期望=[%s]\n' "$1" "$2" "$3"; fail=$((fail + 1)); fi
}

# ============================ 第一轮：全新安装 ============================
out="$ROOT/install.log"
rc="$(run_install "$out")"

echo "== 控制流 =="
chk "cmd_install 退出码 0"        "$rc" "0"
chk "走到 [5/7] 部署"             "$(grep -c '\[5/7\] 部署配置文件' "$out")" "1"
chk "走到 [7/7] 完成"             "$(grep -c '\[7/7\] 完成' "$out")" "1"
chk "插件源码 clone 到 \$HOME/src" "$([[ -d $HOME/src/caelestia-plugin-src/plugin ]] && echo yes)" "yes"
chk "底盘完整性自检通过"          "$(grep -c '底盘完整' "$out")" "1"

echo "== [4a/7] 编译逻辑 =="
chk "限定只编 plugin 模块"        "$(grep -c -- '-DENABLE_MODULES=plugin' "$CMAKE_STUB_LOG")" "1"
chk "传入了 VERSION"              "$(grep -c -- '-DVERSION=1.2.3' "$CMAKE_STUB_LOG")" "1"
chk "传入了 GIT_REVISION"         "$(grep -c -- '-DGIT_REVISION=deadbeef' "$CMAKE_STUB_LOG")" "1"
chk "产物自检通过"                "$(grep -c '编译完成' "$out")" "1"

echo "== [5/7] 部署结果（chezmoi 前缀）=="
chk "private_config → config"     "$([[ -f $HOME/.config/fcitx5/config ]] && echo yes)" "yes"
chk "  ↑ 权限 600"                "$(stat -c '%a' "$HOME/.config/fcitx5/config" 2>/dev/null)" "600"
chk "private_classicui → conf"    "$([[ -f $HOME/.config/fcitx5/conf/classicui.conf ]] && echo yes)" "yes"
chk "symlink_mako → 真链接"       "$([[ -L $HOME/.config/systemd/user/mako.service ]] && echo yes)" "yes"
chk "  ↑ 指向 /dev/null"          "$(readlink "$HOME/.config/systemd/user/mako.service" 2>/dev/null)" "/dev/null"
chk "create_custom_config 字面名" "$([[ -f $HOME/.config/hypr/hyprland/services/create_custom_config.lua ]] && echo yes)" "yes"
chk "executable_ 已剥前缀且可执行" "$([[ -x $HOME/.config/hypr/hyprland/scripts/start_quickshell.sh ]] && echo yes)" "yes"
chk "end4-PC 差异层已部署"        "$([[ -f $HOME/.config/quickshell/end4-pC/panelFamilies/CaelestiaPluginProbe.qml ]] && echo yes)" "yes"
chk "全新机器仍拿到配色默认值"    "$([[ -s $HOME/.config/hypr/hyprland/colors.lua ]] && echo yes)" "yes"

echo "== 隔离：只部署选中那套 =="
chk "hyprland 会话：~/.config/hypr 有"   "$([[ -d $HOME/.config/hypr ]] && echo yes)" "yes"
chk "hyprland 会话：~/.config/niri 没有" "$([[ -e $HOME/.config/niri ]] && echo yes)" ""
chk "end4-pC：不 clone caelestia shell"  "$([[ -e $HOME/.config/quickshell/caelestia ]] && echo yes)" ""

echo "== [6/7] 开关 =="
chk "FONTS=0：跳过字体包"   "$(grep -c '字体: 已跳过' "$out")" "1"
chk "FONTS=0：不下霞鹜臻楷" "$([[ -e $HOME/.local/share/fonts/LXGWZhenKaiGB-Regular.ttf ]] && echo yes)" ""

echo "== 依赖矩阵（配置真正调用的工具必须在安装列表里）=="
# 这些不是"回退链里的备选"，而是 dot_config 里被当作主路径调用的命令。
# 断言在**真实算出来的包列表**上，而不是在源码文本上。
chk "pacman 列表含 wf-recorder" "$(grep -c -- ' wf-recorder' "$PKG_STUB_LOG")" "1"
chk "pacman 列表含 wget"        "$(grep -c -- ' wget' "$PKG_STUB_LOG")" "1"
chk "pacman 列表含 songrec"     "$(grep -c -- ' songrec' "$PKG_STUB_LOG")" "1"
chk "AUR 列表含 walker"         "$(grep -c -- 'paru .* walker' "$PKG_STUB_LOG")" "1"
chk "venv 装了 kde-material-you-colors" \
    "$(grep -c 'kde-material-you-colors' "$PIP_STUB_LOG" 2>/dev/null || echo 0)" "1"

# ================== 第二轮：构建目录指向旧源码路径 ==================
out2="$ROOT/install2.log"
rm -f "$HOME/src/caelestia-build/.overlay-stamp"
printf 'CMAKE_HOME_DIRECTORY:INTERNAL=%s\n' \
       "$HOME/.config/quickshell/caelestia" > "$HOME/src/caelestia-build/CMakeCache.txt"
rc2="$(run_install "$out2")"

echo "== [4a/7] 构建目录与源码路径配对 =="
chk "第二轮退出码 0"              "$rc2" "0"
chk "检测到源码路径已变"          "$(grep -c '源码路径已变' "$out2")" "1"
chk "清空后重新配置并编出产物"    "$(grep -c '编译完成' "$out2")" "1"
chk "缓存里的源码路径已更新"      "$(grep -c "^CMAKE_HOME_DIRECTORY:INTERNAL=$HOME/src/caelestia-plugin-src$" "$HOME/src/caelestia-build/CMakeCache.txt")" "1"

# 模拟"运行时生成物被改写"：真实安装里 [6/7] 的 switchwall 会让 matugen 按当前
# 壁纸重写配色，这里手工追加一行等价于那件事。仓库里那份只是历史快照。
printf '\n-- generated by matugen for the current wallpaper\n' >> "$HOME/.config/hypr/hyprland/colors.lua"
palette_hash="$(sha256sum "$HOME/.config/hypr/hyprland/colors.lua" | cut -c1-16)"
: "$palette_hash"   # 保留现场：失败时用它和实际内容对照

# ================== 第三轮：一切就绪 → 幂等跳过 ==================
out3="$ROOT/install3.log"
rc3="$(run_install "$out3")"

echo "== 幂等 =="
chk "第三轮退出码 0"        "$rc3" "0"
# ⚠ 不能用 `grep -c '已编译'`：[7/7] 的指引文本里也有「已编译到 …」，会误计。
#   用带冒号的完整串，只命中 [4a/7] 的跳过分支。
chk "编译被跳过"            "$(grep -c '已编译: ' "$out3")" "1"
chk "没再触发重建"          "$(grep -c '源码路径已变' "$out3")" "0"

echo "== [5/7] .chezmoiignore 与幂等 =="
# 这是上一轮修掉的缺口：install.sh 以前不读 .chezmoiignore，每重跑一次安装都会
# 用仓库快照把 matugen 生成的配色覆盖回去。
#
# ⚠ 这里断言的是 install.sh **自己的决定**（日志里的保留计数），不是文件内容：
#   [6/7] 会 `nohup switchwall.sh &` 让真实的 matugen 异步重写配色，文件内容
#   不是稳定可观测量（连跑两次都可能不同）。"确实没覆盖"由行为测试台的 G2
#   直接验证 deploy_one_file 的返回值与文件内容。
chk "重复运行 0 备份"       "$(sed -n 's/.*；\([0-9]*\) 个有差异的旧文件.*/\1/p' "$out3" | head -1)" "0"
chk "报告了忽略统计"        "$(grep -c '按 .chezmoiignore 跳过' "$out3")" "1"
kept="$(sed -n 's/^ *\([0-9]\+\) 个运行时生成物已存在.*/\1/p' "$out3" | head -1)"
chk "运行时生成物被判定为保留（≥7）" "$([[ ${kept:-0} -ge 7 ]] && echo yes)" "yes"

echo
if ((fail)); then printf '失败 %d 项\n' "$fail"; exit 1; else printf '全部通过\n'; fi
