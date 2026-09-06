#!/bin/bash

CACHE_DIR="$HOME/.cache/matugen-strategy"
TYPE_FILE="$CACHE_DIR/type"
MODE_FILE="$CACHE_DIR/mode"
INDEX_MODE_FILE="$CACHE_DIR/index_mode"
UPDATE_SCRIPT="$HOME/.config/scripts/matugen-update.sh"
WAYPAPER_CONFIG="$HOME/.config/waypaper/config.ini"

# --- 0. 确保缓存目录存在 ---
if [ ! -d "$CACHE_DIR" ]; then
    mkdir -p "$CACHE_DIR"
fi

# --- 1. 自动检测语言环境 ---
if env | grep -q "zh_CN"; then
    IS_CN=true
else
    IS_CN=false
fi

# --- 2. 读取当前模式 (Toggle) ---
CURRENT_MODE="dark"
if [ -f "$MODE_FILE" ]; then
    READ_MODE=$(cat "$MODE_FILE")
    if [[ "$READ_MODE" == "light" ]]; then
        CURRENT_MODE="light"
    fi
fi

CURRENT_INDEX_MODE="0" # 【修改點】：預設為 0
if [ -f "$INDEX_MODE_FILE" ]; then
    READ_INDEX_MODE=$(cat "$INDEX_MODE_FILE")
    if [[ "$READ_INDEX_MODE" == "random" ]]; then
        CURRENT_INDEX_MODE="random"
    fi
fi

# --- 3. 定义选项 (动态生成 Toggle 行) ---

# 模式 Toggle
if [ "$CURRENT_MODE" == "dark" ]; then
    if [ "$IS_CN" = true ]; then MODE_OPTION=">> 切换到亮色模式"; else MODE_OPTION=">> Switch to Light"; fi
else
    if [ "$IS_CN" = true ]; then MODE_OPTION=">> 切换到暗色模式"; else MODE_OPTION=">> Switch to Dark"; fi
fi

# 颜色 Index Toggle 
if [ "$CURRENT_INDEX_MODE" == "random" ]; then
    if [ "$IS_CN" = true ]; then INDEX_OPTION=">> 切换到第一主色"; else INDEX_OPTION=">> Switch to First Color"; fi
else
    if [ "$IS_CN" = true ]; then INDEX_OPTION=">> 切换到随机/轮换主色"; else INDEX_OPTION=">> Switch to Random/Cycle Color"; fi
fi

# 重新生成选项
if [ "$IS_CN" = true ]; then
    REGEN_OPTION=">> 重新生成"
else
    REGEN_OPTION=">> Regenerate"
fi

# 定义配色策略列表
if [ "$IS_CN" = true ]; then
    SCHEMES="默认点调 (scheme-tonal-spot)
鲜艳模式 (scheme-vibrant)
水果沙拉 (scheme-fruit-salad)
忠实还原 (scheme-fidelity)
表现增强 (scheme-expressive)
中性柔和 (scheme-neutral)
单色黑白 (scheme-monochrome)
彩虹混色 (scheme-rainbow)
内容优先 (scheme-content)"
    PROMPT_TEXT="Matugen 设置 > "
else
    SCHEMES="scheme-tonal-spot
scheme-fruit-salad
scheme-vibrant
scheme-fidelity
scheme-expressive
scheme-neutral
scheme-monochrome
scheme-rainbow
scheme-content"
    PROMPT_TEXT="Matugen Config > "
fi

# 合并选项
OPTIONS="${MODE_OPTION}
${INDEX_OPTION}
${REGEN_OPTION}
--------------------
${SCHEMES}"

# --- 4. Fuzzel 菜单 ---
SELECTED_LINE=$(echo "$OPTIONS" | fuzzel -d --prompt="$PROMPT_TEXT" --lines=14)

if [ -z "$SELECTED_LINE" ]; then
    exit 0
fi

# 过滤掉分隔线
if [[ "$SELECTED_LINE" == *"----"* ]]; then
    exit 0
fi

# --- 5. 提取真实参数 ---
# 通过字符串匹配识别控制选项
if [[ "$SELECTED_LINE" == *">>"* ]]; then
    if [[ "$SELECTED_LINE" == *"亮色"* ]] || [[ "$SELECTED_LINE" == *"Light"* ]]; then
        REAL_VALUE="light"
    elif [[ "$SELECTED_LINE" == *"暗色"* ]] || [[ "$SELECTED_LINE" == *"Dark"* ]]; then
        REAL_VALUE="dark"
    elif [[ "$SELECTED_LINE" == *"第一"* ]] || [[ "$SELECTED_LINE" == *"First"* ]]; then
        REAL_VALUE="0"
    elif [[ "$SELECTED_LINE" == *"随机"* ]] || [[ "$SELECTED_LINE" == *"Random"* ]]; then
        REAL_VALUE="random"
    elif [[ "$SELECTED_LINE" == *"重新生成"* ]] || [[ "$SELECTED_LINE" == *"Regenerate"* ]]; then
        REAL_VALUE="regenerate"
    fi
else
    # 否则是具体策略，继续提取括号里的内容
    REAL_VALUE=$(echo "$SELECTED_LINE" | awk '{print $NF}' | tr -d '()')
fi

# --- 6. 执行逻辑 ---
if [ -n "$REAL_VALUE" ]; then
    
    # 根据 REAL_VALUE 保存对应的状态文件
    if [[ "$REAL_VALUE" == "regenerate" ]]; then
        # 仅触发更新，不修改任何文件状态
        if [ "$IS_CN" = true ]; then NOTIFY_MSG="正在重新生成颜色..."; else NOTIFY_MSG="Regenerating colors..."; fi
    elif [[ "$REAL_VALUE" == "dark" ]] || [[ "$REAL_VALUE" == "light" ]]; then
        echo "$REAL_VALUE" > "$MODE_FILE"
        if [ "$IS_CN" = true ]; then NOTIFY_MSG="已切换为: $REAL_VALUE"; else NOTIFY_MSG="Mode updated to: $REAL_VALUE"; fi
    elif [[ "$REAL_VALUE" == "0" ]] || [[ "$REAL_VALUE" == "random" ]]; then
        echo "$REAL_VALUE" > "$INDEX_MODE_FILE"
        if [ "$IS_CN" = true ]; then NOTIFY_MSG="颜色模式更新为: $REAL_VALUE"; else NOTIFY_MSG="Color strategy updated to: $REAL_VALUE"; fi
    else
        echo "$REAL_VALUE" > "$TYPE_FILE"
        if [ "$IS_CN" = true ]; then NOTIFY_MSG="色彩策略更新为: $REAL_VALUE"; else NOTIFY_MSG="Scheme updated to: $REAL_VALUE"; fi
    fi

    # 发送通知
    notify-send "Matugen" "$NOTIFY_MSG"

    # 【修改】：直接调用带有 -f 参数的更新脚本。
    # 这样可以让 update.sh 自己去走那套完善的 awww + niri 的多显示器逻辑，更加安全精确。
    if [ -x "$UPDATE_SCRIPT" ]; then
        "$UPDATE_SCRIPT" -f
    else
        notify-send "Error" "脚本未找到: $UPDATE_SCRIPT"
    fi
fi
