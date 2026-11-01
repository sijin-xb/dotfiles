-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
--
-- 本文件的取舍原则：保留「不是 vim 动词」的现代快捷键（存盘、移动行、跳词、注释、
-- 开关面板），把 vim 动词（yy / p / u / dd / ggVG）还给 vim 本身，以便边用边学。

local map = vim.keymap.set

-- ==========================================
-- 0. 还原 vim 原生行为
-- ==========================================

-- LazyVim 默认把 j/k 改成按「显示行」移动的 gj/gk。删掉那两条映射后，j/k 回到
-- vim 原生语义（按「逻辑行」移动），和教程、别人的配置、裸 vim 保持一致。
-- gj/gk 是 vim 内置命令，不需要额外映射。
pcall(vim.keymap.del, { "n", "x" }, "j")
pcall(vim.keymap.del, { "n", "x" }, "k")

-- ==========================================
-- 1. 保留的现代快捷键（都不是 vim 动词，不与学习冲突）
-- ==========================================

-- 保存: Ctrl + S (各种模式下均有效)
map({ "i", "x", "n", "s" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save File" })

-- 插入模式下 Ctrl + C 视同 Esc。
-- 原因：vim 原生的 <C-c> 离开插入模式时【不触发 InsertLeave】，fcitx.nvim 就不会
-- 切回英文，你会带着中文输入法回到 normal 模式，然后按的每个命令都变成拼音。
map("i", "<C-c>", "<Esc>", { desc = "Escape (fires InsertLeave)" })

-- 类似 VS Code 的 Alt + 上下箭头移动行
map("n", "<A-j>", "<cmd>m .+1<cr>==", { desc = "Move Down" })
map("n", "<A-k>", "<cmd>m .-2<cr>==", { desc = "Move Up" })
map("i", "<A-j>", "<esc><cmd>m .+1<cr>==gi", { desc = "Move Down" })
map("i", "<A-k>", "<esc><cmd>m .-2<cr>==gi", { desc = "Move Up" })
map("v", "<A-j>", ":m '>+1<cr>gv=gv", { desc = "Move Down" })
map("v", "<A-k>", ":m '<-2<cr>gv=gv", { desc = "Move Up" })

-- 插入模式下用 Ctrl + 方向键 快速跳词
map("i", "<C-Left>", "<Esc>bi", { desc = "Move word left" })
map("i", "<C-Right>", "<Esc>ea", { desc = "Move word right" })

-- 注释代码: Ctrl + /
-- 插入模式必须走 <C-o>，否则 "gcc" 会被当成普通字符直接打进正文。
map({ "n", "v" }, "<C-/>", "gcc", { remap = true, desc = "Toggle Comment" })
map("i", "<C-/>", "<C-o>gcc", { desc = "Toggle Comment" })

-- ==========================================
-- 2. 文件 / 查找 / 终端：Ctrl 与 <leader> 双轨
-- ==========================================
-- 下面调用的 picker / explorer / terminal 都走 LazyVim 当前启用的那一套
-- （已在 lazyvim.json 切到 Telescope / Neo-tree / snacks），所以 Ctrl 键和
-- <leader> 键指向同一个工具，不会出现两个文件树、两套搜索结果。

-- 侧边栏开关: Ctrl + B（等价 <leader>e）
map("n", "<C-b>", function()
  require("neo-tree.command").execute({ toggle = true, dir = LazyVim.root() })
end, { desc = "Toggle Explorer" })

-- 快速查找文件: Ctrl + P（等价 <leader>ff）
map("n", "<C-p>", LazyVim.pick("files"), { desc = "Find Files" })

-- 搜索当前文件内容: Ctrl + F（等价 <leader>sb）
map("n", "<C-f>", "<cmd>Telescope current_buffer_fuzzy_find<cr>", { desc = "Buffer Search" })

-- 终端开关: Ctrl + `（等价 <leader>ft）
map({ "n", "t" }, "<C-`>", function()
  Snacks.terminal.focus(nil, { cwd = LazyVim.root() })
end, { desc = "Toggle Terminal" })
