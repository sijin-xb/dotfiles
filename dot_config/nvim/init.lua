-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

-- 保存文件：Ctrl + s
vim.keymap.set({ "n", "i", "v" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save file" })
