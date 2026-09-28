-- This file will not be overwritten across dots-hyprland updates.
-- The file name is for the sake of organization and does not matter
-- See the corresponding files in ~/.config/hypr/hyprland for examples

-- 只用 end4-pC 这一套 Quickshell 配置。
-- （caelestia 实验已取消；本文件不再包含任何 caelestia 选择逻辑。）
-- 想换默认 shell，改 hyprland/variables.lua 模板里的 qsConfig 即可。

-- 故意不写 local：custom/keybinds.lua 要用它决定绑哪套快捷键
shellIsCaelestia = false

hl.env("qsConfig", "end4-pC")
