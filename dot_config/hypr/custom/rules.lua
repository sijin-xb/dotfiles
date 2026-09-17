-- ============================================================
-- 窗口 / 工作区规则 — 用户覆盖层
-- ============================================================

-- -------- 终端召唤（SUPER + T）：kitty 常驻 special:quake --------
-- 切换逻辑在 quickshell 的 scripts/hyprland/term-summon.sh
hl.workspace_rule({ workspace = "special:quake", gaps_out = 30 })

hl.window_rule({
    match = { class = "kitty-quake" },
    float = true,
    workspace = "special:quake silent",
    size = { "(monitor_w*0.72)", "(monitor_h*0.62)" },
               center = true,
               opacity = 0.93,
               rounding = 14,
})

-- ============================================================
-- 液态玻璃：差异化透明度
-- 主参数（圆角 / 模糊半径 / 全局透明度）在 quickshell 面板里调
-- 这里只放 window_rule 层面的差异化规则
-- ============================================================

-- -------- 终端类：稍高透明度 --------
hl.window_rule({
    match = { class = "^(kitty|foot|Alacritty|wezterm|kitty-quake)$" },
               opacity = 0.90,
})

-- -------- 浏览器：保持可读性 --------
hl.window_rule({
    match = { class = "^(firefox|zen|zen-browser|chromium|brave-browser|google-chrome|microsoft-edge|vivaldi)$" },
               opacity = 0.92,
})

-- -------- 编辑器 / IDE：与终端同档 --------
hl.window_rule({
    match = { class = "^(code|code-oss|VSCodium|jetbrains-.*|neovide)$" },
               opacity = 0.93,
})

-- -------- 视频 / 游戏：完全不透明 + 关模糊 --------
hl.window_rule({
    match = { class = "^(mpv|vlc|celluloid|steam_app_.*|gamescope)$" },
               opacity = 1.0,
               no_blur = true,
})

-- -------- 截图 / 录屏 / 取色：豁免模糊 --------
hl.window_rule({
    match = { class = "^(flameshot|grim|slurp|hyprpicker|obs|wf-recorder)$" },
               no_blur = true,
})

-- -------- 输入法候选框：避免文字发虚 --------
hl.window_rule({
    match = { class = "^(fcitx|fcitx5|ibus)$" },
               no_blur = true,
})

-- -------- 系统弹窗：强制浮动 + 居中 --------
hl.window_rule({
    match = { class = "^(pavucontrol|nm-connection-editor|blueman-manager|xdg-desktop-portal-gtk)$" },
               float = true,
               center = true,
})

-- -------- 画中画（浏览器 PiP）：悬浮 + 固定 --------
hl.window_rule({
    match = { title = "^(Picture-in-Picture)$" },
               float = true,
               pin = true,
               size = { "480", "270" },
})
