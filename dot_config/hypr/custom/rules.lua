-- PVZ ImGui 悬浮窗：悬浮 + 关模糊（磨砂背景就是 blur 给半透明窗口加的）
-- class 来自 WM_CLASS，XWayland 下是 exe / 窗口名，这里是 "pvz-imgui-overlay"
hl.window_rule({match = {class = "^(pvz-imgui-overlay)$"},   float = true, no_blur = true})

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
