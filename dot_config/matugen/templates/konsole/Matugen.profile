# =============================================================================
#  Konsole 配置档 —— matugen 生成，不要手改
#  模板：~/.config/matugen/templates/konsole/Matugen.profile
#
#  Konsole 的「配色方案」不是直接选的：konsolerc 里记一个默认 profile，
#  profile 里再记它用哪个 ColorScheme。所以要真正切色，需要三件东西齐全：
#    1. ~/.local/share/konsole/Matugen.colorscheme   （颜色本体）
#    2. ~/.local/share/konsole/Matugen.profile       （本文件，指向 1）
#    3. ~/.config/konsolerc 的 DefaultProfile=Matugen.profile
#  第 3 步由 hooks/post_hook.sh 负责写入，因为它不在 matugen 的模板体系里。
#
#  Parent=FALLBACK/ 表示其余设置继承 Konsole 内置默认值，不复制一份出来，
#  这样 Konsole 升级后新增的选项会自动生效。
# =============================================================================

[General]
Name=Matugen
Parent=FALLBACK/

[Appearance]
ColorScheme=Matugen
