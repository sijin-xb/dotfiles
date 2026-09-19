# ===================== PATH =====================
set -gx PATH ~/.npm-global/bin $PATH
set -gx PATH "/home/xibie/.local/bin" $PATH

# ===================== Caelestia QML 插件 =====================
if test -d ~/src/caelestia-shell/build/qml
    set -gx QML2_IMPORT_PATH ~/src/caelestia-shell/build/qml $QML2_IMPORT_PATH
end

# ===================== INTERACTIVE =====================
if status is-interactive
    # Starship
    starship init fish | source

    # 禁用默认 greeting
    function fish_greeting
        fastfetch
    end

    # Colors
    set -g fish_color_valid_path --underline '#d5bbff'
    set -g fish_color_param '#e7e0ea'

    # Aliases
    alias clear "printf '\033[2J\033[3J\033[1;1H'"
    alias celar clear
    alias claer clear
    alias pamcan pacman
    alias q 'qs -c ii'

    if type -q eza
        alias ls 'eza --icons --group-directories-first'
        alias ll 'eza -lah --icons'
    end

    if test "$TERM" = xterm-kitty
        alias ssh 'kitten ssh'
    end

    if type -q zoxide
        zoxide init fish | source
    end

    stty -ixon
end

# ===================== CLASH =====================
function clashon;  sudo clashctl on;  end
function clashoff; sudo clashctl off; end
function clashui;  sudo clashctl ui;  end
function clashstatus; sudo clashctl status; end

abbr -a f fastfetch
abbr -a fa fastfetch
abbr -a fas fastfetch
abbr -a fast fastfetch
abbr -a fastf fastfetch

alias poweroff='systemctl poweroff'
alias reboot='systemctl reboot'
