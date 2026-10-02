-- This file will not be overwritten across dots-hyprland updates.
-- The file name is for the sake of organization and does not matter
-- See the corresponding files in ~/.config/hypr/hyprland for examples

-- FireflySpring Missives 像素光标主题（XCursor 格式，安装于 ~/.local/share/icons）
-- 标称尺寸 24：像素画保持锐利，且 person/pin 的相对大小正确
hl.env("XCURSOR_THEME", "FireflySpring-Missives-Pixel-Cursors")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "FireflySpring-Missives-Pixel-Cursors")
hl.env("HYPRCURSOR_SIZE", "24")

-- Qt 应用不画客户端装饰（标题栏）。与 niri 的 config.kdl 保持一致 ——
-- Konsole 这类 Qt 终端在 Wayland 下会自己画一层 CSD 标题栏，tiling WM
-- 下没有哪个 Qt 程序需要它。
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
