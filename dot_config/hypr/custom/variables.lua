-- This file will not be overwritten across dots-hyprland updates.
-- The file name is for the sake of organization and does not matter
-- See the corresponding files in ~/.config/hypr/hyprland for examples

-- ===================== 用哪套 Quickshell 配置 =====================
-- 默认 caelestia；只有当 caelestia 的配置目录不存在时，才自动回退 end4-pC。
-- 这样即使 caelestia 被删掉 / 克隆没成功 / 手滑移走，登录后依然有一个能用的
-- 桌面 shell，而不是黑屏。
--
-- 为什么写在 custom/ 而不是 hyprland/variables.lua：
--   本文件由 hyprland/keybinds.lua 在 require("hyprland.variables") 之后加载，
--   hl.env 是覆盖式写入，所以这里的值会盖掉模板里的 qsConfig = "end4-pC"。
--   写在 custom/env.lua 里是不行的 —— env.lua 在 hyprland.lua 里比 keybinds
--   更早加载，会被后面的 hyprland/variables.lua 反盖回去。
local home = os.getenv("HOME")
local caelestiaEntry = home .. "/.config/quickshell/caelestia/shell.qml"

-- 故意不写 local：custom/keybinds.lua 要用它决定绑哪套快捷键
shellIsCaelestia = is_file_exists(caelestiaEntry)

hl.env("qsConfig", shellIsCaelestia and "caelestia" or "end4-pC")
