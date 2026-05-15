# ===================== STARSHIP =====================
starship init fish | source

# ===================== PATH =====================
set -gx PATH ~/.npm-global/bin $PATH

# ===================== INTERACTIVE =====================
if status is-interactive

    # 禁用默认 fish greeting
    function fish_greeting
        fastfetch
    end

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
