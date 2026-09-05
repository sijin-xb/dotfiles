# 🐧 sijin-xb's Dotfiles 

这是我的个人 Linux 配置文件托管仓库。主要运行在 **CachyOS (Arch Linux)** 上，追求极致的响应速度与现代化工作流。

## 🛠️ 核心工具栈

| 类别 | 工具 |
| :--- | :--- |
| **OS** | [CachyOS](https://cachyos.org/) (Arch Linux Based) |
| **WM** | [Hyprland](https://hyprland.org/)（shell 为 [end-4 illogical-impulse](https://github.com/end-4/dots-hyprland) 的 Quickshell 配置） |
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

脚本会安装 `git`、`chezmoi` 和 `github-cli`，然后初始化并应用 dotfiles。

也可以先克隆仓库、审阅脚本后再执行：

```bash
gh repo clone sijin-xb/dotfiles ~/.local/share/chezmoi
bash ~/.local/share/chezmoi/install.sh
```

### 🧰 环境要求

- **系统**：仅支持 Arch 系发行版，脚本会检查 `/etc/arch-release`（CachyOS / Arch / EndeavourOS 均可）。
- **GitHub 认证**：仓库是私有的，`gh auth login` 必须先完成；没有凭据时脚本会明确报错退出，提示先登录。
- **基础依赖**：`git`、`chezmoi`、`github-cli` 由脚本通过 pacman 自动安装（`--needed`，已装则跳过）。
- **运行时依赖**：脚本只还原**配置文件**。Hyprland、Quickshell、fish、fcitx5 等运行时组件本身不在脚本安装范围内，请先按 [illogical-impulse 的依赖清单](https://github.com/end-4/dots-hyprland) 装好，或者还原后补装。
- **视频壁纸**：额外需要 `mpvpaper`（AUR）和 `ffmpeg`；缺失时切换视频壁纸会弹窗提示安装。
- **生效**：应用完成后注销并重新登录，启动完整会话。

## 🗑️ 卸载 (Uninstall)

```bash
chezmoi managed   # 列出 chezmoi 管理的文件
chezmoi purge     # 删除 chezmoi 自身的配置与源目录（不会删除已应用的 dotfiles）
```

`purge` 只清掉 chezmoi 本身；已经应用到 `~/.config` 的文件需要按 `chezmoi managed` 的清单手动删除，或者保留等着下次 `chezmoi apply` 覆盖更新。
