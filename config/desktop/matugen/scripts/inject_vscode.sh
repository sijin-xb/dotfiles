#!/bin/bash

# 1. 强制指定 Visual Studio Code (官方版) 的路径
VSCODE_SETTINGS="$HOME/.config/Code/User/settings.json"
GENERATED_COLORS="$HOME/.cache/matugen_vscode_inject.json"
if pacman -Qq | grep visual-studio-code; then 

# 2. 如果配置文件不存在，创建一个空的 (防止报错)
if [ ! -f "$VSCODE_SETTINGS" ]; then
    mkdir -p "$(dirname "$VSCODE_SETTINGS")"
    echo "{}" > "$VSCODE_SETTINGS"
fi

# 3. 注入逻辑：合并颜色配置
# 这一步会保留你原本的字体、字号等设置，只覆盖颜色部分
tmp=$(mktemp)
if jq -s '.[0] * .[1]' "$VSCODE_SETTINGS" "$GENERATED_COLORS" > "$tmp"; then
    mv "$tmp" "$VSCODE_SETTINGS"
    echo "✅ VS Code colors updated (Dark/Light adaptive)."
else
    echo "❌ Injection failed."
    rm "$tmp"
    exit 1
fi
fi
