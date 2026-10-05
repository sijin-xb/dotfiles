#!/usr/bin/env bash

# ==============================================================================
# WhiteSur-Matugen Icon Generator
#
# WhiteSur-dark 提供全部图标，本脚本只把 places/scalable 下的文件夹重着色为
# matugen 次色系，产出 WhiteSur-Matugen-{A,B} 覆盖主题（素材 index.theme 里
# 写着 Inherits=WhiteSur-dark）。
#
# 为什么只动文件夹：WhiteSur 的 app / device / mime 图标是彩色拟物素材
# （多层渐变 + 品牌色），matugen 只做 hex 文本替换，换完色整幅图标会崩。
# 文件夹是纯色阶素材，scalable/places 下 33 个 SVG 共用同一套 4 色。
# places/16|22|24 是 currentColor symbolic，颜色由 GTK 渲染时给，无需处理。
#
# 为什么 A/B 交替：GTK/Qt 会缓存已加载主题的图标，同名覆盖不生效，改名强制重载。
# ==============================================================================

# ------------------------------------------------------------------------------
# 文件夹色阶映射（WhiteSur 原始色 -> matugen 角色），保持四级明度关系，
# 顺序错了高光会盖过主体：
#   #008ea2 暗部   -> secondary_container
#   #46a2d7 主体   -> secondary_fixed_dim
#   #60c0f0 中间调 -> secondary
#   #83d4fb 高光   -> secondary_fixed
# ------------------------------------------------------------------------------
COLOR_FOLDER_SHADOW="{{colors.secondary_container.default.hex}}"
COLOR_FOLDER_BODY="{{colors.secondary_fixed_dim.default.hex}}"
COLOR_FOLDER_MID="{{colors.secondary.default.hex}}"
COLOR_FOLDER_TOP="{{colors.secondary_fixed.default.hex}}"

CMD_FOLDER="
s/#008ea2/$COLOR_FOLDER_SHADOW/g;
s/#46a2d7/$COLOR_FOLDER_BODY/g;
s/#60c0f0/$COLOR_FOLDER_MID/g;
s/#83d4fb/$COLOR_FOLDER_TOP/g"

# ==============================================================================
# 执行
# ==============================================================================

TEMPLATE_DIR="$HOME/.config/matugen/templates/gtk-folder/WhiteSur-Matugen"
CURRENT_THEME=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")

if [[ "$CURRENT_THEME" == "WhiteSur-Matugen-A" ]]; then
    TARGET_THEME="WhiteSur-Matugen-B"
else
    TARGET_THEME="WhiteSur-Matugen-A"
fi
TARGET_DIR="$HOME/.local/share/icons/$TARGET_THEME"

# 1. 铺素材。先清目录：素材删掉某个 SVG 后，只靠 cp 覆盖会把旧文件留在主题里
rm -rf "${TARGET_DIR:?}"
mkdir -p "$TARGET_DIR"
cp -rf --reflink=auto --no-preserve=mode,ownership "$TEMPLATE_DIR/"* "$TARGET_DIR/"
sed -i "s/^Name=.*/Name=$TARGET_THEME/" "$TARGET_DIR/index.theme"

# 2. 重着色
find "$TARGET_DIR/places/scalable" -name '*.svg' -print0 | xargs -0 -P0 -r sed -i "$CMD_FOLDER"
gtk-update-icon-cache -f -t "$TARGET_DIR" >/dev/null 2>&1 || true

# 3. 应用。gsettings 只覆盖 GNOME/GTK 的一部分；Qt、fuzzel、rofi、xsettingsd、
#    GTK2 各读自己的配置，不逐个写就会出现「文件夹换了但 fuzzel 图标没换」的割裂。
gsettings set org.gnome.desktop.interface icon-theme "$TARGET_THEME" 2>/dev/null
flatpak override --user --env=ICON_THEME="$TARGET_THEME" 2>/dev/null || true

set_ini_key() { # file key value
    local file="$1" key="$2" value="$3"
    [[ -f "$file" ]] || return 0
    if grep -q "^${key}=" "$file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        echo "${key}=${value}" >>"$file"
    fi
}

set_ini_key "$HOME/.config/gtk-3.0/settings.ini" gtk-icon-theme-name "$TARGET_THEME"
set_ini_key "$HOME/.config/gtk-4.0/settings.ini" gtk-icon-theme-name "$TARGET_THEME"
set_ini_key "$HOME/.config/qt5ct/qt5ct.conf" icon_theme "$TARGET_THEME"
set_ini_key "$HOME/.config/qt6ct/qt6ct.conf" icon_theme "$TARGET_THEME"
set_ini_key "$HOME/.config/fuzzel/fuzzel.ini" icon-theme "$TARGET_THEME"

# rofi 的图标主题写在 .rasi 里而不是 ini（旧脚本漏了这个 sink，
# 所以 rofi 一直停在 Papirus-Dark —— 那个主题本机根本没装）
mkdir -p "$HOME/.config/rofi/themes"
cat >"$HOME/.config/rofi/themes/icons.rasi" <<EOF
* {
  icon-theme: "$TARGET_THEME";
}
EOF

# xsettingsd 的值带引号，单独处理
XSETTINGSD_CONFIG="$HOME/.config/xsettingsd/xsettingsd.conf"
if [[ -f "$XSETTINGSD_CONFIG" ]]; then
    if grep -q "^Net/IconThemeName" "$XSETTINGSD_CONFIG" 2>/dev/null; then
        sed -i "s|^Net/IconThemeName.*|Net/IconThemeName \"$TARGET_THEME\"|" "$XSETTINGSD_CONFIG"
    else
        echo "Net/IconThemeName \"$TARGET_THEME\"" >>"$XSETTINGSD_CONFIG"
    fi
    pkill -HUP xsettingsd 2>/dev/null || true
fi

# GTK2
gtk2_config="$HOME/.gtkrc-2.0"
if [[ -f "$gtk2_config" ]]; then
    if grep -q "^gtk-icon-theme-name=" "$gtk2_config" 2>/dev/null; then
        sed -i "s|^gtk-icon-theme-name=.*|gtk-icon-theme-name=\"$TARGET_THEME\"|" "$gtk2_config"
    else
        echo "gtk-icon-theme-name=\"$TARGET_THEME\"" >>"$gtk2_config"
    fi
fi

exit 0
