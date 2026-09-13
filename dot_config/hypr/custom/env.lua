-- This file will not be overwritten across dots-hyprland updates.
-- The file name is for the sake of organization and does not matter
-- See the corresponding files in ~/.config/hypr/hyprland for examples

-- 光标主题由 hyprland/execs.lua 统一管理：
-- 它读取 ~/.cache/cursor_theme（由 generate_cursor_theme.py 按 matugen 主色重写），
-- 再做 hyprctl setcursor。此处不要再硬编码 XCURSOR_THEME / HYPRCURSOR_THEME，
-- 否则会和 execs.lua 的设置打架（execs.lua 后加载，会静默覆盖这里的值）。
