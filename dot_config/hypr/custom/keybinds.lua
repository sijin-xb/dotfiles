hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )

local function shell(command)
    return hl.dsp.exec_cmd("sh -lc '" .. command:gsub("'", "'\\''") .. "'")
end

-- Niri-compatible personal shortcuts that do not replace end-4 defaults.
hl.bind("SUPER + F1", shell("pkill fcitx5 || fcitx5 -d"), { description = "Toggle input method" })
hl.bind("SUPER + F10", shell("waypaper --random"), { description = "Random wallpaper" })
hl.bind("SUPER + SHIFT + F10", shell("$HOME/.config/scripts/random-anime-wallpaper.sh"), { description = "Download random wallpaper" })
hl.bind("SUPER + F12", hl.dsp.global("quickshell:regionScreenshot"), { description = "Screenshot region" })
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
