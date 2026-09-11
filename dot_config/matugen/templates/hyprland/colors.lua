hl.config({
    general = {
        col = {
            -- Note: the dynamic (lua) config setter parses a single color;
            -- multi-stop gradients are only accepted by window rules
            active_border   = "rgba({{colors.primary.default.hex_stripped}}AA)",
            inactive_border = "rgba({{colors.surface_container_low.default.hex_stripped}}33)",
        },
    },
    misc = {
        background_color = "rgba({{colors.surface.dark.hex_stripped}}FF)",
    },
    -- 阴影：参数对齐 Caelestia（小范围 + 柔和羽化 + 主题色），
    -- 颜色用 inverse_primary，随壁纸主题变化
    decoration = {
        shadow = {
            enabled      = true,
            range        = 15,
            render_power = 4,
            offset       = {0, 0},
            color        = "rgba({{colors.inverse_primary.default.hex_stripped}}1A)",
        },
    },
})

hl.window_rule({
    match        = { pin = 1 },
    border_color = "rgba({{colors.primary.default.hex_stripped}}AA) rgba({{colors.primary.default.hex_stripped}}77)",
})
