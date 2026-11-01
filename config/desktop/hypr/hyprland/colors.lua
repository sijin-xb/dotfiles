hl.config({
    general = {
        col = {
            -- Note: the dynamic (lua) config setter parses a single color;
            -- multi-stop gradients are only accepted by window rules
            active_border   = "rgba(90d5aeAA)",
            inactive_border = "rgba(171d1933)",
        },
    },
    misc = {
        background_color = "rgba(0f1511FF)",
    },
})

hl.window_rule({
    match        = { pin = 1 },
    border_color = "rgba(90d5aeAA) rgba(90d5ae77)",
})
