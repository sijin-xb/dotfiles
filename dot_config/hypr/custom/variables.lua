-- This file will not be overwritten across dots-hyprland updates.
-- The file name is for the sake of organization and does not matter
-- See the corresponding files in ~/.config/hypr/hyprland for examples

-- ===================== 用哪套 Quickshell 配置 =====================
-- 默认 caelestia；当 caelestia **跑不起来**时自动回退 end4-pC。
-- 「跑不起来」有两种，都要覆盖：
--   1. 配置目录 / shell.qml 不存在（被删掉、克隆没成功、手滑移走）
--   2. shell.qml 在、但 C++ QML 插件没编译（clone 成功 ≠ 能加载）
-- 只判第 1 种的话第 2 种会直接黑屏 —— 这是 2026-09-28 那次修复的原因。
-- 另外 start_quickshell.sh 还会在运行时再兜一层（IPC 健康检查 + 回退），
-- 静态判据只是让 qsConfig 一开始就指向一个能用的 shell。
--
-- ===================== 想自己指定用哪套？改下面这一行 =====================
--   ""          = 自动（caelestia 能跑就用 caelestia，否则 end4-pC）—— 默认
--   "end4-pC"   = 固定用 end4-pC
--   "caelestia" = 固定用 caelestia
--
-- 改的就是本文件的 QS_SHELL_PREFERENCE 这一行，改完重启 Hyprland 会话生效
-- （或执行 `bash ~/.config/hypr/hyprland/scripts/start_quickshell.sh` 立即换）。
--
-- ⚠ 强制 "caelestia" 但插件没编译时，仍然会退到 end4-pC：宁可换个 shell，
--   也不要黑屏。原因会写进 ~/.local/state/dotfiles/quickshell-startup.log。
QS_SHELL_PREFERENCE = ""
local preference = QS_SHELL_PREFERENCE

-- 为什么写在 custom/ 而不是 hyprland/variables.lua：
--   本文件由 hyprland/keybinds.lua 在 require("hyprland.variables") 之后加载，
--   hl.env 是覆盖式写入，所以这里的值会盖掉模板里的 qsConfig = "end4-pC"。
--   写在 custom/env.lua 里是不行的 —— env.lua 在 hyprland.lua 里比 keybinds
--   更早加载，会被后面的 hyprland/variables.lua 反盖回去。
local home = os.getenv("HOME")
local caelestiaEntry = home .. "/.config/quickshell/caelestia/shell.qml"
local caelestiaModuleDir = home .. "/src/caelestia-build/qml/Caelestia"
local caelestiaModuleFile = caelestiaModuleDir .. "/qmldir"

-- 「shell.qml 存在」不等于「caelestia 能跑」。
--
-- caelestia 的界面几乎全部由**编译出来的 C++ QML 模块**提供
-- （Caelestia.Config / Caelestia.Components …，光仓库里就有 200+ 个文件 import
-- Caelestia.*）。clone 成功但插件没编译时，shell.qml 明明在、qs 却会报
--
--     module "Caelestia.Config" is not installed
--
-- 然后立刻退出。而 qsConfig 一旦被判成 caelestia，完整的 end4-pC 就不会启动，
-- 于是登录后**黑屏、只剩光标**（2026-09-28 在本机实测复现）。
--
-- 所以判据要跟着「shell.qml + 插件产物」一起看。插件产物的位置与 install.sh
-- 第 [4/7] 步的判据对齐（那边也是查 $build/qml/Caelestia/*.so）。
--
-- 顺带一个必须知道的细节：lib/init.lua 的 is_file_exists 用的是 io.open，
-- 而 Linux 上 fopen 对**目录**也会成功，所以它实际是「路径存在」判据
-- （已用 lua 实测确认）。这里正好需要这个语义，因此下面可以直接测目录。
local caelestiaRunnable = is_file_exists(caelestiaEntry)
    and (is_file_exists(caelestiaModuleFile) or is_file_exists(caelestiaModuleDir))

-- 生效值：显式指定优先，但它只是「偏好」——不可运行的 caelestia 不会被选中
local useCaelestia
if preference == "end4-pC" then
    useCaelestia = false
elseif preference == "caelestia" then
    useCaelestia = caelestiaRunnable
else -- "" 或写了别的值：按自动判据
    useCaelestia = caelestiaRunnable
end

-- 故意不写 local：custom/keybinds.lua 要用它决定绑哪套快捷键
shellIsCaelestia = useCaelestia

hl.env("qsConfig", shellIsCaelestia and "caelestia" or "end4-pC")
