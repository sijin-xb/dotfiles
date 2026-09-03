# 🐧 sijin-xb's Dotfiles 

这是我的个人 Linux 配置文件托管仓库。主要运行在 **CachyOS (Arch Linux)** 上，追求极致的响应速度与现代化工作流。

## 🛠️ 核心工具栈

| 类别 | 工具 |
| :--- | :--- |
| **OS** | [CachyOS](https://cachyos.org/) (Arch Linux Based) |
| **WM** | [niri](https://github.com/YaLTeR/niri) (Scrollable tiling Wayland compositor) |
| **Shell** | [fish](https://fishshell.com/) (with Fisher & fzf) |
| **Terminal** | [kitty](https://sw.kovidgoyal.net/kitty/) |
| **Manager** | [chezmoi](https://www.chezmoi.io/) |

## 🚀 快速恢复 (Installation)

如果你想在全新的 Arch Linux 系统中还原这些配置，私有仓库需要先登录 GitHub：

```bash
sudo pacman -S --needed github-cli
gh auth login
```

### 一键安装

登录 GitHub 后，使用下面的命令从私有仓库获取并运行安装脚本：

```bash
gh api repos/sijin-xb/dotfiles/contents/install.sh --jq .content \
  | base64 -d | bash
```

脚本会安装 `git` 和 `chezmoi`，然后初始化并应用 dotfiles。

也可以先克隆仓库、审阅脚本后再执行：

```bash
gh repo clone sijin-xb/dotfiles ~/.local/share/chezmoi
bash ~/.local/share/chezmoi/install.sh
