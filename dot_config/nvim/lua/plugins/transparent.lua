return {
    "xiyaowong/transparent.nvim",
    lazy = false, -- 插件需要立即启动以覆盖主题背景
    config = function()
    require("transparent").setup({
        extra_groups = { -- 额外需要透明的组
            "NormalFloat", -- 浮动窗口
            "NapiTreeNormal", -- 侧边栏
            "NeoTreeNormal",
            "NeoTreeNormalNC",
        },
    })
    -- 默认开启透明
    vim.cmd("TransparentEnable")
    end,
}
