#!/usr/bin/env bash
# install.sh 行为测试台（不需要 pacman / AUR / 网络 / sudo）
#
# 原理：把 install.sh 去掉最后一行 `main "$@"` 之后当作**库** source 进来，
# 然后直接调用里面已经抽成顶层函数的纯逻辑部分：
#   deploy_one_file()      [5/7] 的循环体：chezmoi 前缀 / 备份 / 幂等
#   end4pc_base_missing()  底盘完整性自检
#   active_snap_paths()    删除范围过滤（合成器 + shell 两个维度）
#   skip_by_shell() / skip_by_compositor()   部署过滤
#
# 用法：bash tests/install-sh-behaviour-test.sh
#   全通过退出码 0；有失败项打印实际/期望并退出 1。
#
# ⚠ 测试台自己**不能**放在它 rm -rf 的目录里。
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/src/dot_config"/{fcitx5/conf,systemd/user,hypr/hyprland/services,scripts,quickshell/end4-pC/panelFamilies}
mkdir -p "$ROOT/home" "$ROOT/backup"

# 假源树：覆盖所有 chezmoi 前缀 + 一个目录被 skip 的场景
printf '[Hotkey]\nEnumerateWithTriggerKeys=True\n' > "$ROOT/src/dot_config/fcitx5/private_config"
printf '[ClassicUI]\nTheme=default\n'            > "$ROOT/src/dot_config/fcitx5/conf/private_classicui.conf"
printf '/dev/null\n'                             > "$ROOT/src/dot_config/systemd/user/symlink_mako.service"
printf 'require("hyprland/lib")\n'               > "$ROOT/src/dot_config/hypr/hyprland/services/create_custom_config.lua"
printf '#!/usr/bin/env bash\necho hi\n'          > "$ROOT/src/dot_config/scripts/executable_probe.sh"
printf 'shell\n'                                 > "$ROOT/src/dot_config/quickshell/end4-pC/shell.qml"
mkdir -p "$ROOT/src/dot_config/hypr/hyprland"
printf 'REPO_SNAPSHOT_PALETTE\n'                 > "$ROOT/src/dot_config/hypr/hyprland/colors.lua"

# chezmoi_ignore_kind() 读 $SRC/.chezmoiignore（SRC = lib.sh 所在目录 = $ROOT）。
# 用**真实的**忽略清单，这样测的是真模式而不是自造的玩具模式。
cp "$REPO/.chezmoiignore" "$ROOT/.chezmoiignore"

# 去掉最后的 `main "$@"`，剩下的当库用（SRC 会取 lib.sh 所在目录 = $ROOT）
head -n -1 "$REPO/install.sh" > "$ROOT/lib.sh"

export HOME="$ROOT/home"
# shellcheck disable=SC1090
source "$ROOT/lib.sh"

backup_dir="$ROOT/backup"
backed=0
fail=0

chk() { # chk <描述> <实际> <期望>
    if [[ "$2" == "$3" ]]; then
        printf '  OK   %s\n' "$1"
    else
        printf '  FAIL %s\n        实际=[%s]\n        期望=[%s]\n' "$1" "$2" "$3"
        fail=$((fail + 1))
    fi
}

say_t() { printf '\n== %s ==\n' "$1"; }

say_t "A. chezmoi 前缀：private_ / symlink_ / executable_ / create_"
deploy_one_file "$ROOT/src/dot_config/fcitx5/private_config"                 "$HOME/.config/fcitx5"        "private_config"
deploy_one_file "$ROOT/src/dot_config/fcitx5/conf/private_classicui.conf"    "$HOME/.config/fcitx5/conf"   "private_classicui.conf"
deploy_one_file "$ROOT/src/dot_config/systemd/user/symlink_mako.service"     "$HOME/.config/systemd/user"  "symlink_mako.service"
deploy_one_file "$ROOT/src/dot_config/hypr/hyprland/services/create_custom_config.lua" \
                                                                             "$HOME/.config/hypr/hyprland/services" "create_custom_config.lua"
deploy_one_file "$ROOT/src/dot_config/scripts/executable_probe.sh"           "$HOME/.config/scripts"       "executable_probe.sh"

chk "private_config → config 名对"        "$([[ -f $HOME/.config/fcitx5/config ]] && echo yes)"            "yes"
chk "private_config 无残留前缀文件"       "$([[ -e $HOME/.config/fcitx5/private_config ]] && echo yes)"    ""
chk "private_config 权限 600"             "$(stat -c '%a' "$HOME/.config/fcitx5/config")"                  "600"
chk "private_classicui → classicui.conf"  "$([[ -f $HOME/.config/fcitx5/conf/classicui.conf ]] && echo yes)" "yes"
chk "conf 权限 600"                       "$(stat -c '%a' "$HOME/.config/fcitx5/conf/classicui.conf")"     "600"
chk "symlink_mako 是符号链接"             "$([[ -L $HOME/.config/systemd/user/mako.service ]] && echo yes)" "yes"
chk "symlink 目标为 /dev/null"            "$(readlink "$HOME/.config/systemd/user/mako.service")"          "/dev/null"
chk "create_custom_config 名字保持字面"   "$([[ -f $HOME/.config/hypr/hyprland/services/create_custom_config.lua ]] && echo yes)" "yes"
chk "create_custom_config 没被剥前缀"     "$([[ -e $HOME/.config/hypr/hyprland/services/custom_config.lua ]] && echo yes)"        ""
chk "executable_probe.sh 可执行"          "$([[ -x $HOME/.config/scripts/probe.sh ]] && echo yes)"         "yes"
chk "executable_probe.sh 名字无前缀"      "$([[ -e $HOME/.config/scripts/executable_probe.sh ]] && echo yes)" ""

say_t "B. 幂等：重跑一遍不该产生备份、也不该改坏链接"
backed=0
deploy_one_file "$ROOT/src/dot_config/fcitx5/private_config"                 "$HOME/.config/fcitx5"        "private_config"
deploy_one_file "$ROOT/src/dot_config/systemd/user/symlink_mako.service"     "$HOME/.config/systemd/user"  "symlink_mako.service"
chk "重跑 0 次备份"        "$backed"                                                          "0"
chk "链接仍然正确"         "$(readlink "$HOME/.config/systemd/user/mako.service")"            "/dev/null"

say_t "C. 内容变了 → 备份旧文件（符号链接按链接本身备份）"
printf '[Hotkey]\nEnumerateWithTriggerKeys=False\n' > "$ROOT/src/dot_config/fcitx5/private_config"
printf '/dev/zero\n'                                > "$ROOT/src/dot_config/systemd/user/symlink_mako.service"
backed=0
deploy_one_file "$ROOT/src/dot_config/fcitx5/private_config"             "$HOME/.config/fcitx5"        "private_config"
deploy_one_file "$ROOT/src/dot_config/systemd/user/symlink_mako.service" "$HOME/.config/systemd/user"  "symlink_mako.service"
chk "2 次备份"                                  "$backed"                                              "2"
chk "旧 config 已备份"                          "$([[ -f $ROOT/backup/$HOME/.config/fcitx5/config ]] && echo yes)" "yes"
chk "旧链接以链接形式备份"                      "$([[ -L $ROOT/backup/$HOME/.config/systemd/user/mako.service ]] && echo yes)" "yes"
chk "链接已更新为 /dev/zero"                    "$(readlink "$HOME/.config/systemd/user/mako.service")" "/dev/zero"

say_t "D. end4pc_base_missing：完整 / 残缺"
D="$HOME/.config/quickshell/end4-pC"
mkdir -p "$D/modules/common" "$D/services" "$D/scripts/colors"
for f in shell.qml modules/common/Config.qml modules/common/Appearance.qml \
         scripts/colors/switchwall.sh; do
    mkdir -p "$D/$(dirname "$f")"; : > "$D/$f"
done
chk "完整底盘 → 无输出"      "$(end4pc_base_missing || true)"   ""
chk "完整底盘 → 返回 1"      "$(end4pc_base_missing; echo "rc=$?")"  "rc=1"
rm -f "$D/modules/common/Appearance.qml"
chk "缺一个 → 报出该文件"    "$(end4pc_base_missing || true)"   "modules/common/Appearance.qml"
chk "缺文件 → 返回 0"        "$(end4pc_base_missing >/dev/null; echo "rc=$?")"  "rc=0"
: > "$D/modules/common/Appearance.qml"
rm -rf "$D/services"
chk "缺目录也算缺"           "$(end4pc_base_missing || true)"   "services"
mkdir -p "$D/services"

# ⚠ 回归：**上游不提供的路径绝不能被列进清单**。
#   列了就会永远判"缺" → 重拉上游也补不上 → 安装 die。
#   这四项历史上就在清单里，而 pctrade/end4-PC 的 modules/ii/ 下
#   根本没有 dashboard-caelestia（用 gh api 核过）。
for f in modules/ii/dashboard-caelestia/dashboard/Content.qml \
         modules/ii/dashboard-caelestia/components/filedialog/FileDialog.qml \
         modules/ii/dashboard-caelestia/components/controls/ButtonBase.qml \
         modules/ii/dashboard-caelestia/shim/qmldir; do
    chk "定制层路径不进底盘自检: ${f##*/}" "$(end4pc_base_missing || true)" ""
done

say_t "D2. base_tree_missing：拿 clone 当基准（不靠硬编码清单）"
bsrc="$ROOT/base-src"
mkdir -p "$bsrc/modules/common" "$bsrc/services"
printf 'a\n' > "$bsrc/shell.qml"
printf 'b\n' > "$bsrc/modules/common/Config.qml"
printf 'c\n' > "$bsrc/services/x.qml"
bdst="$HOME/.config/quickshell/base-dst"; mkdir -p "$bdst"
cp -a "$bsrc/." "$bdst/"
chk "clone 全部落地 → 无输出"   "$(base_tree_missing "$bsrc" "$bdst" || true)" ""
chk "clone 全部落地 → 返回 1"   "$(base_tree_missing "$bsrc" "$bdst"; echo "rc=$?")" "rc=1"
rm -f "$bdst/services/x.qml"
chk "漏一个 → 精确报出落点"     "$(base_tree_missing "$bsrc" "$bdst" || true)" "services/x.qml"
chk "clone 目录不存在 → 算残缺" "$(base_tree_missing "$ROOT/no-such" "$bdst" >/dev/null; echo "rc=$?")" "rc=0"

say_t "E. active_snap_paths：删除范围按 shell 过滤"
qsp() {
    ( COMPOSITOR=hyprland; QS_SHELL="$1"; active_snap_paths ) | grep -c "quickshell/end4-pC" || true
}
qsc() {
    ( COMPOSITOR=hyprland; QS_SHELL="$1"; active_snap_paths ) | grep -c "quickshell/caelestia" || true
}
chk "QS_SHELL=end4-pC → 含 end4-pC"   "$(qsp end4-pC)"    "1"
chk "QS_SHELL=end4-pC → 不含 caelestia" "$(qsc end4-pC)"  "0"
chk "QS_SHELL=caelestia → 含 caelestia" "$(qsc caelestia)" "1"
chk "QS_SHELL=caelestia → 不含 end4-pC" "$(qsp caelestia)" "0"
chk "QS_SHELL=both → 两个都在"        "$(qsp both)$(qsc both)" "11"
chk "QS_SHELL 空 → 保持旧行为(都算)"  "$(qsp '')$(qsc '')"     "11"

say_t "F. skip_by_shell / skip_by_compositor"
chk "end4-pC 跳过 caelestia 差异层" "$( (QS_SHELL=end4-pC; skip_by_shell dot_config/quickshell/caelestia/plugin/x.po; echo rc=$?) )" "rc=0"
chk "end4-pC 不跳自己的差异层"      "$( (QS_SHELL=end4-pC; skip_by_shell dot_config/quickshell/end4-pC/shell.qml; echo rc=$?) )"    "rc=1"
chk "niri 会话跳过 dot_config/hypr" "$( (COMPOSITOR=niri; skip_by_compositor dot_config/hypr/x; echo rc=$?) )"                     "rc=0"
chk "hyprland 会话跳过 dot_config/niri" "$( (COMPOSITOR=hyprland; skip_by_compositor dot_config/niri/x; echo rc=$?) )"             "rc=0"

say_t "G. .chezmoiignore 匹配（用仓库里真实的忽略清单）"
chk "精确路径 → keep"                 "$(chezmoi_ignore_kind .config/hypr/hyprland/colors.lua)" "keep"
chk "精确路径(UI 写回) → keep"        "$(chezmoi_ignore_kind .config/mimeapps.list)" "keep"
chk "未列出的路径 → 空"               "$(chezmoi_ignore_kind .config/fish/config.fish)" ""
chk "目录条目 → skip"                 "$(chezmoi_ignore_kind .config/niri/qssettings/foo.kdl)" "skip"
chk "**/*.pyc → skip"                 "$(chezmoi_ignore_kind .config/x/y/z.pyc)" "skip"
chk "**/__pycache__ → skip"           "$(chezmoi_ignore_kind .config/x/__pycache__)" "skip"
chk "**/__pycache__/ 内层 → skip"     "$(chezmoi_ignore_kind .config/x/__pycache__/a.pyc)" "skip"
chk "**/dot_git → skip"               "$(chezmoi_ignore_kind .config/DankMaterialShell/plugins/foo/dot_git)" "skip"
chk "单层 glob (*.bak*) → skip"       "$(chezmoi_ignore_kind .config/niri/dms/layout.kdl.bak-123)" "skip"
chk "dms/binds.kdl 未被屏蔽"          "$(chezmoi_ignore_kind .config/niri/dms/binds.kdl)" ""
chk "create_custom_config 未被屏蔽"   "$(chezmoi_ignore_kind .config/hypr/hyprland/services/create_custom_config.lua)" ""

say_t "G2. .chezmoiignore 生效路径：运行时生成物不被仓库快照覆盖"
mkdir -p "$HOME/.config/hypr/hyprland"
printf 'CURRENT_PALETTE\n' > "$HOME/.config/hypr/hyprland/colors.lua"
backed=0; ignored_keep=0; ignored_skip=0
deploy_one_file "$ROOT/src/dot_config/hypr/hyprland/colors.lua" \
                "$HOME/.config/hypr/hyprland" "colors.lua"
chk "目标已存在 → 保留当前值" "$(cat "$HOME/.config/hypr/hyprland/colors.lua")" "CURRENT_PALETTE"
chk "计入 ignored_keep"       "$ignored_keep" "1"
chk "不产生备份"              "$backed" "0"
rm -f "$HOME/.config/hypr/hyprland/colors.lua"
deploy_one_file "$ROOT/src/dot_config/hypr/hyprland/colors.lua" \
                "$HOME/.config/hypr/hyprland" "colors.lua"
chk "目标不存在 → 部署仓库默认值" "$(cat "$HOME/.config/hypr/hyprland/colors.lua")" "REPO_SNAPSHOT_PALETTE"

say_t "H. 依赖矩阵：分支函数输出"
chk "dms 分支含 nirius"            "$( (QS_SHELL=dms; shell_aur_pkgs) | tr ' ' '\n' | grep -cx nirius)" "1"
chk "dms 分支含 awww-git"          "$( (QS_SHELL=dms; shell_aur_pkgs) | tr ' ' '\n' | grep -cx awww-git)" "1"
chk "end4-pC 不装 niri 专用包"     "$( (QS_SHELL=end4-pC; shell_aur_pkgs) | wc -w)" "0"
chk "quickshell 会话拿到插件 AUR 依赖" "$( (QS_SHELL=end4-pC; base_aur_pkgs) | tr ' ' '\n' | grep -cx libcava)" "1"
chk "dms 不装插件 AUR 依赖"        "$( (QS_SHELL=dms; base_aur_pkgs) | wc -w)" "0"
chk "quickshell 会话拿到插件 pacman 依赖" "$( (QS_SHELL=end4-pC; base_pacman_pkgs) | tr ' ' '\n' | grep -cx libqalculate)" "1"
chk "dms 不装插件 pacman 依赖"     "$( (QS_SHELL=dms; base_pacman_pkgs) | wc -w)" "0"

say_t "I. clone 合并不带 .git（重跑安装不再被 .git 卡死）"
# 造一份"刚 clone 出来"的源：带 .git，以及正常的配置文件
csrc="$ROOT/clone-src"; mkdir -p "$csrc/.git/objects/pack" "$csrc/modules"
printf 'PACKDATA' > "$csrc/.git/objects/pack/pack-deadbeef.pack"
printf 'shell\n'  > "$csrc/shell.qml"
printf 'x\n'      > "$csrc/modules/Config.qml"
cdst="$HOME/.config/quickshell/end4-pC"; mkdir -p "$cdst"
merge_clone_into "$csrc" "$cdst"
chk "目标拿到 shell.qml"           "$([[ -f $cdst/shell.qml ]] && echo yes)" "yes"
chk "目标拿到 modules/Config.qml"  "$([[ -f $cdst/modules/Config.qml ]] && echo yes)" "yes"
chk "目标里没有 .git"              "$([[ -e $cdst/.git ]] && echo yes)" ""
chk "源里的 .git 已剥掉"           "$([[ -e $csrc/.git ]] && echo yes)" ""

# 历史遗留：目标目录里已有一个旧版本拷进去的 .git
mkdir -p "$cdst/.git/objects/pack"
printf 'OLD' > "$cdst/.git/objects/pack/pack-old.pack"
cleanup_stray_git "$cdst"
chk "历史遗留 .git 被清理"         "$([[ -e $cdst/.git ]] && echo yes)" ""
chk "没有 .git 时幂等且不报错"     "$(cleanup_stray_git "$cdst"; echo rc=$?)" "rc=0"

say_t "J. 依赖声明：本次补的三个 + 复核「故意不加」那批"
# 包列表现在全部由函数产出（原先固定列表是内联的 PACMAN_PKGS=(...) 字面量，
# 抽成 fixed_pacman_pkgs / font_* 是为了让 `update --with-packages` 复用同一份，
# 避免两处各维护一半）。所以这里直接调函数取输出。
#
# ⚠ 各 fixed_* 函数的文档注释写在函数**外面**（独立的注释块），printf 里只有
#   包名，所以取到的输出不含「注释里提到的命令名」，不会把注释当声明。
_funcs="$(compositor_pkgs 2>/dev/null; shell_pacman_pkgs 2>/dev/null; base_pacman_pkgs 2>/dev/null; \
          base_aur_pkgs 2>/dev/null; shell_aur_pkgs 2>/dev/null; compositor_aur_pkgs 2>/dev/null; \
          fixed_pacman_pkgs 2>/dev/null; fixed_aur_pkgs 2>/dev/null; \
          font_pacman_pkgs 2>/dev/null; font_aur_pkgs 2>/dev/null)"
_all_pkgs="$(printf '%s\n' "$_funcs" | tr -s '[:space:]' '\n')"
has_pkg() { printf '%s\n' "$_all_pkgs" | grep -cx "$1"; }

# 本次坐实后新补的：都在可执行上下文里被真实调用
chk "声明 psmisc（killall）"        "$(has_pkg psmisc)"      "1"
chk "声明 libnotify（notify-send）" "$(has_pkg libnotify)"   "1"
chk "声明 imagemagick（magick）"    "$(has_pkg imagemagick)" "1"

# 「故意不加」那批：逐个确认**没有**被声明（复核依据见 CHANGELOG）
for _p in rofi clipse anyrun satty ydotool firefox micro \
          alacritty wezterm waybar swaybg swayidle hyprpaper copyq upscayl; do
    chk "未声明 $_p（复核：不在可执行上下文）" "$(has_pkg "$_p")" "0"
done

printf '\n============================\n'
if ((fail)); then printf '失败 %d 项\n' "$fail"; exit 1; else printf '全部通过\n'; fi
