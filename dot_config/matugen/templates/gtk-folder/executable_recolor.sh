#!/usr/bin/env bash

# ==============================================================================
# Adwaita-Matugen Icon Generator V6 (扁平化配置版)
# 逻辑：每一组 SVG 文件的颜色变量直接在顶部定义，方便用户微调。
# ==============================================================================

# ==============================================================================
# [一] 颜色变量配置区 (用户修改此处)
# ==============================================================================
MAIN_COLOR="{{colors.secondary_fixed_dim.default.hex}}"
MAIN_SHADOW="{{colors.secondary_container.default.hex}}"
MAIN_DARKER_SHADOW="{{colors.on_secondary.default.hex}}"
MAIN_HILIGHT="{{colors.secondary.default.hex}}"
INVERSE_MAIN_COLOR="{{colors.tertiary_fixed_dim.default.hex}}"
INVERSE_MAIN_HIGHLT="{{colors.tertiary.default.hex}}"
INVERSE_MAIN_SHADOW="{{colors.tertiary_container.default.hex}}" 
PAPER_COLOR="#fafafa" 
PAPER_FOLE_COLOR="#deddda"
# ------------------------------------------------------------------------------
# [1] 文件夹 (folder*.svg / user-home.svg ...)
# ------------------------------------------------------------------------------
# 文件夹保持使用 Secondary (次色系)，为了不刺眼使用 dim 版本作为主体
COLOR_FOLDER_BODY=$MAIN_COLOR      # 主体 (原 #a4caee)
COLOR_FOLDER_TOP=$MAIN_HILIGHT                 # 顶部高光/符号 (原 #afd4ff)
COLOR_FOLDER_SHADOW=$MAIN_SHADOW    # 阴影/渐变暗部 (原 #438de6)

# ------------------------------------------------------------------------------
# [2] 网络与垃圾桶 (network*.svg / user-trash*.svg)
# ------------------------------------------------------------------------------
# 使用 Tertiary (第三色系) 作为强调色
COLOR_ACCENT_BODY=$INVERSE_MAIN_COLOR                # 主体 (原 #1c71d8/垃圾桶身)
COLOR_ACCENT_LIGHT=$INVERSE_MAIN_HIGHLT         # 亮部 (原 #62a0ea/垃圾桶盖亮面)
COLOR_ACCENT_DARK=$INVERSE_MAIN_SHADOW       # 暗部 (原 #1a5fb4/垃圾桶内侧)
COLOR_TRASH_PAPER="{{colors.on_tertiary_container.default.hex}}"    # 废纸团颜色

# ------------------------------------------------------------------------------
# [3] 脚本与可执行文件 (text-x-script.svg / application-x-executable.svg)
# ------------------------------------------------------------------------------
# 重点修正：防止偏淡，主体使用 Primary Default (最鲜艳的主色)
# 对应 Adwaita 原版光影逻辑：
COLOR_SCRIPT_BODY=$MAIN_SHADOW                  # 主体 (原 #3584e4 - 基准蓝)
COLOR_SCRIPT_HIGHLIGHT=$MAIN_HILIGHT       # 高光 (原 #99c1f1 - 亮蓝)
COLOR_SCRIPT_MID="#f0f0f0"         # 侧面/次亮 (原 #62a0ea)
COLOR_SCRIPT_SHADOW=$MAIN_SHADOW      # 阴影 (原 #1c71d8)
COLOR_SCRIPT_GEAR=$MAIN_DARKER_SHADOW    # 齿轮/最深色 
COLOR_SCRIPT_PALE="ffffff"           # 极亮部 (原 #d7e8fc)

# ------------------------------------------------------------------------------
# [4] 网页地球仪 (text-html.svg)
# ------------------------------------------------------------------------------
# [新增] 极高光/反光 (原 #b3d3f9, #d7e8fc) 
# 建议：使用 secondary_fixed (通常比 dim 更亮) 或 surface_bright
COLOR_HTML_PALE="#f0f0f0"
COLOR_HTML_HIGHLIGHT=$MAIN_HILIGHT              # 中间向左上一级左上反光 (原 #99c1f1)
COLOR_HTML_BODY=$MAIN_SHADOW                     # 球体中间 (原 #62a0ea)
COLOR_HTML_MID=$MAIN_SHADOW # 球体中间向右下一级 (原 #3584e4)
COLOR_HTML_SHADOW=$MAIN_DARKER_SHADOW     # 右下 (原 #1c71d8)
COLOR_HTML_DEEP="{{colors.surface_container.default.hex}}"  # 最右下 (原 #1a5fb4)
# [新增] 纸张背景 (原 #f6f5f4, #deddda) - 
COLOR_DOC_PAPER=$PAPER_COLOR                     
COLOR_DOC_FOLD=$PAPER_FOLE_COLOR                      

# ------------------------------------------------------------------------------
# [5] 插件图标 (application-x-addon.svg)
# ------------------------------------------------------------------------------
# 你的要求：必须和 Folder (Secondary) 颜色一致
COLOR_ADDON_BODY=$MAIN_COLOR       # 主体 (原 #3584e4 -> 对应 Folder Body)
COLOR_ADDON_HIGHLIGHT=$MAIN_HILIGHT            # 高光 (原 #98c1f1 -> 对应 Folder Top)
COLOR_ADDON_SHADOW=$MAIN_SHADOW     # 阴影 (原 #1c71d8 -> 对应 Folder Shadow)
COLOR_ADDON_DEEP=$MAIN_DARKER_SHADOW    # 轮廓 (原 #1a5fb4 -> 对应 Folder Deep)

# ------------------------------------------------------------------------------
# [6] 字体文件 (font-x-generic.svg)
# ------------------------------------------------------------------------------
COLOR_FONT_A=$MAIN_SHADOW                    # 字母 "A" (原 #3584e4)
COLOR_FONT_BASE=$MAIN_DARKER_SHADOW          # 底座/阴影 (原 #1a5fb4)

# ------------------------------------------------------------------------------
# [7] Office 文档 (x-office-document.svg)
# ------------------------------------------------------------------------------
COLOR_DOC_PAPER=$PAPER_COLOR                                         # 纸张白
COLOR_DOC_FOLD=$PAPER_FOLE_COLOR                                            # 折角灰
# 绿色渐变 -> 映射为 Tertiary (强调色)
COLOR_DOC_GRAD_ACCENT_START=$INVERSE_MAIN_COLOR       # 原 #50db81
COLOR_DOC_GRAD_ACCENT_END=$INVERSE_MAIN_COLOR   # 原 #8ff0a4
# 蓝色阴影 -> 映射为 Primary (主色)
COLOR_DOC_GRAD_SHADE_START=$MAIN_COLOR         # 原 #4a86cf
COLOR_DOC_GRAD_SHADE_END=$INVERSE_MAIN_COLOR # 原 #87bae1

# ------------------------------------------------------------------------------
# [8] Office 演示文稿 (x-office-presentation.svg)
# ------------------------------------------------------------------------------
# 你的要求：饼图蓝色变 Folder 色，绿色变 Accent 色
COLOR_PRES_CHART_BLUE=$MAIN_COLOR  # 饼图-蓝 (Folder Body)
COLOR_PRES_CHART_BLUE_DEEP=$MAIN_SHADOW # 饼图-深蓝 (Folder Shadow)
COLOR_PRES_CHART_GREEN=$INVERSE_MAIN_COLOR            # 饼图-绿 (Accent Body)
COLOR_PRES_CHART_GREEN_DEEP=$INVERSE_MAIN_SHADOW # 饼图-深绿 (Accent Dark)
# 支架颜色 (保持中性灰或微调)
COLOR_PRES_STAND_DARK="{{colors.outline.default.hex}}"
COLOR_PRES_STAND_LIGHT="{{colors.outline.default.hex}}"
# ------------------------------------------------------------------------------
# [10] 音频文件 (audio-x-generic.svg)
# ------------------------------------------------------------------------------
# 对应之前的光影逻辑，映射到 Tertiary (第三色系) 以保持与其他图标的区别
# 逻辑：Pale > Highlight > Body > Shadow > Deep
COLOR_AUDIO_PALE="{{colors.tertiary_fixed.default.hex}}"        # 最亮高光 (原 #8ff0a4)
COLOR_AUDIO_HIGHLIGHT=$INVERSE_MAIN_HIGHLT                      # 鲜艳高光 (原 #38ec8b, #38f39d)
COLOR_AUDIO_BODY=$INVERSE_MAIN_COLOR                            # 主体 (原 #33d17a, #2dbd7d)
COLOR_AUDIO_SHADOW=$INVERSE_MAIN_SHADOW                         # 阴影/过渡 (原 #26a269)
COLOR_AUDIO_DEEP="{{colors.on_tertiary_container.default.hex}}" # 最深轮廓 (原 #1a6842)

# ==============================================================================
# [二] 核心逻辑与 Sed 规则生成
# ==============================================================================

# 1. 文件夹规则
CMD_FOLDER="
s/#a4caee/$COLOR_FOLDER_BODY/g;
s/#438de6/$COLOR_FOLDER_SHADOW/g;
s/#62a0ea/$COLOR_FOLDER_SHADOW/g;
s/#afd4ff/$COLOR_FOLDER_TOP/g;
s/#c0d5ea/$COLOR_FOLDER_TOP/g"

# 2. 网络规则
CMD_NETWORK="
s/#62a0ea/$COLOR_ACCENT_LIGHT/g;
s/#1c71d8/$COLOR_ACCENT_BODY/g;
s/#c0bfbc/$COLOR_ACCENT_BODY/g;
s/#1a5fb4/$COLOR_ACCENT_DARK/g;
s/#14498a/$COLOR_ACCENT_DARK/g;
s/#9a9996/$COLOR_ACCENT_DARK/g;
s/#77767b/$COLOR_FOLDER_SHADOW/g;
s/#241f31/$COLOR_FOLDER_SHADOW/g;
s/#3d3846/$COLOR_FOLDER_SHADOW/g"


# 3. 垃圾桶规则
CMD_TRASH="
s/#2ec27e/$COLOR_ACCENT_BODY/g;
s/#33d17a/$COLOR_ACCENT_BODY/g;
s/#26a269/$COLOR_ACCENT_DARK/g;
s/#26a168/$COLOR_ACCENT_DARK/g;
s/#9a9996/$COLOR_ACCENT_DARK/g;
s/#c3c2bc/$COLOR_ACCENT_DARK/g;
s/#42d390/$COLOR_ACCENT_LIGHT/g;
s/#ffffff/$COLOR_FOLDER_SHADOW/g;
s/#deddda/$COLOR_TRASH_PAPER/g;
s/#f6f5f4/$COLOR_TRASH_PAPER/g;
s/#77767b/$COLOR_FOLDER_SHADOW/g"

# 4. 脚本/可执行文件规则 (核心光影修正)
CMD_SCRIPT="
s/#3584e4/$COLOR_SCRIPT_BODY/g;
s/#99c1f1/$COLOR_SCRIPT_HIGHLIGHT/g;
s/#98c1f1/$COLOR_SCRIPT_HIGHLIGHT/g;
s/#62a0ea/$COLOR_SCRIPT_MID/g;
s/#1c71d8/$COLOR_SCRIPT_SHADOW/g;
s/#1a5fb4/$COLOR_SCRIPT_GEAR/g;
s/#d7e8fc/$COLOR_SCRIPT_PALE/g;
s/#b3d3f9/$COLOR_SCRIPT_PALE/g"

# 5. 网页地球仪规则 (已补全所有 Hex)
CMD_HTML="
s/#f6f5f4/$COLOR_DOC_PAPER/g;
s/#deddda/$COLOR_DOC_FOLD/g;
s/#b3d3f9/$COLOR_HTML_PALE/g;
s/#d7e8fc/$COLOR_HTML_PALE/g;
s/#62a0ea/$COLOR_HTML_BODY/g;
s/#3584e4/$COLOR_HTML_MID/g;
s/#99c1f1/$COLOR_HTML_HIGHLIGHT/g;
s/#1c71d8/$COLOR_HTML_SHADOW/g;
s/#1a5fb4/$COLOR_HTML_DEEP/g"

# 6. Addon (拼图) 规则
CMD_ADDON="
s/#3584e4/$COLOR_ADDON_BODY/g;
s/#62a0ea/$COLOR_ADDON_HIGHLIGHT/g;
s/#98c1f1/$COLOR_ADDON_HIGHLIGHT/g;
s/#1c71d8/$COLOR_ADDON_SHADOW/g;
s/#1a5fb4/$COLOR_ADDON_DEEP/g"

# 7. Font (字体) 规则
CMD_FONT="
s/#3584e4/$COLOR_FONT_A/g;
s/#1a5fb4/$COLOR_FONT_BASE/g"

# 8. Document (文档) 规则
CMD_DOC="
s/#f6f5f4/$COLOR_DOC_PAPER/g;
s/#deddda/$COLOR_DOC_FOLD/g;
s/#50db81/$COLOR_DOC_GRAD_ACCENT_START/g;
s/#8ff0a4/$COLOR_DOC_GRAD_ACCENT_END/g;
s/#4a86cf/$COLOR_DOC_GRAD_SHADE_START/g;
s/#87bae1/$COLOR_DOC_GRAD_SHADE_END/g;
s/#d7e8fc/$COLOR_SCRIPT_PALE/g; 
s/#b3d3f9/$COLOR_SCRIPT_PALE/g"

# 9. Presentation (PPT) 规则
CMD_PRES="
s/#4a86cf/$COLOR_PRES_CHART_BLUE/g;
s/#1a5fb4/$COLOR_PRES_CHART_BLUE_DEEP/g;
s/#50db81/$COLOR_PRES_CHART_GREEN/g;
s/#26a269/$COLOR_PRES_CHART_GREEN_DEEP/g;
s/#f6f5f4/$COLOR_DOC_PAPER/g;
s/#ffffff/$COLOR_DOC_PAPER/g;
s/#414140/$COLOR_PRES_STAND_DARK/g;
s/#949390/$COLOR_PRES_STAND_LIGHT/g;
s/#d7e8fc/$COLOR_SCRIPT_PALE/g"

# 10. Audio (音频) 规则
# 精确映射 audio-x-generic.svg 中的所有绿色阶
CMD_AUDIO="
s/#1a6842/$COLOR_AUDIO_DEEP/g;
s/#26a269/$COLOR_AUDIO_SHADOW/g;
s/#2dbd7d/$COLOR_AUDIO_BODY/g;
s/#2dc47e/$COLOR_AUDIO_BODY/g;
s/#33d17a/$COLOR_AUDIO_BODY/g;
s/#38ec8b/$COLOR_AUDIO_HIGHLIGHT/g;
s/#38f39d/$COLOR_AUDIO_HIGHLIGHT/g;
s/#8ff0a4/$COLOR_AUDIO_PALE/g"
# ==============================================================================
# [三] 执行核心流程
# ==============================================================================

TEMPLATE_DIR="$HOME/.config/matugen/templates/gtk-folder/Adwaita-Matugen"
CURRENT_THEME=$(gsettings get org.gnome.desktop.interface icon-theme | tr -d "'")

if [[ "$CURRENT_THEME" == "Adwaita-Matugen-A" ]]; then
    TARGET_THEME="Adwaita-Matugen-B"
else
    TARGET_THEME="Adwaita-Matugen-A"
fi
TARGET_DIR="$HOME/.local/share/icons/$TARGET_THEME"

# 1. 准备目录
mkdir -p "$TARGET_DIR"
cp -rf --reflink=auto --no-preserve=mode,ownership "$TEMPLATE_DIR/"* "$TARGET_DIR/"
sed -i "s/Name=.*/Name=$TARGET_THEME/" "$TARGET_DIR/index.theme"

# 2. 处理 PNG (统一使用文件夹颜色)
find "$TARGET_DIR" -name "*.png" -print0 | xargs -0 -P0 -I {} magick "{}" \
    -channel RGB -colorspace gray -sigmoidal-contrast 10,50% \
    +level-colors "$COLOR_FOLDER_SHADOW","$COLOR_FOLDER_BODY" \
    +channel "{}"

# 3. 处理 SVG (分模块并行处理)

# [Group 1] Folders
find "$TARGET_DIR/scalable" \
    \( -name "folder*.svg" -o -name "user-home*.svg" -o -name "user-desktop*.svg" -o -name "user-bookmarks*.svg" -o -name "inode-directory*.svg" \) \
    -print0 | xargs -0 -P0 sed -i "$CMD_FOLDER"

# [Group 2] Network
find "$TARGET_DIR/scalable" -name "network*.svg" -print0 | xargs -0 -P0 sed -i --follow-symlinks "$CMD_NETWORK"

# [Group 3] Trash
find "$TARGET_DIR/scalable" -name "user-trash*.svg" -print0 | xargs -0 -P0 sed -i --follow-symlinks "$CMD_TRASH"

# [Group 4] Mimetypes - Script & Executable
find "$TARGET_DIR/scalable/mimetypes" \
    \( -name "text-x-script*.svg" -o -name "application-x-executable*.svg" \) \
    -print0 | xargs -0 -P0 sed -i "$CMD_SCRIPT"

# [Group 5] Mimetypes - Addon
find "$TARGET_DIR/scalable/mimetypes" -name "application-x-addon*.svg" -print0 | xargs -0 -P0 sed -i "$CMD_ADDON"

# [Group 6] Mimetypes - HTML
find "$TARGET_DIR/scalable/mimetypes" -name "text-html*.svg" -print0 | xargs -0 -P0 sed -i "$CMD_HTML"

# [Group 7] Mimetypes - Font
find "$TARGET_DIR/scalable/mimetypes" -name "font-x-generic*.svg" -print0 | xargs -0 -P0 sed -i "$CMD_FONT"

# [Group 8] Mimetypes - Document
find "$TARGET_DIR/scalable/mimetypes" -name "x-office-document*.svg" -print0 | xargs -0 -P0 sed -i "$CMD_DOC"

# [Group 9] Mimetypes - Presentation
find "$TARGET_DIR/scalable/mimetypes" -name "x-office-presentation*.svg" -print0 | xargs -0 -P0 sed -i "$CMD_PRES"
# [Group 10] Mimetypes - Audio
find "$TARGET_DIR/scalable/mimetypes" -name "audio-x-generic*.svg" -print0 | xargs -0 -P0 sed -i "$CMD_AUDIO"
# 4. 应用变更
gsettings set org.gnome.desktop.interface icon-theme "$TARGET_THEME"
flatpak override --user --env=ICON_THEME="$TARGET_THEME" 2>/dev/null || true

# 5. 同步静态配置文件：gsettings 只影响 GNOME/GTK3/GTK4 的一部分；
#    Qt（qt5ct/qt6ct）、fuzzel、xsettingsd、GTK2 各自读自己的配置文件，
#    不写它们会出现「文件夹变了但 fuzzel 图标没变」的割裂。
set_ini_key() { # file key value
    local file="$1" key="$2" value="$3"
    [[ -f "$file" ]] || return 0
    if grep -q "^${key}=" "$file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

set_ini_key "$HOME/.config/gtk-3.0/settings.ini" "gtk-icon-theme-name" "$TARGET_THEME"
set_ini_key "$HOME/.config/gtk-4.0/settings.ini" "gtk-icon-theme-name" "$TARGET_THEME"
set_ini_key "$HOME/.config/qt5ct/qt5ct.conf" "icon_theme" "$TARGET_THEME"
set_ini_key "$HOME/.config/qt6ct/qt6ct.conf" "icon_theme" "$TARGET_THEME"
set_ini_key "$HOME/.config/fuzzel/fuzzel.ini" "icon-theme" "$TARGET_THEME"

# xsettingsd 值带引号，单独处理
XSETTINGSD_CONFIG="$HOME/.config/xsettingsd/xsettingsd.conf"
if [[ -f "$XSETTINGSD_CONFIG" ]]; then
    if grep -q "^Net/IconThemeName" "$XSETTINGSD_CONFIG" 2>/dev/null; then
        sed -i "s|^Net/IconThemeName.*|Net/IconThemeName \"$TARGET_THEME\"|" "$XSETTINGSD_CONFIG"
    else
        echo "Net/IconThemeName \"$TARGET_THEME\"" >> "$XSETTINGSD_CONFIG"
    fi
    pkill -HUP xsettingsd 2>/dev/null || true
fi

# GTK2 配置
gtk2_config="$HOME/.gtkrc-2.0"
if grep -q "^gtk-icon-theme-name=" "$gtk2_config" 2>/dev/null; then
    sed -i "s|^gtk-icon-theme-name=.*|gtk-icon-theme-name=\"$TARGET_THEME\"|" "$gtk2_config"
else
    echo "gtk-icon-theme-name=\"$TARGET_THEME\"" >> "$gtk2_config"
fi

exit 0
