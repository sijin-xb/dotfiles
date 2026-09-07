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

-- ============================================================
-- 液态玻璃效果 - 性能豁免 & 差异化透明度
-- ------------------------------------------------------------
-- 注：主参数（圆角/模糊半径/透明度/边框/间距）请直接在
-- quickshell 设置 → "配置文件" → "Hyprland" 面板里调整，
-- 那里面的滑条会写入 shellOverrides 并最终生效。
-- 这里只放 window_rule 层面的差异化规则。
-- ============================================================

-- -------- 模糊/透明豁免：游戏、视频、绘图工具 --------
-- 这些应用如果开模糊会严重影响画质/性能，强制关模糊
-- （透明度使用全局默认的 fullscreen_opacity=1，全屏时自动变不透明）
hl.window_rule({match = {class = "^(mpv)$"},                          no_blur = true })
hl.window_rule({match = {class = "^(vlc)$"},                          no_blur = true })
hl.window_rule({match = {class = "^(CelluloID)$"},                    no_blur = true })
hl.window_rule({match = {class = ".*steam_app.*"},                    no_blur = true })
hl.window_rule({match = {class = "^(lutris)$"},                       no_blur = true })
hl.window_rule({match = {class = "^(heroic)$"},                       no_blur = true })
hl.window_rule({match = {title = ".*\\.exe.*"},                       no_blur = true })
hl.window_rule({match = {fullscreen = 1},                             no_blur = true })
hl.window_rule({match = {class = "^(hyprpicker)$"},                   no_blur = true })
hl.window_rule({match = {class = "^(gimp)$"},                         no_blur = true })
hl.window_rule({match = {class = "^(krita)$"},                        no_blur = true })
hl.window_rule({match = {class = "^(Inkscape)$"},                     no_blur = true })

-- -------- 终端类：稍高透明度，代码阅读更舒适 --------
hl.window_rule({match = {class = "^(kitty|foot|Alacritty|wezterm)$"}, opacity = 0.90 })

-- -------- 浏览器：保持较高可读性，减少偏色 --------
hl.window_rule({match = {class = "^(firefox|zen-browser|chromium|brave-browser|google-chrome|microsoft-edge)$"}, opacity = 0.92 })
