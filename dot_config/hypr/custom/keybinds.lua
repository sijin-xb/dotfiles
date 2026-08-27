hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )

local function shell(command)
    return hl.dsp.exec_cmd("sh -lc '" .. command:gsub("'", "'\\''") .. "'")
end

-- Niri-compatible personal shortcuts that do not replace end-4 defaults.
hl.bind("SUPER + F1", shell("pkill fcitx5 || fcitx5 -d"), { description = "Toggle input method" })
hl.bind("SUPER + F10", shell("waypaper --random"), { description = "Random wallpaper" })
hl.bind("SUPER + SHIFT + F10", shell("$HOME/.config/scripts/random-anime-wallpaper.sh"), { description = "Download random wallpaper" })
hl.bind("SUPER + F12", hl.dsp.global("quickshell:regionScreenshot"), { description = "Screenshot region" })
hl.bind("SUPER + Slash", shell("kitty --single-instance --class quickterminal"), { description = "Quick terminal" })
hl.bind("SUPER + ALT + L", shell("hyprlock"), { description = "Lock screen" })
hl.bind("SUPER + ALT + T", shell("$HOME/.config/scripts/matugen-select-type.sh"), { description = "Change color strategy" })
hl.bind("SUPER + U", hl.dsp.focus({ workspace = "r-" .. "1" }), { description = "Previous workspace" })
hl.bind("SUPER + I", hl.dsp.focus({ workspace = "r+" .. "1" }), { description = "Next workspace" })
hl.bind("SUPER + CTRL + U", hl.dsp.window.move({ workspace = "r-1" }), { description = "Move window to previous workspace" })
hl.bind("SUPER + CTRL + I", hl.dsp.window.move({ workspace = "r+1" }), { description = "Move window to next workspace" })
