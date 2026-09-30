-- 配色不在这里声明插件：由 matugen 从壁纸生成到
-- ~/.config/nvim/colors/matugen.lua（模板见
-- dot_config/matugen/templates/editors/nvim.lua），走 nvim 原生的
-- :colorscheme 机制，与 kitty / fuzzel / walker / GTK / micro / Kate
-- 共用同一份 M3 色板。
--
-- 切换时机放在 transparent.lua 里（TransparentEnable 之后），
-- 因为 transparent.nvim 是靠 ColorScheme autocmd 重新清背景的：
-- 先 setup 把 autocmd 注册好、再切主题，透明才会被重新应用一遍。
return {}
