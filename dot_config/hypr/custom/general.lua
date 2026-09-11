-- ============================================================
-- 液态玻璃效果 - 高级补充配置
-- ------------------------------------------------------------
-- 【重要】主参数（窗口圆角 / 模糊半径 / 模糊迭代次数 / 边框大小
--         / 内部间距 / 外部间距 / 活动 & 非活动窗口不透明度）
-- 请直接在 quickshell 设置面板 → "配置文件" → "Hyprland"
-- 中用滑条调节，那里的修改会写入 shellOverrides 并最终生效。
--
-- 本文件只放 quickshell 面板里【调不到】的高级参数，
-- 用来增强玻璃质感（vibrancy 染色、噪点、阴影细项等）。
-- ============================================================

hl.config({
    decoration = {
        -- -------- 圆角曲线 --------
        -- 2.0=正圆, 2.5-3.0=更柔和的 squircle (液态玻璃推荐)
        rounding_power = 2.8,

        -- -------- 模糊高级参数（面板里只有 size / passes，调不到这些）--------
        blur = {
            -- xray：让模糊采样"看穿"窗口 alpha，玻璃效果的关键
            xray = true,
            -- special 工作区也使用模糊
            special = true,
            -- 启用新优化，保持性能
            new_optimizations = true,

            -- 亮度 & 对比度：轻微加强让模糊后层次更清楚
            brightness = 1.02,
            contrast   = 1.03,

            -- 微噪点：消除色带 + 模拟玻璃表面的细微颗粒
            noise = 0.025,

            -- Vibrancy 染色：把背景颜色"染"到窗口上 → 真实玻璃色散感
            vibrancy          = 0.55,
            vibrancy_darkness = 0.35,

            -- 弹窗 / 输入法面板也开模糊
            popups            = true,
            popups_ignorealpha        = 0.5,
            input_methods     = true,
            input_methods_ignorealpha = 0.7,
        },

        -- 阴影已移到 matugen 模板（~/.config/matugen/templates/hyprland/colors.lua），
        -- 以便跟随主题色。这里若要覆盖，取消下面注释并改值即可：
        -- shadow = {
        --     range        = 15,
        --     render_power = 4,
        --     offset       = {0, 0},
        --     color        = "rgba(8e49581A)",
        -- },

        -- -------- 非活跃窗口变暗（面板里调不到的 dim 细项）--------
        dim_inactive = true,
        -- 非活跃窗口额外暗一点，和活跃窗口在阴影层次上拉得更开
        dim_strength = 0.12,
        dim_special  = 0.18,

        -- 全屏保持完全不透明（面板里调不到）
        fullscreen_opacity = 1.0,
    },
})
