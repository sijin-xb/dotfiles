# ===================== STARSHIP =====================
starship init fish | source

# ===================== PATH =====================
set -gx PATH ~/.npm-global/bin $PATH

# ===================== Caelestia QML 插件（可选） =====================
# 自行 clone caelestia-dots/shell 并编译后，把 build/qml 加入 Qt 导入路径。
# 目录不存在时不设置，对未装插件的环境零影响。
if test -d ~/src/caelestia-shell/build/qml
    set -gx QML2_IMPORT_PATH ~/src/caelestia-shell/build/qml $QML2_IMPORT_PATH
end

# ===================== INTERACTIVE =====================
if status is-interactive

    # 禁用默认 fish greeting
    function fish_greeting
        fastfetch
    end

    # ===================== COLORS =====================
    # 命令参数里的有效路径（如 `kate keybinds.lua` 的 keybinds.lua）
    # 默认继承 fish_color_param 太暗，显式设成 kitty 主题的亮紫
    set -g fish_color_valid_path --underline '#d5bbff'
    # 普通命令参数同步提亮，避免混排时明暗突兀
    set -g fish_color_param '#e7e0ea'

    # ===================== ALIASES =====================
    alias clear "printf '\033[2J\033[3J\033[1;1H'"
    alias celar clear
    alias claer clear

    alias pamcan pacman
    alias q 'qs -c ii'

    # eza
    if type -q eza
        alias ls 'eza --icons --group-directories-first'
        alias ll 'eza -lah --icons'
    end

    # kitty ssh
    if test "$TERM" = xterm-kitty
        alias ssh 'kitten ssh'
    end

    # zoxide（不要覆盖 cd）
    if type -q zoxide
        zoxide init fish | source
    end

end

# ===================== CLASH =====================
function clashon
    sudo clashctl on
end

function clashoff
    sudo clashctl off
end

function clashui
    sudo clashctl ui
end

function clashstatus
    sudo clashctl status
end

abbr -a f fastfetch
abbr -a fa fastfetch
abbr -a fas fastfetch
abbr -a fast fastfetch
abbr -a fastf fastfetch

stty -ixon

alias poweroff='systemctl poweroff'
alias reboot='systemctl reboot'


# Added by Antigravity CLI installer
set -gx PATH "/home/xibie/.local/bin" $PATH
