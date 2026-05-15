#  sijin-xb's Dotfiles 

这是我的个人 Linux 配置文件托管仓库。主要运行在 **CachyOS (Arch Linux)** 上，追求极致的响应速度与现代化工作流。

##  核心工具栈

| 类别 | 工具 |
| :--- | :--- |
| **OS** | [CachyOS](https://cachyos.org/) (Arch Linux Based) |
| **WM** | [niri](https://github.com/YaLTeR/niri) (Scrollable tiling Wayland compositor) |
| **Shell** | [fish](https://fishshell.com/) (with Fisher & fzf) |
| **Terminal** | [kitty](https://sw.kovidgoyal.net/kitty/) |
| **Manager** | [chezmoi](https://www.chezmoi.io/) |

## 🚀 快速恢复 (Installation)

如果你想在全新的系统中还原这些配置，只需安装 `chezmoi` 后运行一行命令：

```bash
# 安装 chezmoi (Arch)
sudo pacman -S chezmoi

# 初始化并应用配置
chezmoi init --apply [https://github.com/sijin-xb/dotfiles.git](https://github.com/sijin-xb/dotfiles.git)
