# ===================== PATH =====================
set -gx PATH ~/.npm-global/bin $PATH
# ⚠ 这里以前写死了 /home/xibie/.local/bin —— 换用户名/换机器就静默失效
#   （PATH 里多一条不存在的路径，不报错但 ~/.local/bin 下的东西全找不到）。
set -gx PATH ~/.local/bin $PATH

# ===================== Caelestia QML 插件 =====================
# caelestia-dots/shell 仓库里只有 QML 源码，Caelestia 这个 Qt 插件要自己
# cmake 编译。源码在 ~/src/caelestia-plugin-src，产物固定在
# ~/src/caelestia-build/qml（见 install.sh 的 [4a/7]）。
# 没构建过（目录不存在）就不注入，免得污染其它 Qt 程序。
# 注意：hyprland/scripts/start_quickshell.sh 里还有一份同样的注入（会话自启用），
# 两处要一致 —— 这里以前写的是 execs.lua，实际早就挪进那个脚本了。
#
# 幂等：fish 里再开 fish 会重复执行本文件，不判重的话
# QML2_IMPORT_PATH 会累积成 "a:a:a"。
if test -d ~/src/caelestia-build/qml
    if not contains ~/src/caelestia-build/qml $QML2_IMPORT_PATH
        set -gx QML2_IMPORT_PATH ~/src/caelestia-build/qml $QML2_IMPORT_PATH
    end
end

# ===================== INTERACTIVE =====================
if status is-interactive
    # Starship
    starship init fish | source

    # 禁用默认 greeting
    function fish_greeting
        fastfetch
    end

    # 配色不在本文件设：conf.d/matugen-colors.fish（matugen 生成）管全套
    # fish_color_* / fish_pager_color_*。
    # ⚠ fish 先按字母序 source conf.d/*.fish，最后才读 config.fish —— 在这里
    #   写任何 fish_color_* 都会反过来覆盖 matugen。原来这两行就是旧配色残留
    #   （valid_path 紫 #d5bbff、param 灰 #e7e0ea），已删。

    # Aliases
    alias clear "printf '\033[2J\033[3J\033[1;1H'"
    alias celar clear
    alias claer clear
    alias pamcan pacman
    alias q 'qs -c caelestia'

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
fish_add_path /opt/rocm/bin
