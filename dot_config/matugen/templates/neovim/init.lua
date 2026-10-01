-- ==========================================================================
-- 1. 自动安装插件管理器 (Lazy.nvim)
-- ==========================================================================
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- ==========================================================================
-- 2. 加载插件 (已替换为更稳定的源)
-- ==========================================================================
require("lazy").setup({
  {
    -- 【关键修改】换成了官方社区版，更稳定，不会报错
    "RRethy/base16-nvim",
    lazy = false,
    priority = 1000,
  },
})

-- ==========================================================================
-- 3. Matugen 热更新逻辑
-- ==========================================================================
local function source_matugen()
  local matugen_path = vim.fn.stdpath('config') .. "/generated.lua"

  local f = io.open(matugen_path, "r")
  if f ~= nil then
    io.close(f)
    -- 尝试执行生成的文件
    local ok, err = pcall(dofile, matugen_path)
    if not ok then
      -- 如果加载出错，只打印提示，不阻断启动
      print("Matugen Load Error: " .. err)
    end
  else
    -- 如果还没有生成过文件，使用内置主题兜底
    vim.cmd.colorscheme('habamax') 
  end
end

-- 热重载函数
local function matugen_reload()
  -- 重新加载颜色
  source_matugen()
  
  -- 如果你有 lualine，可以在这里刷新
  -- package.loaded['lualine'] = nil
  -- require('lualine').setup({ options = { theme = 'base16' } })
  
  -- 修复一些高亮丢失
  vim.api.nvim_set_hl(0, "Comment", { italic = true })
end

-- 监听 Matugen 发出的信号
vim.api.nvim_create_autocmd("Signal", {
  pattern = "SIGUSR1",
  callback = function()
    matugen_reload()
    print("Matugen 颜色已更新！")
  end,
})

-- 启动时加载一次
source_matugen()