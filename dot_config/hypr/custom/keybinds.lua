hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )

local function shell(command)
    return hl.dsp.exec_cmd("sh -lc '" .. command:gsub("'", "'\\''") .. "'")
end

-- Niri-compatible personal shortcuts that do not replace end-4 defaults.
hl.bind("SUPER + F1", shell("pkill fcitx5 || fcitx5 -d"), { description = "Toggle input method" })
hl.bind("SUPER + F10", shell("waypaper --random"), { description = "Random wallpaper" })
hl.bind("SUPER + SHIFT + F10", shell("$HOME/.config/scripts/random-anime-wallpaper.sh"), { description = "Download random wallpaper" })
hl.bind("SUPER + F12",
    shellIsCaelestia and hl.dsp.global("caelestia:screenshotFreeze")
        or hl.dsp.global("quickshell:regionScreenshot"),
    { description = "Screenshot region" })
-- 【已让位给快捷键管理器】
-- 官方 hyprland/keybinds.lua 里 SUPER + / 绑的是
-- hl.dsp.global("quickshell:cheatsheetToggle")（快捷键速查表）。
-- 本文件原先用同一键位覆盖成 quick terminal，导致速查表永远打不开。
-- 按需求让位：删掉这条覆盖，官方那条即重新生效。
-- 注意**不要**在这里再补一条同样的绑定 —— 同键位两条会同时触发，
-- 速查表会「开一次又关一次」，看起来像没反应。
-- quick terminal 若仍需要，换个键位另绑即可。

hl.bind("SUPER + L", hl.dsp.global("quickshell:lock"), { description = "Lock screen（Quickshell 媒体面板）" })
hl.bind("SUPER + ALT + T", shell("$HOME/.config/scripts/matugen-select-type.sh"), { description = "Change color strategy" })
hl.bind("SUPER + U", hl.dsp.focus({ workspace = "r-" .. "1" }), { description = "Previous workspace" })
hl.bind("SUPER + CTRL + U", hl.dsp.window.move({ workspace = "r-1" }), { description = "Move window to previous workspace" })
hl.bind("SUPER + CTRL + I", hl.dsp.window.move({ workspace = "r+1" }), { description = "Move window to next workspace" })

-- 滚动布局下 Super+滚轮 切窗口，其他布局切工作区
hl.unbind("SUPER + mouse_up")
hl.unbind("SUPER + mouse_down")

local function scroll_focus(forward)
    local ws = hl.get_active_special_workspace() or hl.get_active_workspace()
    if not ws then return end
    if ws.tiled_layout == "scrolling" then
        hl.dispatch(hl.dsp.layout("focus " .. (forward and "r" or "l")))
    else
        hl.dispatch(hl.dsp.focus({ workspace = (forward and "+1" or "-1") }))
    end
end
hl.bind("SUPER + mouse_down", function() scroll_focus(true) end,
    { description = "Scroll: next window (scrolling) / next workspace" })
hl.bind("SUPER + mouse_up", function() scroll_focus(false) end,
    { description = "Scroll: previous window (scrolling) / previous workspace" })

-- ===================== Caelestia 全局快捷键 =====================
-- caelestia 的快捷键走 Hyprland global shortcut（appid = "caelestia"），
-- 只有 caelestia 在跑时才会被注册；换回 end4-PC 时这些键自动变哑，两套可以共存。
-- 面板/抽屉本身也能点状态栏打开，这里只是补键位。
--
-- end4-PC 专属的 quickshell:* 全局绑定已经在 hyprland/keybinds.lua 里按
-- shellIsCaelestia 从源头跳过（见那边的 qsBind），这里不用再逐个擦。
-- 只有下面这 4 个键例外：base 在它们身上除了 global 还绑了「真的会执行」的
-- exec 兜底（`qs ... ipc call TEST_ALIVE || 兜底`，TEST_ALIVE 这个 IPC target
-- 在配置里不存在，所以 `||` 后面的兜底永远会跑），得单独 unbind。
if shellIsCaelestia then
    hl.unbind("SUPER + L")             -- base: loginctl lock-session（锁了个寂寞，见 hypridle.conf）
    hl.unbind("SUPER + V")             -- base: end4-PC cliphist/fuzzel 兜底
    hl.unbind("CTRL + ALT + Delete")   -- base: wlogout 兜底
    hl.unbind("XF86MonBrightnessUp")   -- base: brightnessctl 5%+ 兜底
    hl.unbind("XF86MonBrightnessDown") -- base: brightnessctl 5%- 兜底
    -- base 在 SUPER+SHIFT+S 上有一条 hyprshot 兜底（`qs ... || hyprshot --freeze
    -- --clipboard-only ...`）。它和 caelestia 的截图器会**同时**启动、抢同一个
    -- slurp，结果两个区域选择器打架 —— 看起来就是「截图坏了」。下面换成
    -- caelestia 原生的 freeze+clipboard 变体，所以这条兜底必须先擦掉。
    hl.unbind("SUPER + SHIFT + S")

    -- ---- 沿用 end4-PC 的习惯键位（映射到 caelestia 的等价功能） ----
    -- 剪贴板：必须先擦掉 base 的普通 hl.bind，再启动 caelestia 自己的
    -- cliphist + fuzzel 入口；否则两条绑定会同时触发，旧兜底会抢焦点。
    hl.bind("SUPER + V", shell("caelestia clipboard"),
        { description = "Caelestia: 剪贴板历史" })

    -- end4-PC 的 SUPER+I 是 quickshell 设置面板；caelestia 里「设置」就是 nexus
    -- （launcher 的 Settings action 命令正是 `caelestia shell nexus open`，
    -- 描述 "Configure the shell"）。所以直接开 nexus。
    hl.bind("SUPER + I", hl.dsp.global("caelestia:nexus"),
        { description = "Caelestia: 设置 / 控制中心（nexus）" })

    -- end4-PC 的 CTRL+ALT+T 是 quickshell 壁纸选择器。caelestia **没有**独立的
    -- 壁纸选择器窗口 —— 换壁纸的 UI 是启动器的 `>wallpaper` 列表（nexus 的
    -- 「壁纸与风格」页是另一个入口，但没有 IPC 能直达那一页）。
    -- 所以这里：确保启动器打开 → 用 wtype 把前缀打进搜索框。
    -- 启动器没有可预填搜索文本的 IPC，只能模拟输入；等 0.4s 是留给开启动画，
    -- 打开时 SearchBar 会 forceActiveFocus，输入才会落进搜索框。
    -- 已经开着就不要再 toggle（否则会把启动器关掉、按键打到别处）。
    hl.bind("CTRL + ALT + T", shell(
        '[ "$(qs -c caelestia ipc call drawers isOpen launcher)" = 1 ] || qs -c caelestia ipc call drawers toggle launcher; sleep 0.4; wtype ">wallpaper "'
    ), { description = "Caelestia: 壁纸选择器（启动器 >wallpaper）" })

    -- 其余 end4-PC 键位里 caelestia 有等价功能的，一并接上。
    -- 这些键在 caelestia 下原本都是死的：要么是纯 quickshell global 被 qsBind
    -- 从源头跳过、要么压根没有 exec fallback。
    -- 左栏：end4-PC 有左右两条侧栏，caelestia 只有一条 sidebar
    hl.bind("SUPER + B", hl.dsp.global("caelestia:sidebar"),
        { description = "Caelestia: 侧栏（= end4-PC 左栏）" })
    hl.bind("SUPER + O", hl.dsp.global("caelestia:sidebar"),
        { description = "Caelestia: 侧栏（= end4-PC 左栏）" })
    -- 媒体控制：end4-PC 有独立面板，caelestia 的媒体在 dashboard 里
    hl.bind("SUPER + M", hl.dsp.global("caelestia:dashboard"),
        { description = "Caelestia: 仪表盘（含媒体控制）" })
    -- 随机壁纸：end4-PC 是 quickshell:wallpaperSelectorRandom，对应 caelestia CLI
    hl.bind("CTRL + SUPER + ALT + T", shell("caelestia wallpaper -r"),
        { description = "Caelestia: 随机壁纸" })
    -- 明暗模式切换：end4-PC 是 quickshell:toggleLightDark，对应 caelestia scheme
    hl.bind("CTRL + SUPER + SHIFT + D", shell(
        'if [ "$(caelestia scheme get -m)" = dark ]; then caelestia scheme set -m light; else caelestia scheme set -m dark; fi'
    ), { description = "Caelestia: 切换明暗模式" })

    -- 面板 / 抽屉
    hl.bind("SUPER + SUPER_L", hl.dsp.global("caelestia:launcher"),
        { release = true, description = "Caelestia: 启动器（输 >wallpaper 换壁纸）" })
    hl.bind("SUPER + SUPER_R", hl.dsp.global("caelestia:launcher"),
        { release = true, description = "Caelestia: 启动器（右 Super）" })
    hl.bind("SUPER + K", hl.dsp.global("caelestia:showall"),
        { description = "Caelestia: 启动器 + 仪表盘 + OSD" })
    hl.bind("SUPER + A", hl.dsp.global("caelestia:dashboard"),
        { description = "Caelestia: 仪表盘" })
    hl.bind("SUPER + N", hl.dsp.global("caelestia:sidebar"),
        { description = "Caelestia: 侧栏" })
    hl.bind("SUPER + G", hl.dsp.global("caelestia:utilities"),
        { description = "Caelestia: 工具抽屉" })
    hl.bind("SUPER + R", hl.dsp.global("caelestia:nexus"),
        { description = "Caelestia: 控制中心（壁纸 / 主题 / 服务）" })

    -- 会话 / 通知 / 锁屏
    hl.bind("CTRL + ALT + Delete", hl.dsp.global("caelestia:session"),
        { description = "Caelestia: 会话菜单（注销 / 重启 / 关机）" })
    hl.bind("CTRL + ALT + C", hl.dsp.global("caelestia:clearNotifs"),
        { locked = true, description = "Caelestia: 清空所有通知" })
    hl.bind("SUPER + L", hl.dsp.global("caelestia:lock"),
        { description = "Caelestia: 锁屏" })

    -- 截图：统一用 caelestia 原生工具（caelestia:screenshot*）。
    -- end4-PC 的 Print / SHIFT+Print 是**纯** quickshell global —— 不像
    -- SUPER+SHIFT+S 还挂着一条 hyprshot 兜底，它们没有任何 fallback，
    -- caelestia 下被 qsBind 从源头跳过之后就是彻底没反应。
    hl.bind("Print", hl.dsp.global("caelestia:screenshotFreeze"),
        { locked = true, description = "Caelestia: 截图（区域，冻结画面）" })
    hl.bind("SHIFT + Print", hl.dsp.global("caelestia:screenshot"),
        { locked = true, description = "Caelestia: 截图（区域，实时画面）" })
    -- end4-PC 的 SUPER+SHIFT+S 兜底是 hyprshot --freeze --clipboard-only，
    -- 语义 = 冻结 + 进剪贴板，对应 caelestia 的 FreezeClip 变体。
    hl.bind("SUPER + SHIFT + S", hl.dsp.global("caelestia:screenshotFreezeClip"),
        { description = "Caelestia: 截图（区域，冻结 → 剪贴板）" })
    hl.bind("SUPER + SHIFT + ALT + S", hl.dsp.global("caelestia:screenshotClip"),
        { description = "Caelestia: 截图（区域 → 剪贴板）" })

    -- 亮度：交给 caelestia，才会有它自己的亮度 OSD。
    -- 官方只给了 locked；这里额外加 repeating，保持原来长按连续调的手感。
    hl.bind("XF86MonBrightnessUp", hl.dsp.global("caelestia:brightnessUp"),
        { locked = true, repeating = true })
    hl.bind("XF86MonBrightnessDown", hl.dsp.global("caelestia:brightnessDown"),
        { locked = true, repeating = true })

    -- 媒体：用官方键位。
    -- XF86 那几个硬件键刻意不动 —— 它们已经绑了 playerctl，再叠一层
    -- caelestia:media* 会把 play-pause / next 触发两次，等于按了没反应。
    hl.bind("CTRL + SUPER + Space", hl.dsp.global("caelestia:mediaToggle"),
        { locked = true, description = "Caelestia: 播放 / 暂停" })
    hl.bind("CTRL + SUPER + Equal", hl.dsp.global("caelestia:mediaNext"),
        { locked = true, description = "Caelestia: 下一首" })
    hl.bind("CTRL + SUPER + Minus", hl.dsp.global("caelestia:mediaPrev"),
        { locked = true, description = "Caelestia: 上一首" })
    hl.bind("CTRL + SUPER + Backspace", hl.dsp.global("caelestia:mediaStop"),
        { locked = true, description = "Caelestia: 停止播放" })
end
