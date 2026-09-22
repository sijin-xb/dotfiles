-- 中文输入法自动切换（fcitx5）
--
-- 行为：离开插入模式 / 命令行模式时切回英文，进入插入模式 / 命令行模式时恢复中文，
-- 并且按 buffer 记住各自的输入法状态。学 vim 的过程就是不停按 Esc 回 normal 模式，
-- 没有这个插件的话，你在 normal 模式下按的每个命令都会先被输入法吃掉变成拼音。
--
-- 前提（已核实本机满足）：
--   1. fcitx5-remote 在 PATH 里（/usr/bin/fcitx5-remote）
--   2. fcitx5 的输入法列表里「英文排第一、中文排第二」
--      （~/.config/fcitx5/profile: keyboard-us 为 Items/0，rime 为 Items/1）
--
-- 注：插件自带 plugin/ 目录里的 autocmd，不需要 setup()。

return {
  {
    "h-hg/fcitx.nvim",
    lazy = false, -- 需要尽早注册 autocmd，所以不走懒加载
  },
}
