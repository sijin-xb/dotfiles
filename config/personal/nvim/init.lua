-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

-- 保存文件：Ctrl + s
vim.keymap.set({ "n", "i", "v" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save file" })

-- 复制：在可视化模式下按 Ctrl + C 复制到系统剪贴板
vim.keymap.set("v", "<C-c>", '"+y', { desc = "Copy to clipboard" })

-- 粘贴：在普通模式和插入模式下按 Ctrl + V 粘贴系统剪贴板内容
vim.keymap.set({ "n", "i" }, "<C-v>", "<C-r>+", { desc = "Paste from clipboard" })
