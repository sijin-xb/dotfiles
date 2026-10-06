"""dotctl —— dotfiles 安装器的 Python 引擎（纯标准库，3.11+）。

迁移期状态：一部分子命令已经在这里，其余仍在 bash（install.sh + lib/*.sh）
里，由 install.sh 分发。每迁一个就在 cli.COMMANDS 里加一条，并把
lib/8x-cmd-*.sh 的实现换成一行转发 —— 不要两边各留一份实现。
"""
