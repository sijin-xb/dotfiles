-- put former exec-once commands inside the func and former exec commands outside
local home_dir = os.getenv("HOME")

hl.on("hyprland.start", function ()

    -- Input method：异步 + **有界**。超时与日志都在脚本里，失败不阻塞桌面。
    -- ⚠ 这里以前是内联的无界等待（`while ! fcitx5-remote --check; do sleep 0.1; done`）：
    --   fcitx5 没起来 / DBus 不可用 / fcitx5-remote 缺失时它永远不退出。单独一行时
    --   只是输入法不可用，但历史上同一个循环还串在 Quickshell 启动之前，于是
    --   登录后黑屏只剩光标。任何"等一个东西就绪"的写法都必须有上限。
    hl.exec_cmd("$HOME/.config/hypr/hyprland/scripts/fcitx_init.sh")

    -- Bar, wallpaper
    hl.exec_cmd("$HOME/.config/hypr/hyprland/scripts/start_geoclue_agent.sh")
    -- Quickshell：**独立脚本**启动，不与输入法、也不与其它任何"等就绪"耦合。
    -- 脚本负责：QML2_IMPORT_PATH（caelestia 的 C++ 插件）、入口/模块可用性检查、
    -- 启动后的 IPC 健康检查、失败回退 end4-pC、以及全过程日志
    -- （~/.local/state/dotfiles/quickshell-startup.log）。
    -- 这样即使 $qsConfig 指向一个加载不起来的 shell（例如 caelestia 克隆成功但
    -- C++ 插件没编译），也只会退到 end4-pC，不会黑屏。
    hl.exec_cmd("$HOME/.config/hypr/hyprland/scripts/start_quickshell.sh")
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/__restore_video_wallpaper.sh")
    -- Refresh pinyin search aliases for CJK-named apps (used by AppSearch)
    hl.exec_cmd("$HOME/.local/state/quickshell/.venv/bin/python $HOME/.config/hypr/hyprland/scripts/generate_app_pinyin.py")

    -- Core components (authentication, lock screen, notification daemon)
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("systemctl --user restart xdg-desktop-portal-hyprland")
    hl.exec_cmd("dbus-update-activation-environment --all")
    hl.exec_cmd("sleep 1 && dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP") -- Some fix idk
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")

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
