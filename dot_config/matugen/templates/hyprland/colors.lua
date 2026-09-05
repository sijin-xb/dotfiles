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
})

hl.window_rule({
    match        = { pin = 1 },
    border_color = "rgba({{colors.primary.default.hex_stripped}}AA) rgba({{colors.primary.default.hex_stripped}}77)",
})
