-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
-- Options are automatically loaded before lazy.nvim startup
-- Default options: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua

local opt = vim.opt

-- ==========================================
-- 1. 现代交互 (鼠标与剪贴板)
-- ==========================================
opt.mouse = "a"               -- 彻底开启鼠标支持，点击、缩放、滚动随心所欲
opt.clipboard = "unnamedplus" -- 默认与系统剪贴板同步（Ctrl+C/V 飞起）

-- ==========================================
-- 2. 视觉体验 (配合你的 kitty + niri)
-- ==========================================
opt.cursorline = true         -- 高亮当前行（现代编辑器标配）
opt.termguicolors = true      -- 开启真彩色支持，充分发挥你显卡的色彩渲染
opt.laststatus = 3            -- 全局状态栏，不再为每个窗口开一个条，简洁美观
opt.signcolumn = "yes"        -- 始终显示左侧符号列（防止代码抖动）

-- ==========================================
-- 3. 编辑行为 (告别 Vim 迷惑逻辑)
-- ==========================================
opt.scrolloff = 10            -- 光标到达屏幕边缘前保留 10 行（类似滚动保护）
opt.sidescrolloff = 8         -- 左右滚动同理
opt.confirm = true            -- 未保存退出时弹出确认确认框，而不是直接报错
opt.ignorecase = true         -- 搜索时忽略大小写
opt.smartcase = true          -- 只要你输入了大写字母，就自动切换到精确匹配
opt.undofile = true           -- 开启持久化撤销，关掉编辑器重启也能 Ctrl+Z

-- ==========================================
-- 4. 缩进配置 (适合 Rust/现代前端)
-- ==========================================
opt.expandtab = true          -- 把 Tab 变成空格（现代开发规范）
opt.shiftwidth = 4            -- 缩进 4 格
opt.tabstop = 4               -- Tab 占 4 格
opt.smartindent = true        -- 智能缩进

-- ==========================================
-- 5. 性能与响应
-- ==========================================
opt.updatetime = 200          -- 响应时间从 4000ms 降到 200ms，LSP 提示飞快
opt.timeoutlen = 300          -- 组合键等待时间（如果你按 Ctrl+S 慢了点也不会断）
