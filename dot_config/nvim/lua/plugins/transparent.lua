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

    -- 切到 matugen 配色。必须放在 TransparentEnable 之后：
    -- transparent.nvim 是在 ColorScheme autocmd 里清背景的，先注册 autocmd
    -- 再切主题，新主题才会被清一遍；反过来切则新主题会带着实心背景。
    --
    -- 生成物缺失时（还没跑过 matugen / 换过壁纸前）不让 nvim 开不起来：
    -- 回退内置 habamax 并提示一次。
    local ok, err = pcall(vim.cmd.colorscheme, "matugen")
    if not ok then
        vim.cmd.colorscheme("habamax")
        vim.notify(
            "[matugen] 没找到生成的配色（~/.config/nvim/colors/matugen.lua），已回退 habamax。" .. tostring(err),
            vim.log.levels.WARN
        )
    end
    end,
}
