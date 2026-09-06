require("hyprland.lib")
require("hyprland.variables")
if is_file_exists(HOME .. "/.config/hypr/custom/variables.lua") then
    require("custom.variables")
end

local qsScripts = "$HOME/.config/quickshell/$qsConfig/scripts"
local hyprScripts = "$HOME/.config/hypr/hyprland/scripts"
local qsIpcCall = "qs -c $qsConfig ipc call"
local qsIsAlive = qsIpcCall .. " TEST_ALIVE"
local fullScreenshot = "mkdir -p \"$HOME/Pictures/Screenshots/Hyprland-screenshots\" && save_path=\"$HOME/Pictures/Screenshots/Hyprland-screenshots/screenshot-$(date '+%Y-%m-%d_%H-%M-%S').png\" && grim \"$save_path\" && wl-copy -t image/png < \"$save_path\" && notify-send '屏幕截图' '已保存并复制到剪贴板'"

hl.bind("SUPER + SUPER_L", hl.dsp.global("quickshell:searchToggleRelease"), { description = "Shell: Toggle search" })
hl.bind("SUPER + SUPER_R", hl.dsp.global("quickshell:searchToggleRelease"))

hl.bind("SUPER_L", hl.dsp.global("quickshell:workspaceNumber"), { ignore_mods = true, transparent = true })
hl.bind("SUPER_R", hl.dsp.global("quickshell:workspaceNumber"), { ignore_mods = true, transparent = true })
hl.bind("SUPER_L", hl.dsp.global("quickshell:workspaceNumber"),
    { ignore_mods = true, transparent = true, release = true })
hl.bind("SUPER_R", hl.dsp.global("quickshell:workspaceNumber"),
    { ignore_mods = true, transparent = true, release = true })
hl.bind("SUPER + Tab", hl.dsp.global("quickshell:overviewWorkspacesToggle"), { description = "Shell: Toggle overview" })
hl.bind("SUPER + V", hl.dsp.global("quickshell:overviewClipboardToggle"))
hl.bind("SUPER + Period", hl.dsp.global("quickshell:overviewEmojiToggle"))
-- NOTE: hl.dsp.exec_cmd is broken in this Hyprland build (spawns nothing),
-- so exec-style binds use a Lua callback + hl.exec_cmd instead
-- setprop is broken too, so we toggle opacity via hl.config directly
local _opacity_state = 0.65
hl.bind("SUPER + A", function()
    if _opacity_state == 0.65 then
        _opacity_state = 1.0
    else
        _opacity_state = 0.65
    end
    hl.config({ decoration = { active_opacity = _opacity_state } })
end, { description = "Shell: Toggle active window opacity" })
hl.bind("SUPER + ALT + A", hl.dsp.global("quickshell:sidebarLeftToggleDetach"))
hl.bind("SUPER + B", hl.dsp.global("quickshell:sidebarLeftToggle"))
hl.bind("SUPER + O", hl.dsp.global("quickshell:sidebarLeftToggle"))
hl.bind("SUPER + N", hl.dsp.global("quickshell:sidebarRightToggle"), { description = "Shell: Toggle right sidebar" })
hl.bind("SUPER + Slash", hl.dsp.global("quickshell:cheatsheetToggle"), { description = "Shell: Toggle cheatsheet" })
hl.bind("SUPER + K", hl.dsp.global("quickshell:oskToggle"), { description = "Shell: Toggle on-screen keyboard" })
hl.bind("SUPER + M", hl.dsp.global("quickshell:mediaControlsToggle"), { description = "Shell: Toggle media controls" })
hl.bind("SUPER + G", hl.dsp.global("quickshell:overlayToggle"), { description = "Shell: Toggle widget overlay" })
hl.bind("CTRL + ALT + Delete", hl.dsp.global("quickshell:sessionToggle"), { description = "Shell: Toggle session menu" })
hl.bind("SUPER + J", hl.dsp.global("quickshell:barToggle"), { description = "Shell: Toggle bar" })
hl.bind("CTRL + ALT + Delete", function() hl.exec_cmd(qsIsAlive .. " || pkill wlogout || wlogout -p layer-shell") end)
hl.bind("SHIFT + SUPER + ALT + Slash", function() hl.exec_cmd("qs -p $HOME/.config/quickshell/$qsConfig/welcome.qml") end)

hl.bind("XF86MonBrightnessUp", function() hl.exec_cmd(qsIpcCall .. " brightness increment || brightnessctl s 5%+") end,
    { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", function() hl.exec_cmd(qsIpcCall .. " brightness decrement || brightnessctl s 5%-") end,
    { locked = true, repeating = true })
hl.bind("XF86AudioRaiseVolume", function() hl.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+ -l 1.5") end,
    { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", function() hl.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-") end,
    { locked = true, repeating = true })

hl.bind("CTRL + SUPER + T", hl.dsp.global("quickshell:wallpaperSelectorToggle"),
    { description = "Shell: Change wallpaper" })
hl.bind("CTRL + SUPER + ALT + T", hl.dsp.global("quickshell:wallpaperSelectorRandom"),
    { description = "Shell: Random wallpaper" })
hl.bind("CTRL + SUPER + SHIFT + D", hl.dsp.global("quickshell:toggleLightDark"),
    { description = "Shell: Toggle light/dark mode" })
hl.bind("CTRL + SUPER + T", function() hl.exec_cmd(qsIsAlive .. " || " .. qsScripts .. "/colors/switchwall.sh") end)
hl.bind("CTRL + SUPER + R", function() hl.exec_cmd("killall ydotool qs quickshell; qs -c $qsConfig &") end,
    { description = "Shell: Restart widgets" })
hl.bind("CTRL + SUPER + P", hl.dsp.global("quickshell:panelFamilyCycle"), { description = "Shell: Cycle panel family" })

--##! Utilities
--# Screenshot, Record, OCR, Color picker, Clipboard history
hl.bind("SUPER + V", function() hl.exec_cmd(
        qsIsAlive .. " || pkill fuzzel || cliphist list | fuzzel --match-mode fzf --dmenu | cliphist decode | wl-copy") end,
    { description = "Utilities: Clipboard history >> clipboard" })
hl.bind("SUPER + Period", function() hl.exec_cmd(
        qsIsAlive .. " || pkill fuzzel || " .. hyprScripts .. "/fuzzel-emoji.sh copy") end,
    { description = "Utilities: Emoji >> clipboard" })
hl.bind("SUPER + SHIFT + S", hl.dsp.global("quickshell:regionScreenshot"), { description = "Utilities: Screen snip" })
hl.bind("SUPER + SHIFT + S",
    function() hl.exec_cmd(qsIsAlive .. " || pidof slurp || hyprshot --freeze --clipboard-only --mode region --silent") end)
hl.bind("SUPER + SHIFT + A", hl.dsp.global("quickshell:regionSearch"), { description = "Utilities: Google Lens" })
hl.bind("SUPER + SHIFT + A", function() hl.exec_cmd(qsIsAlive .. " || pidof slurp || " .. hyprScripts .. "/snip_to_search.sh") end)
--# OCR
hl.bind("SUPER + SHIFT + X", hl.dsp.global("quickshell:regionOcr"),
    { description = "Utilities: Character recognition >> clipboard" })
hl.bind("SUPER + SHIFT + T", hl.dsp.global("quickshell:screenTranslate"),
    { description = "Utilities: Translate screen content" })
hl.bind("SUPER + SHIFT + X", function() hl.exec_cmd(
    qsIsAlive ..
    " || pidof slurp || grim -g \"$(slurp $SLURP_ARGS)\" \"/tmp/ocr_image.png\" && tesseract \"/tmp/ocr_image.png\" stdout -l $(tesseract --list-langs | awk 'NR>1{print $1}' | tr '\\\\n' '+' | sed 's/\\\\+$/\\\\n/') | wl-copy && rm \"/tmp/ocr_image.png\""
) end)
--# Color picker
hl.bind("SUPER + SHIFT + C", function() hl.exec_cmd("hyprpicker -a") end,
    { description = "Utilities: Pick color #RRGGBB >> clipboard" })
--# Recording stuff
hl.bind("SUPER + SHIFT + R", hl.dsp.global("quickshell:regionRecord"),
    { locked = true, description = "Utilities: Record region (no sound)" })
hl.bind("SUPER + SHIFT + R", function() hl.exec_cmd(qsIsAlive .. " || " .. qsScripts .. "/videos/record.sh") end, { locked = true })
hl.bind("SUPER + ALT + R", hl.dsp.global("quickshell:regionRecord"), { locked = true })
hl.bind("SUPER + ALT + R", function() hl.exec_cmd(qsIsAlive .. " || " .. qsScripts .. "/videos/record.sh") end, { locked = true })
hl.bind("CTRL + ALT + R", function() hl.exec_cmd(qsScripts .. "/videos/record.sh --fullscreen") end, { locked = true })
hl.bind("SUPER + SHIFT + ALT + R", function() hl.exec_cmd(qsScripts .. "/videos/record.sh --fullscreen --sound") end,
    { locked = true, description = "Utilities: Record screen (with sound)" })
--# Screenshot entry points use end-4's region selector and action menu.
hl.bind("Print", hl.dsp.global("quickshell:regionScreenshot"),
    { locked = true, description = "Utilities: Screenshot region" })
hl.bind("CTRL + Print", function() hl.exec_cmd(fullScreenshot) end,
    { locked = true, description = "Utilities: Screenshot screen" })
hl.bind("SHIFT + Print", hl.dsp.global("quickshell:regionScreenshot"),
    { locked = true, description = "Utilities: Screenshot region" })
--# AI
hl.bind("SUPER + SHIFT + ALT + mouse:273", function() hl.exec_cmd(hyprScripts .. "/ai/primary-buffer-query.sh") end,
    { description = "Utilities: Generate AI summary for selected text" })
-- (requires a running ollama model)

--##! Screen
--# Zoom
local function zoomfunction(value)
    local zoomvalue = hl.get_config("cursor:zoom_factor")
    if (zoomvalue + value) > 3.0 then
        hl.config({ cursor = { zoom_factor = 3.0 } })
    elseif (zoomvalue + value) < 1.0 then
        hl.config({ cursor = { zoom_factor = 1.0 } })
    else
        hl.config({ cursor = { zoom_factor = zoomvalue + value } })
    end
end
hl.bind("SUPER + Minus", function() zoomfunction(-0.3) end, { repeating = true, description = "Screen: Zoom out" })
hl.bind("SUPER + Equal", function() zoomfunction(0.3) end, { repeating = true, description = "Screen: Zoom in" })

--# Zoom with keypad
hl.bind("SUPER + code:82", function() zoomfunction(-0.3) end, { repeating = true })
hl.bind("SUPER + code:86", function() zoomfunction(0.3) end, { repeating = true })

--##! Media
local mediaNextCommand =
"playerctl next || playerctl position `bc <<< \"100 * $(playerctl metadata mpris:length) / 1000000 / 100\"`"
hl.bind("SUPER + SHIFT + N", function() hl.exec_cmd(mediaNextCommand) end, { locked = true, description = "Media: Next track" })
hl.bind("XF86AudioNext", function() hl.exec_cmd(mediaNextCommand) end, { locked = true })
hl.bind("XF86AudioPrev", function() hl.exec_cmd("playerctl previous") end, { locked = true })
hl.bind("SUPER + SHIFT + ALT + mouse:275", function() hl.exec_cmd("playerctl previous") end)
hl.bind("SUPER + SHIFT + ALT + mouse:276", function() hl.exec_cmd(mediaNextCommand) end)
hl.bind("SUPER + SHIFT + B", function() hl.exec_cmd("playerctl previous") end,
    { locked = true, description = "Media: Previous track" })
hl.bind("SUPER + SHIFT + P", function() hl.exec_cmd("playerctl play-pause") end,
    { locked = true, description = "Media: Play/pause media" })
hl.bind("XF86AudioPlay", function() hl.exec_cmd("playerctl play-pause") end, { locked = true })
hl.bind("XF86AudioPause", function() hl.exec_cmd("playerctl play-pause") end, { locked = true })
hl.bind("XF86AudioMute", function() hl.exec_cmd("wpctl set-mute @DEFAULT_SINK@ toggle") end, { locked = true })
hl.bind("SUPER + SHIFT + M", function() hl.exec_cmd("wpctl set-mute @DEFAULT_SINK@ toggle") end,
    { locked = true, description = "Media: Toggle mute" })
hl.bind("ALT + XF86AudioMute", function() hl.exec_cmd("wpctl set-mute @DEFAULT_SOURCE@ toggle") end, { locked = true })
hl.bind("XF86AudioMicMute", function() hl.exec_cmd("wpctl set-mute @DEFAULT_SOURCE@ toggle") end, { locked = true })
hl.bind("SUPER + ALT + M", function() hl.exec_cmd("wpctl set-mute @DEFAULT_SOURCE@ toggle") end,
    { locked = true, description = "Media: Toggle mic" })

--#!
--##! Window
--# Focusing
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "Window: Move" })
hl.bind("SUPER + mouse:274", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Window: Resize" })
--#/# bind = SUPER + ←/↑/→/↓,, -- Focus in direction
for i = 1, 4 do
    local arrowkey = { "Left", "Right", "Up", "Down" }
    local focusdir = { "l", "r", "u", "d" }
    hl.bind("SUPER + " .. arrowkey[i], hl.dsp.focus({ direction = focusdir[i] }),
        { description = "Window: Focus " .. arrowkey[i] })
end
for i = 1, 2 do
    local arrowkey = { "BracketLeft", "BracketRight" }
    local focusdir = { "l", "r" }
    hl.bind("SUPER + " .. arrowkey[i], hl.dsp.focus({ direction = focusdir[i] }))
end
--#/# bind = SUPER + SHIFT, ←/↑/→/↓,, -- Move in direction
for i = 1, 4 do
    local arrowkey = { "Left", "Right", "Up", "Down" }
    local focusdir = { "l", "r", "u", "d" }
    hl.bind("SUPER + SHIFT + " .. arrowkey[i], hl.dsp.window.move({ direction = focusdir[i] }),
        { description = "Window: Move " .. arrowkey[i] })
end

hl.bind("ALT + F4",
    function()
        hl.exec_cmd(
            "notify-send \"Wrong close keybind\" \"Super+Q to close. Use Alt+F4 for Windows VMs\" -a Hyprland")
    end,
    { non_consuming = true })
hl.bind("SUPER + Q", hl.dsp.window.close(), { description = "Window: Close" })
hl.bind("SUPER + SHIFT + ALT + Q", function() hl.exec_cmd("hyprctl kill") end, { description = "Window: Forcefully zap a window" })

--# Window split ratio
--#/# binde = SUPER, ;/',, -- Adjust split ratio
hl.bind("SUPER + Semicolon", hl.dsp.layout("splitratio -0.1"), { repeating = true })
hl.bind("SUPER + Apostrophe", hl.dsp.layout("splitratio +0.1"), { repeating = true })
--# Positioning mode
hl.bind("SUPER + ALT + Space", hl.dsp.window.float({ action = "toggle" }), { description = "Window: Float/Tile" })
hl.bind("SUPER + D", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }),
    { description = "Window: Maximize" })
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }),
    { description = "Window: Fullscreen" })
hl.bind("SUPER + ALT + F", hl.dsp.window.fullscreen_state({ internal = 0, client = 3, action = "toggle" }),
    { description = "Window: Fullscreen spoof" })
hl.bind("SUPER + P", hl.dsp.window.pin(), { description = "Window: Pin" })

--#/# bind = SUPER+ALT, Hash,, -- Send to workspace -- (1, 2, 3,...)
for i = 1, 10 do
    hl.bind("SUPER + ALT + " .. (i % 10), function()
        hl.dispatch(hl.dsp.window.move({ workspace = workspace_in_group(i), follow = false }))
    end, { description = "Window: Send to workspace " .. i })
end
--# We also use raw keycodes because some keyboard layouts register number keys as different chars. The codes can be verified with `wev`
-- for i = 1, 10 do
--     local numberkey = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
--     hl.bind("SUPER + ALT + code:" .. numberkey[i], function()
--         hl.dispatch(hl.dsp.window.move({ workspace = workspace_in_group(i), follow = false }))
--     end)
-- end
--# keypad numbers
for i = 1, 10 do
    local numpadkey = { 87, 88, 89, 83, 84, 85, 79, 80, 81, 90 }
    hl.bind("SUPER + ALT + code:" .. numpadkey[i], function()
        hl.dispatch(hl.dsp.window.move({ workspace = workspace_in_group(i), follow = false }))
    end)
end

--# #/# bind = SUPER+SHIFT, Scroll ↑/↓,, -- Send to workspace left/right
for i = 1, 4 do
    local key = { "SUPER + SHIFT + mouse_", "SUPER + ALT + mouse_" }
    local keycombos = { key[1] .. "down", key[1] .. "up", key[2] .. "down", key[2] .. "up" }
    local prefix = { "r-", "r+", "r-", "r+" }
    hl.bind(keycombos[i], hl.dsp.window.move({ workspace = prefix[i] .. "1" }))
end

--#/# bind = SUPER+SHIFT, Page_↑/↓,, -- Send to workspace left/right
for i = 1, 2 do
    local keydirs = { "Up", "Down" }
    local prefix = { "r-", "r+" }
    local descdir = { "left", "right" }
    hl.bind("SUPER + SHIFT + Page_" .. keydirs[i], hl.dsp.window.move({ workspace = prefix[i] .. "1" }), {description = "Window: Send to workspace " .. descdir[i]})
end
for i = 1, 4 do
    local key = { "SUPER + ALT + Page_", "CTRL + SUPER + SHIFT + " }
    local keycombos = { key[1] .. "down", key[1] .. "up", key[2] .. "Right", key[2] .. "Left" }
    local prefix = { "r+", "r-", "r+", "r-" }
    hl.bind(keycombos[i], hl.dsp.window.move({ workspace = prefix[i] .. "1" })) -- # [hidden]
end

hl.bind("SUPER + ALT + S",
    hl.dsp.window.move({ workspace = "special:special", follow = false }), { description = "Window: Send to scratchpad" })
hl.bind("CTRL + SUPER + S", hl.dsp.workspace.toggle_special("special"))

--##! Workspace
--# Switching
--#/# bind = SUPER, Hash,, -- Focus workspace -- (1, 2, 3,...)
for i = 1, 10 do
    hl.bind("SUPER + " .. (i % 10), function()
        hl.dispatch(hl.dsp.focus({ workspace = workspace_in_group(i) }))
    end, { description = "Workspace: Focus " .. i })
end
--# We also use raw keycodes because some keyboard layouts register number keys as different chars. The codes can be verified with `wev`
for i = 1, 10 do
    local numberkey = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
    hl.bind("SUPER + code:" .. numberkey[i], function()
        hl.dispatch(hl.dsp.focus({ workspace = workspace_in_group(i) }))
    end)
end
--# keypad numbers
for i = 1, 10 do
    local numpadkey = { 87, 88, 89, 83, 84, 85, 79, 80, 81, 90 }
    hl.bind("SUPER + code:" .. numpadkey[i], function()
        hl.dispatch(hl.dsp.focus({ workspace = workspace_in_group(i) }))
    end)
end

--#/# bind = CTRL+SUPER, ←/→,, -- Focus left/right
--#/# bind = CTRL+SUPER+ALT, ←/→,, -- # [hidden] Focus busy left/right
for i = 1, 2 do
    local keys = { "Left", "Right" }
    local prefix = { "r-", "r+" }
    local descdir = { "left", "right" }
    hl.bind("CTRL + SUPER + " .. keys[i], hl.dsp.focus({ workspace = prefix[i] .. "1" }), {description = "Workspace: Focus " .. descdir[i]})
end
for i = 1, 2 do
    local keys = { "Left", "Right" }
    local prefix = { "m-", "m+" }
    hl.bind("CTRL + SUPER + ALT + " .. keys[i], hl.dsp.focus({ workspace = prefix[i] .. "1" }))
end
--#/# bind = SUPER, Page_↑/↓,, -- Focus left/right
for i = 1, 4 do
    local key = { "SUPER + Page_Down", "SUPER + Page_Up" }
    local keycombos = { key[1], key[2], "CTRL + " .. key[1], "CTRL + " .. key[2] }
    local prefix = { "r+", "r-", "r+", "r-" }
    hl.bind(keycombos[i], hl.dsp.focus({ workspace = prefix[i] .. "1" }))
end
--#/# bind = SUPER, Scroll ↑/↓,, -- Focus left/right
for i = 1, 4 do
    local key = { "SUPER + mouse_up", "SUPER + mouse_down" }
    local keycombos = { key[1], key[2], "CTRL + " .. key[1], "CTRL + " .. key[2] }
    local prefix = { "-", "+", "r-", "r+" }
    hl.bind(keycombos[i], hl.dsp.focus({ workspace = prefix[i] .. "1" }))
end
--## Special
hl.bind("SUPER + S", hl.dsp.workspace.toggle_special("special"), { description = "Workspace: Toggle scratchpad" })
hl.bind("SUPER + mouse:275", hl.dsp.workspace.toggle_special("special"))
for i = 1, 4 do
    local key = { "BracketLeft", "BracketRight", "Up", "Down" }
    local prefix = { "-1", "+1", "r-5", "r+5" }
    hl.bind("CTRL + SUPER + " .. key[i], hl.dsp.focus({ workspace = prefix[i] }))
end

--##! Virtual machines
hl.define_submap("virtual-machine", function()
    hl.bind("SUPER + ALT + F1", function()
        local currentsubmap = hl.get_current_submap()
        if currentsubmap == "virtual-machine" then
            hl.dispatch(function() hl.exec_cmd(
                "notify-send 'Exited Virtual Machine submap' 'Keybinds re-enabled' -a 'Hyprland'") end)
            hl.dispatch(hl.dsp.submap("reset"))
        elseif currentsubmap == "" then
            hl.dispatch(function() hl.exec_cmd(
                "notify-send 'Entered Virtual Machine submap' 'Keybinds disabled. hit SUPER+ALT+F1 to escape' -a 'Hyprland'") end)
            hl.dispatch(hl.dsp.submap("virtual-machine"))
        end
    end, { submap_universal = true })
end)


--#!
--# Testing
hl.bind("SUPER + ALT + F11",
    function() hl.exec_cmd(
        "bash -c 'RANDOM_IMAGE=$(find ~/Pictures -type f | shuf -n 1); ACTION=$(notify-send \"Test notification with body image\" \"This notification should contain your user account <b>image</b> and <a href=\\\"https://discord.com/app\\\">Discord</a> <b>icon</b>. Oh and here is a random image in your Pictures folder: <img src=\\\"$RANDOM_IMAGE\\\" alt=\\\"Testing image\\\"/>\" -a \"Hyprland\" -p -h \"string:image-path:/var/lib/AccountsService/icons/$USER\" -t 6000 -i \"discord\" -A \"openImage=Profile image\" -A \"action2=Open the random image\" -A \"action3=Useless button\"); [[ $ACTION == *openImage ]] && xdg-open \"/var/lib/AccountsService/icons/$USER\"; [[ $ACTION == *action2 ]] && xdg-open \"$RANDOM_IMAGE\"'") end
) -- # [hidden]
hl.bind("SUPER + ALT + F12",
    function() hl.exec_cmd(
        "bash -c 'RANDOM_IMAGE=$(find ~/Pictures -type f | shuf -n 1); ACTION=$(notify-send \"Test notification\" \"This notification should contain a random image in your <b>Pictures</b> folder and <a href=\\\"https://discord.com/app\\\">Discord</a> <b>icon</b>.\n<i>Flick right to dismiss!</i>\" -a \"Discord (fake)\" -p -h \"string:image-path:$RANDOM_IMAGE\" -t 6000 -i \"discord\" -A \"openImage=Profile image\" -A \"action2=Useless button\"); [[ $ACTION == *openImage ]] && xdg-open \"/var/lib/AccountsService/icons/$USER\"'") end
)                                                                                                        -- # [hidden]
hl.bind("SUPER + ALT + Equal",
    function() hl.exec_cmd("notify-send 'Urgent notification' 'Ah hell no' -u critical -a 'Hyprland keybind'") end) -- # [hidden]

--##! Session
hl.bind("SUPER + L", function() hl.exec_cmd("loginctl lock-session") end, { description = "Session: Lock" })
hl.bind("SUPER + SHIFT + L", function() hl.exec_cmd("systemctl suspend || loginctl suspend") end,
    { locked = true, description = "Session: Sleep" }) -- Sleep
-- hl.bind("switch:on:Lid Switch", function() hl.exec_cmd("systemctl suspend || loginctl suspend") end, {locked = true} ) -- # [hidden] Suspend when laptop lid is closed, uncomment if for whatever reason it's not the default behavior

hl.bind("CTRL + SHIFT + ALT + SUPER + Delete", function() hl.exec_cmd("systemctl poweroff || loginctl poweroff") end,
    { description = "Session: Shut down" }) -- # [hidden] Power off


--##! Apps
hl.bind("SUPER + Return", function() hl.exec_cmd(terminal) end, { description = "App: Terminal" })
hl.bind("SUPER + T", function() hl.exec_cmd(qsScripts .. "/hyprland/term-summon.sh") end, { description = "App: 终端召唤（special:quake 浮动居中，再按隐藏）" })
hl.bind("CTRL + ALT + T", hl.dsp.global("quickshell:wallpaperSelectorToggle"),
    { description = "Shell: Wallpaper selector" })
hl.bind("SUPER + E", function() hl.exec_cmd(fileManager) end, { description = "App: File manager" })
hl.bind("SUPER + W", function() hl.exec_cmd(browser) end, { description = "App: Browser" })
hl.bind("SUPER + C", function() hl.exec_cmd(codeEditor) end, { description = "App: Code editor" })
hl.bind("CTRL + SUPER + SHIFT + ALT + W", function() hl.exec_cmd(officeSoftware) end, { description = "App: Office software" })
hl.bind("SUPER + X", function() hl.exec_cmd(textEditor) end, { description = "App: Text editor" })
hl.bind("CTRL + SUPER + V", function() hl.exec_cmd(volumeMixer) end, { description = "App: Volume mixer" })
hl.bind("SUPER + I", hl.dsp.global("quickshell:settingsToggle"), { description = "Shell: Toggle settings" })
hl.bind("CTRL + SHIFT + Escape", function() hl.exec_cmd(taskManager) end, { description = "App: Task manager" })

--# Cursed stuff
--## Make window not amogus large
hl.bind("CTRL + SUPER + Backslash", hl.dsp.window.resize({ x = 640, y = 480, "exact" }))

