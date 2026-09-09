# sijin-xb's dotfiles

个人桌面配置：Arch 系（开发环境 CachyOS）+ Hyprland + Quickshell。
源码树使用 chezmoi 风格命名（`dot_`、`executable_` 前缀），但安装由自带
bash 脚本完成，不需要 chezmoi 二进制。

> **English (brief)**: Personal desktop configuration for Arch-based systems
> with Hyprland and Quickshell. Clone the repo and run `./install.sh` (TUI)
> or `./install.sh install`; the same script provides `rollback`, `restore`,
> `archive` and `uninstall`. Full documentation below is in Chinese.

## 包含内容

- Hyprland 配置（Lua）。`hyprland/` 为模板层，`custom/` 为个人覆盖层
  （同名文件在模板之后加载并覆盖模板）
- Quickshell（end4-pC fork）差异层：栏、侧边栏、启动器、总览、设置面板
- 锁屏：Quickshell LockSurface（时钟、媒体卡片：专辑封面 / 可拖拽进度条 /
  播放控制、密码输入、电源按钮）；quickshell 未运行时回退 hyprlock
- 桌面歌词：逐字计时（酷狗 KRC），适配任意 MPRIS 播放器
- matugen 壁纸取色：kitty / alacritty / foot / fastfetch / fcitx5 / mako /
  Hyprland 联动配色
- fish（fzf 绑定、nvm）、nvim（LazyVim）、btop、fastfetch、fuzzel、mako 配置

## 环境要求

- Arch 系发行版（存在 `/etc/arch-release`）
- Hyprland（Wayland 会话）
- 普通用户运行，需要 sudo 权限（pacman 用）
- quickshell / matugen / mpvpaper 缺失时由脚本自动安装
  （pacman → AUR → 源码编译）

## 安装

```bash
git clone https://github.com/sijin-xb/dotfiles.git
cd dotfiles
./install.sh           # TUI 二级菜单
./install.sh install   # 直接执行完整安装
```

安装步骤：

1. pacman 基础依赖（hyprland、kitty、fish、fuzzel、fcitx5、cliphist、
   hypridle、hyprlock、xdg portals、qt6 工具链）
2. AUR 包（matugen、mpvpaper）；无 AUR helper 时自动安装 yay
3. quickshell 三级回退：已有二进制 → pacman → AUR → 源码编译
4. 部署 `dot_*` 条目到 `$HOME`；有差异的已存在文件先备份到
   `~/.local/state/dotfiles-backup/` 再覆盖
5. 首次运行克隆 quickshell 底盘（pctrade/end4-pC）
6. 创建 python venv（pypinyin、dbus-python），供启动器拼音搜索使用

重复运行幂等。

## 脚本命令

| 命令 | 功能 |
|---|---|
| `install` | 完整安装；开始前创建 pre-install 快照 |
| `rollback` | 还原到 pre-install 快照；开始前创建 pre-rollback 快照 |
| `restore` | 重新应用 pre-rollback 快照（撤销回档） |
| `archive [-o PATH] [--delete]` | 打包配置 / 状态 / 缓存为 tar.gz（含 MANIFEST.txt）；`--delete` 打包后清理源文件 |
| `uninstall` | 可选先存档，然后删除受管理路径 |
| 无参数 / `--tui` | 二级菜单 TUI |
| `-h` | 帮助 |

快照仅覆盖脚本内受管理路径清单（`SNAP_PATHS`），清单外的文件不会被改动。

## 快捷键（节选）

| 按键 | 功能 |
|---|---|
| Super | 启动器（拼音搜索） |
| Super+T | 终端召唤（quake 风格 kitty） |
| Super+S | 临时工作区 scratchpad |
| Super+L | 锁屏（quickshell 锁屏界面） |
| Super+Q | 关闭窗口 |
| Super+1..0、Super+方向键 | 切换工作区 / 焦点 |
| Super+Shift+方向键 | 移动窗口 |
| Super+Shift+S、Print | 区域截图 |
| Super+Shift+R | 区域录屏 |
| Super+Shift+P / N / B | 播放暂停 / 下一首 / 上一首 |
| Super+F1 | 重启 fcitx5 |
| Ctrl+Super+T | 壁纸选择器 |

完整列表：`~/.config/hypr/hyprland/keybinds.lua` 与
`~/.config/hypr/custom/keybinds.lua`。

## 目录结构

```
dot_config/
  hypr/
    hyprland.lua          配置入口
    hyprland/             模板层（keybinds、general、rules、env、execs、scripts）
    custom/               个人覆盖层（同名文件覆盖模板）
    hyprlock.conf         回退锁屏配置
    hyprlock/             配色与辅助脚本
  quickshell/end4-pC/     shell 差异层（modules、services、scripts）
  fish/  kitty/  foot/  alacritty/  nvim/  btop/  fastfetch/  fuzzel/  mako/  matugen/
install.sh                安装 / 卸载 / 回档 / 存档 / TUI
```

## 锁屏

`Super+L` 触发 `quickshell:lock`。锁屏界面显示模糊后的桌面壁纸（与桌面
背景同一源链，含 `lockWall` 覆盖与视频缩略图分支）、时钟与日期、媒体卡片
（专辑封面、歌名 / 艺术家、可拖拽进度条、上一首 / 播放暂停 / 下一首）、
密码输入框与电源按钮。hypridle 超时锁屏走同一入口；quickshell 未运行时
使用 hyprlock。

## 说明

- 更换壁纸会触发重新取色；模板位于 `dot_config/matugen/templates/`
- 桌面歌词偏移微调：
  `qs -c end4-pC ipc call desktoplyrics offset_faster / offset_slower`
- 备份根目录：`~/.local/state/dotfiles-backup/`（`snapshots/`、`state/`）

## 许可证

本项目采用 [GPL-3.0](LICENSE) 许可证。
