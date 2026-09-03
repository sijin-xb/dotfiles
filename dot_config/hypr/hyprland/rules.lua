-- ============================================================
-- Hyprland 窗口/图层规则配置文件 (rules.lua)
-- ------------------------------------------------------------
-- 使用方式：
--   本文件由 hyprland.lua 通过 require("hyprland.rules") 加载。
--   如果你想在不修改本文件的前提下自定义规则，请在
--   custom/rules.lua 里写新规则 —— custom.rules 会在本文件
--   之后被 require，后加载的规则会覆盖/追加前面同名 match 的效果。
--   改完规则后执行：hyprctl reload  即可生效，无需重启 Hyprland。
--
--   两个核心函数：
--     hl.window_rule({match = {...}, 属性 = 值})   -- 针对普通窗口
--     hl.layer_rule({match = {namespace = "..."}, 属性 = 值}) -- 针对 layer-shell 图层
--       (layer 指的是 bar、launcher、通知、Quickshell 面板这类
--        不是普通窗口、而是"层叠在桌面上"的 UI 组件)
-- ============================================================

-- ######## 窗口规则 (Window rules) ########

-- 对 xwayland 的空白右键菜单（class/title 都是空）禁用模糊
hl.window_rule({match = {class = "^()$", title = "^()$" },                   no_blur = true })

-- 全局模糊开关：false 表示不禁用，即"所有普通窗口都允许模糊"
-- 如果你想恢复"只有 shell 组件模糊、普通窗口不模糊"的效果，把这里改回 true
hl.window_rule({match = {class = ".*" }, no_blur = false })

-- ---- 悬浮 (Floating) 窗口规则 ----
-- 以下这些都是"文件选择器 / 弹窗"类窗口，强制居中 + 悬浮显示，
-- 避免它们被平铺进 tiling 布局里
hl.window_rule({match = {title = "^(Open File)(.*)$" },                      center = true})
hl.window_rule({match = {title = "^(Open File)(.*)$" },                      float = true})
hl.window_rule({match = {title = "^(Select a File)(.*)$" },                  center = true})
hl.window_rule({match = {title = "^(Select a File)(.*)$" },                  float = true})
hl.window_rule({match = {title = "^(Choose wallpaper)(.*)$" },               center = true})
hl.window_rule({match = {title = "^(Choose wallpaper)(.*)$" },               float = true})
hl.window_rule({match = {title = "^(Choose wallpaper)(.*)$" },               size = {"(monitor_w*0.60)", "(monitor_h*0.65)"} })
hl.window_rule({match = {title = "^(Open Folder)(.*)$" },                    center = true})
hl.window_rule({match = {title = "^(Open Folder)(.*)$" },                    float = true})
hl.window_rule({match = {title = "^(Save As)(.*)$" },                        center = true})
hl.window_rule({match = {title = "^(Save As)(.*)$" },                        float = true})
hl.window_rule({match = {title = "^(Library)(.*)$" },                        center = true})
hl.window_rule({match = {title = "^(Library)(.*)$" },                        float = true})
hl.window_rule({match = {title = "^(File Upload)(.*)$" },                    center = true})
hl.window_rule({match = {title = "^(File Upload)(.*)$" },                    float = true})
hl.window_rule({match = {title = "^(.*)(wants to save)$" },                  center = true})
hl.window_rule({match = {title = "^(.*)(wants to save)$" },                  float = true})
hl.window_rule({match = {title = "^(.*)(wants to open)$" },                  center = true})
hl.window_rule({match = {title = "^(.*)(wants to open)$" },                  float = true})

-- 一些具体应用的悬浮/尺寸设置
hl.window_rule({match = {class = "^(blueberry\\.py)$" },                     float = true}) -- 蓝牙管理器
hl.window_rule({match = {class = "^(guifetch)$" },                           float = true}) -- FlafyDev/guifetch
hl.window_rule({match = {class = "^(pavucontrol)$" },                        float = true}) -- 音量控制面板
hl.window_rule({match = {class = "^(pavucontrol)$" },                        size = {"(monitor_w*0.45)", "(monitor_h*0.45)"} })
hl.window_rule({match = {class = "^(pavucontrol)$" },                        center = true})
hl.window_rule({match = {class = "^(org.pulseaudio.pavucontrol)$" },         float = true})
hl.window_rule({match = {class = "^(org.pulseaudio.pavucontrol)$" },         size = {"(monitor_w*0.45)", "(monitor_h*0.45)"} })
hl.window_rule({match = {class = "^(org.pulseaudio.pavucontrol)$" },         center = true})
hl.window_rule({match = {class = "^(nm-connection-editor)$" },               float = true}) -- 网络管理器
hl.window_rule({match = {class = "^(nm-connection-editor)$" },               size = {"(monitor_w*0.45)", "(monitor_h*0.45)"} })
hl.window_rule({match = {class = "^(nm-connection-editor)$" },               center = true})
hl.window_rule({match = {class = ".*plasmawindowed.*" },                     float = true}) -- KDE 独立组件窗口
hl.window_rule({match = {class = "kcm_.*" },                                  float = true}) -- KDE 系统设置模块
hl.window_rule({match = {class = ".*bluedevilwizard" },                      float = true}) -- KDE 蓝牙配对向导
hl.window_rule({match = {title = ".*Welcome" },                              float = true})
hl.window_rule({match = {title = "^(illogical-impulse Settings)$" },         float = true})
hl.window_rule({match = {title = ".*Shell conflicts.*" },                    float = true})
hl.window_rule({match = {class = "org.freedesktop.impl.portal.desktop.kde" }, float = true}) -- 文件选择/权限弹窗
hl.window_rule({match = {class = "org.freedesktop.impl.portal.desktop.kde" }, size = {"(monitor_w*0.60)", "(monitor_h*0.65)"} })
hl.window_rule({match = {class = "^(Zotero)$" },                             float = true}) -- 文献管理软件
hl.window_rule({match = {class = "^(Zotero)$" },                             size = {"(monitor_w*0.45)", "(monitor_h*0.45)"} })

-- ---- 窗口位置 (Move) ----
-- kde-material-you-colors 切换深/浅色主题时会弹出一个中间窗口，
-- 这里把它挪到屏幕外(999999,999999)并禁止抢焦点，避免干扰
hl.window_rule({match = {class = "^(plasma-changeicons)$" }, float = true})
hl.window_rule({match = {class = "^(plasma-changeicons)$" }, no_initial_focus = true})
hl.window_rule({match = {class = "^(plasma-changeicons)$" }, move = {999999, 999999}})
-- Dolphin 复制文件时的进度条窗口，挪到左上角固定位置
hl.window_rule({match = {title = "^(Copying — Dolphin)$" }, move = {40, 80}})

-- ---- 平铺 (Tiling) ----
hl.window_rule({match = {class = "^dev\\.warp\\.Warp$" }, tile = true}) -- Warp 终端强制平铺

-- ---- 画中画 (Picture-in-Picture) ----
-- 匹配浏览器/播放器弹出的"画中画"小窗，固定悬浮在右下角、保持宽高比、
-- 并 pin 住（切换工作区时始终可见）
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, float = true})
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, keep_aspect_ratio = true})
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, move = {"(monitor_w*0.73)", "(monitor_h*0.72)"} })
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, size = {"(monitor_w*0.25)", "(monitor_h*0.25)"} })
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, float = true})
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, pin = true})

-- ---- 屏幕共享 (Screen sharing) ----
-- 屏幕共享提示条：悬浮、pin 住、居中贴底显示
hl.window_rule({match = {title = ".*is sharing (a window|your screen).*" }, float = true})
hl.window_rule({match = {title = ".*is sharing (a window|your screen).*" }, pin = true})
hl.window_rule({match = {title = ".*is sharing (a window|your screen).*" }, move = {"(monitor_w*.5-window_w*.5)", "(monitor_h-window_h-12)"} })

-- ---- 画面撕裂/立即渲染 (Tearing) ----
-- 对 .exe（游戏，通常经 Wine/Proton）、Minecraft、Steam 游戏
-- 开启 immediate 立即呈现，降低输入延迟（代价是可能出现画面撕裂）
hl.window_rule({match = {title = ".*\\.exe" }, immediate = true})
hl.window_rule({match = {title = ".*minecraft.*" }, immediate = true})
hl.window_rule({match = {class = "^(steam_app).*" }, immediate = true})

-- 平铺窗口不需要阴影（阴影只有悬浮窗才好看，平铺窗口会显得多余/影响性能）
hl.window_rule({match = {float = 0 }, no_shadow = true})

-- ######## 工作区规则 (Workspace rules) ########
-- special workspace（呼出式侧边工作区）的外边距设为 30
hl.workspace_rule({ workspace = "special:special", gaps_out = 30 })

-- ######## 图层规则 (Layer rules) ########
-- 注意：layer_rule 匹配的是 wlr-layer-shell 协议的图层组件
-- （状态栏、启动器、通知、锁屏、Quickshell 面板等），不是普通窗口

-- xray: 让这些图层"看穿"下层内容做模糊采样（通常配合 blur 使用）
hl.layer_rule({ match = { namespace = ".*" }, xray = true})

-- 以下这些图层禁用开合动画，追求"秒开秒关"的响应速度
hl.layer_rule({ match = { namespace = "walker" }, no_anim = true})       -- walker 启动器
hl.layer_rule({ match = { namespace = "selection" }, no_anim = true})    -- 区域选择（截图等）
hl.layer_rule({ match = { namespace = "overview" }, no_anim = true})     -- 工作区总览
hl.layer_rule({ match = { namespace = "anyrun" }, no_anim = true})       -- anyrun 启动器
hl.layer_rule({ match = { namespace = "indicator.*" }, no_anim = true})  -- 各类指示器
hl.layer_rule({ match = { namespace = "osk" }, no_anim = true})          -- 屏幕键盘
hl.layer_rule({ match = { namespace = "hyprpicker" }, no_anim = true})   -- 取色器
hl.layer_rule({ match = { namespace = "noanim" }, no_anim = true})       -- 通用"禁用动画"命名空间

-- ---- GTK layer-shell / launcher / notifications / logout ----
-- ignore_alpha 的值表示"透明度低于该阈值的像素不参与模糊计算"，
-- 数值越大，越多的半透明区域会被跳过模糊（可以理解成模糊的“阈值门槛”）
hl.layer_rule({ match = { namespace = "gtk-layer-shell" }, blur = true})
hl.layer_rule({ match = { namespace = "gtk-layer-shell" }, ignore_alpha = 0})
hl.layer_rule({ match = { namespace = "launcher" }, blur = true})
hl.layer_rule({ match = { namespace = "launcher" }, ignore_alpha = 0.5})
hl.layer_rule({ match = { namespace = "notifications" }, blur = true})
hl.layer_rule({ match = { namespace = "notifications" }, ignore_alpha = 0.69})
hl.layer_rule({ match = { namespace = "logout_dialog" }, blur = true}) -- wlogout 关机菜单

-- ---- ags 相关组件（侧边栏滑入动画 + 各面板模糊）----
hl.layer_rule({ match = { namespace = "sideleft.*" }, animation = "slide left"})
hl.layer_rule({ match = { namespace = "sideright.*" }, animation = "slide right"})
hl.layer_rule({ match = { namespace = "session[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "bar[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "bar[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "barcorner.*" }, blur = true})
hl.layer_rule({ match = { namespace = "barcorner.*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "dock[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "dock[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "indicator.*" }, blur = true})
hl.layer_rule({ match = { namespace = "indicator.*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "overview[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "overview[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "cheatsheet[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "cheatsheet[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "sideright[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "sideright[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "sideleft[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "sideleft[0-9]*" }, ignore_alpha = 0.6})
-- 注：原文件这里 indicator.* 的 blur/ignore_alpha 重复写了两遍，已去重
hl.layer_rule({ match = { namespace = "osk[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "osk[0-9]*" }, ignore_alpha = 0.6})

-- ---- Quickshell 组件 ----
-- Quickshell: illogical-impulse 主题
-- 先给所有 quickshell:* 图层统一开模糊 + 弹窗模糊 + 透明度阈值，
-- 下面再针对每个具体面板单独设置动画方式
hl.layer_rule({ match = { namespace = "quickshell:.*" }, blur_popups = true})
hl.layer_rule({ match = { namespace = "quickshell:.*" }, blur = true})
hl.layer_rule({ match = { namespace = "quickshell:.*" }, ignore_alpha = 0.79})
hl.layer_rule({ match = { namespace = "quickshell:bar" }, animation = "slide"})                     -- 顶栏：滑入
hl.layer_rule({ match = { namespace = "quickshell:actionCenter" }, no_anim = true})                 -- 操作中心：无动画
hl.layer_rule({ match = { namespace = "quickshell:cheatsheet" }, animation = "slide bottom"})       -- 速查表：底部滑入
hl.layer_rule({ match = { namespace = "quickshell:dock" }, animation = "slide bottom"})             -- Dock：底部滑入
hl.layer_rule({ match = { namespace = "quickshell:screenCorners" }, animation = "popin 120%"})      -- 屏幕圆角贴图：弹入
hl.layer_rule({ match = { namespace = "quickshell:lockWindowPusher" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:notificationPopup" }, animation = "fade"})        -- 通知弹窗：淡入淡出
hl.layer_rule({ match = { namespace = "quickshell:overlay" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:overlay" }, ignore_alpha = 1})
hl.layer_rule({ match = { namespace = "quickshell:overview" }, animation = "fade"})                 -- 工作区总览：淡入淡出
hl.layer_rule({ match = { namespace = "quickshell:osk" }, animation = "slide bottom"})              -- 屏幕键盘：底部滑入
hl.layer_rule({ match = { namespace = "quickshell:polkit" }, no_anim = true})                       -- 授权认证弹窗
-- 下面两条是为了修掉工具提示(tooltip)显示异常颜色的问题：
-- 理论上关掉 xray 就够了，但实测还需要额外把 ignore_alpha 设为 1 才彻底解决
hl.layer_rule({ match = { namespace = "quickshell:popup" }, xray = false})
hl.layer_rule({ match = { namespace = "quickshell:popup" }, ignore_alpha = 1})
hl.layer_rule({ match = { namespace = "quickshell:mediaControls" }, ignore_alpha = 1}) -- 媒体控制面板同理
hl.layer_rule({ match = { namespace = "quickshell:reloadPopup" }, animation = "slide"})             -- 配置重载提示：滑入
hl.layer_rule({ match = { namespace = "quickshell:regionSelector" }, no_anim = true})               -- 区域选择器
hl.layer_rule({ match = { namespace = "quickshell:screenshot" }, no_anim = true})                   -- 截图
hl.layer_rule({ match = { namespace = "quickshell:session" }, blur = true})                         -- 会话菜单（关机/注销）
hl.layer_rule({ match = { namespace = "quickshell:session" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:session" }, ignore_alpha = 0})
hl.layer_rule({ match = { namespace = "quickshell:sidebarRight" }, animation = "fade"})             -- 右侧边栏：淡入淡出
hl.layer_rule({ match = { namespace = "quickshell:sidebarLeft" }, animation = "fade"})              -- 左侧边栏：淡入淡出
hl.layer_rule({ match = { namespace = "quickshell:verticalBar" }, animation = "slide"})             -- 竖排任务栏：滑入
hl.layer_rule({ match = { namespace = "quickshell:osk" }, order = -1})                              -- 屏幕键盘层级下移

-- Quickshell: waffles 主题（另一套/额外组件）
hl.layer_rule({ match = { namespace = "quickshell:wallpaperSelector" }, animation = "slide top"})   -- 壁纸选择器：顶部滑入
hl.layer_rule({ match = { namespace = "quickshell:wNotificationCenter" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:wOnScreenDisplay" }, no_anim = true})              -- OSD（音量/亮度提示）
hl.layer_rule({ match = { namespace = "quickshell:wStartMenu" }, no_anim = true})                   -- 开始菜单
hl.layer_rule({ match = { namespace = "quickshell:wTaskView" }, ignore_alpha = 0})
hl.layer_rule({ match = { namespace = "quickshell:wTaskView" }, no_anim = true})                    -- 任务视图

-- 启动器类图层必须"快"，禁用动画减少感知延迟
hl.layer_rule({ match = { namespace = "gtk4-layer-shell" }, no_anim = true})
