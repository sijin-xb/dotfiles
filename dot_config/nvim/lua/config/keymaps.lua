-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua

local map = vim.keymap.set

-- ==========================================
-- 1. 基础编辑 (Ctrl + 系)
-- ==========================================

-- 全选: Ctrl + A
map("n", "<C-a>", "ggVG", { desc = "Select All" })

-- 保存: Ctrl + S (各种模式下均有效)
map({ "i", "x", "n", "s" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save File" })

-- 撤销/重做: Ctrl + Z / Ctrl + Y
map("n", "<C-z>", "u", { desc = "Undo" })
map("n", "<C-y>", "<C-r>", { desc = "Redo" })
map("i", "<C-z>", "<Cmd>u<CR>", { desc = "Undo in Insert Mode" })

-- 复制/剪切/粘贴 (对接系统剪贴板)
map({ "n", "v" }, "<C-c>", '"+y', { desc = "Copy to System Clipboard" })
map({ "n", "v" }, "<C-x>", '"+d', { desc = "Cut to System Clipboard" })
map({ "n", "v", "i" }, "<C-v>", '<C-r>+', { desc = "Paste from System Clipboard" })

-- ==========================================
-- 2. 现代行操作 (Alt + 方向键 移动行)
-- ==========================================

-- 类似 VS Code 的 Alt + 上下箭头移动行
map("n", "<A-j>", "<cmd>m .+1<cr>==", { desc = "Move Down" })
map("n", "<A-k>", "<cmd>m .-2<cr>==", { desc = "Move Up" })
map("i", "<A-j>", "<esc><cmd>m .+1<cr>==gi", { desc = "Move Down" })
map("i", "<A-k>", "<esc><cmd>m .-2<cr>==gi", { desc = "Move Up" })
map("v", "<A-j>", ":m '>+1<cr>gv=gv", { desc = "Move Down" })
map("v", "<A-k>", ":m '<-2<cr>gv=gv", { desc = "Move Up" })

-- ==========================================
-- 3. 界面与导航
-- ==========================================

-- 侧边栏开关: Ctrl + B (类似 VS Code)
map("n", "<C-b>", "<cmd>Neotree toggle<cr>", { desc = "Toggle Explorer" })

-- 快速查找文件: Ctrl + P
map("n", "<C-p>", "<cmd>Telescope find_files<cr>", { desc = "Find Files" })

-- 快速全局搜索文本: Ctrl + F
-- 注意：在 Vim 中习惯用 / 搜索，但我们可以映射 Ctrl+F 弹出更现代的搜索
map("n", "<C-f>", "<cmd>Telescope current_buffer_fuzzy_find<cr>", { desc = "Buffer Search" })

-- 终端开关: Ctrl + ` (或者 Ctrl + t)
map({ "n", "t" }, "<C-`>", "<cmd>ToggleTerm<cr>", { desc = "Toggle Terminal" })

-- ==========================================
-- 4. 插入模式下的舒适操作
-- ==========================================

-- 在插入模式下用 Ctrl + 方向键 快速跳词 (现代人类习惯)
map("i", "<C-Left>", "<Esc>bi", { desc = "Move word left" })
map("i", "<C-Right>", "<Esc>ea", { desc = "Move word right" })

-- 注释代码: Ctrl + / (注意：某些终端可能需要映射为 <C-_>)
map({ "n", "i", "v" }, "<C-/>", "gcc", { remap = true, desc = "Toggle Comment" })
