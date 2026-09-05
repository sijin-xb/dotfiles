-- put former exec-once commands inside the func and former exec commands outside
hl.on("hyprland.start", function ()

    -- Input method
    hl.exec_cmd("fcitx5 -d")
    hl.exec_cmd("while ! fcitx5-remote --check >/dev/null 2>&1; do sleep 0.1; done; fcitx5-remote -o; fcitx5-remote -s rime; dbus-update-activation-environment --systemd XMODIFIERS GTK_IM_MODULE QT_IM_MODULE QT_IM_MODULES LANG LANGUAGE")

    -- Bar, wallpaper
    hl.exec_cmd("$HOME/.config/hypr/hyprland/scripts/start_geoclue_agent.sh")
    -- Keep Qt's Wayland text-input fallback available; forcing only the
    -- Fcitx backend can swallow ordinary key events in QtQuick.
    hl.exec_cmd("while ! fcitx5-remote --check >/dev/null 2>&1; do sleep 0.1; done; env QT_IM_MODULE=fcitx 'QT_IM_MODULES=wayland;fcitx' GTK_IM_MODULE=fcitx XMODIFIERS=@im=fcitx QT_QPA_PLATFORM='wayland;xcb' QT_WAYLAND_TEXT_INPUT_PROTOCOL=zwp_text_input_v3 qs -c $qsConfig")
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/__restore_video_wallpaper.sh")
    -- Refresh pinyin search aliases for CJK-named apps (used by AppSearch)
    hl.exec_cmd("$HOME/.local/state/quickshell/.venv/bin/python $HOME/.config/hypr/hyprland/scripts/generate_app_pinyin.py")

    -- Core components (authentication, lock screen, notification daemon)
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("systemctl --user restart xdg-desktop-portal-hyprland")
    hl.exec_cmd("dbus-update-activation-environment --all")
    hl.exec_cmd("sleep 1 && dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP") -- Some fix idk

    -- Audio
    hl.exec_cmd("easyeffects --hide-window --service-mode")

    -- Clipboard: history
    --hl.exec_cmd("wl-paste --watch cliphist store")
    hl.exec_cmd("wl-paste --type text --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update'")
    hl.exec_cmd("wl-paste --type image --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update'")

    -- Cursor: theme follows the matugen palette (nearest catppuccin mocha accent),
    -- persisted by apply_cursor_theme.py to ~/.cache/cursor_theme
    local cursorThemeFile = io.open(home_dir .. "/.cache/cursor_theme", "r")
    local cursorTheme = "catppuccin-mocha-flamingo-cursors"
    if cursorThemeFile then
        local content = cursorThemeFile:read("*l")
        cursorThemeFile:close()
        if content and string.len(content) > 0 then
            cursorTheme = content
        end
    end
    hl.env("XCURSOR_THEME", cursorTheme)
    hl.env("XCURSOR_SIZE", "24")
    hl.exec_cmd("hyprctl setcursor " .. cursorTheme .. " 24")
end)
