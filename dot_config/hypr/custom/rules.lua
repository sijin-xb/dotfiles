-- PVZ ImGui 悬浮窗：悬浮
-- class 来自 WM_CLASS，XWayland 下是 exe / 窗口名，这里是 "pvz-imgui-overlay"
hl.window_rule({match = {class = "^(pvz-imgui-overlay)$"},   float = true})

-- ============================================================
-- 终端召唤（SUPER + T）：kitty 常驻 special:quake 工作区，
-- 浮动、居中、半透明。切换逻辑在 quickshell 的
-- scripts/hyprland/term-summon.sh（launch-if-missing + toggle）。
-- ============================================================
hl.workspace_rule({ workspace = "special:quake", gaps_out = 30 })
hl.window_rule({match = {class = "^(kitty-quake)$"}, float = true})
hl.window_rule({match = {class = "^(kitty-quake)$"}, workspace = "special:quake silent"})
hl.window_rule({match = {class = "^(kitty-quake)$"}, size = {"(monitor_w*0.72)", "(monitor_h*0.62)"}})
hl.window_rule({match = {class = "^(kitty-quake)$"}, center = true})
hl.window_rule({match = {class = "^(kitty-quake)$"}, opacity = 0.93})
hl.window_rule({match = {class = "^(kitty-quake)$"}, rounding = 14})

-- ============================================================
-- 液态玻璃效果 - 性能豁免 & 差异化透明度
-- ------------------------------------------------------------
-- 注：主参数（圆角/模糊半径/透明度/边框/间距）请直接在
-- quickshell 设置 → "配置文件" → "Hyprland" 面板里调整，
-- 那里面的滑条会写入 shellOverrides 并最终生效。
-- 这里只放 window_rule 层面的差异化规则。
-- ============================================================

-- -------- 模糊：全局开启，无任何窗口级豁免 --------
-- 所有窗口一律参与模糊；要单独关某个窗口，再自己加 no_blur = true。
-- 注：Hyprland 的 fullscreen 匹配符 1=最大化、2=真全屏，这里都不再豁免。
hl.window_rule({match = {class = ".*"}, no_blur = false })

-- -------- 终端类：稍高透明度，代码阅读更舒适 --------
hl.window_rule({match = {class = "^(kitty|foot|Alacritty|wezterm)$"}, opacity = 0.90 })

-- -------- 浏览器：保持较高可读性，减少偏色 --------
hl.window_rule({match = {class = "^(firefox|zen-browser|chromium|brave-browser|google-chrome|microsoft-edge)$"}, opacity = 0.92 })
