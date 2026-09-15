# sijin-xb's dotfiles

个人桌面配置：Arch 系（开发环境 CachyOS）+ Hyprland + Quickshell。
源码树使用 chezmoi 风格命名（`dot_`、`executable_` 前缀），但安装由自带
bash 脚本完成，不需要 chezmoi 二进制。

> **English (brief)**: Personal desktop configuration for Arch-based systems
> with Hyprland and Quickshell. Clone the repo and run `./install.sh` (TUI)
> or `./install.sh install`; the same script provides `rollback`, `restore`,
> `archive` and `uninstall`. Full documentation below is in Chinese.

## 目录

- [包含内容](#包含内容)
- [环境要求](#环境要求)
- [安装](#安装)
- [脚本命令](#脚本命令)
- [快捷键（节选）](#快捷键节选)
- [目录结构](#目录结构)
- [说明](#说明)
- [文档与更新日志](#文档与更新日志)
- [致谢与上游](#致谢与上游)
- [许可证](#许可证)

## 包含内容

- Hyprland 配置（Lua）。`hyprland/` 为模板层，`custom/` 为个人覆盖层
  （同名文件在模板之后加载并覆盖模板）
- Quickshell（end4-pC fork）差异层：栏、侧边栏、启动器、总览、设置面板
- 锁屏：Serpantinum 风格三栏布局（居中大时钟 → 点击展开三栏翼面板）；
  quickshell 未运行时回退 hyprlock。详见 [docs/lockscreen.md](docs/lockscreen.md)
- 桌面歌词：逐字计时（酷狗 KRC），适配任意 MPRIS 播放器；SPlayer 可走
  WebSocket 直推。详见 [docs/integrations.md](docs/integrations.md)
- 灵动岛：音乐 / 音量 / 录屏活动的顶部动态胶囊，详见
  [docs/dynamic-island-roadmap.md](docs/dynamic-island-roadmap.md)
- 壁纸视差与多后端视频壁纸，详见 [docs/appearance.md](docs/appearance.md)
- matugen 壁纸取色：kitty / alacritty / foot / fastfetch / fcitx5（含 fcitx5-rime
  候选框）/ mako / Hyprland 联动配色
- fish（fzf 绑定、nvm）、nvim（LazyVim）、btop、fastfetch、fuzzel、mako 配置

## 环境要求

- Arch 系发行版（存在 `/etc/arch-release`）
- Hyprland（Wayland 会话）
- 普通用户运行，需要 sudo 权限（pacman 用）
- quickshell / matugen / mpvpaper 缺失时由脚本自动安装
  （pacman → AUR → 源码编译）

## 安装

~~~bash
git clone https://github.com/sijin-xb/dotfiles.git
cd dotfiles
./install.sh           # TUI 二级菜单
./install.sh install   # 直接执行完整安装
~~~

安装步骤：

1. pacman 基础依赖（hyprland、kitty、fish、fuzzel、fcitx5、cliphist、
   hypridle、hyprlock、xdg portals、qt6 工具链，以及 Caelestia QML 插件
   编译所需的 aubio / libpipewire / libqalculate / lm_sensors / fftw /
   spirv-tools）。**默认只装缺失项，不滚动系统**；需要全量升级时用
   `FULL_UPGRADE=1 ./install.sh install`
2. AUR 包（matugen、mpvpaper、libcava）；无 AUR helper 时自动安装 yay
3. quickshell 三级回退：已有二进制 → pacman → AUR → 源码编译
4. **Caelestia QML 插件**：clone `caelestia-dots/shell` 并编译到
   `~/src/caelestia-shell/build/qml`（失败中断，不静默跳过）
5. 部署 `dot_*` 条目到 `$HOME`；有差异的已存在文件先备份到
   `~/.local/state/dotfiles-backup/` 再覆盖
6. 首次运行克隆 quickshell 底盘（pctrade/end4-pC）
7. 创建 python venv（pypinyin、dbus-python），供启动器拼音搜索使用

重复运行幂等。

> **Caelestia QML 插件**：`[4/7]` 步会 clone `caelestia-dots/shell` 并编译
> 到 `~/src/caelestia-shell/build/qml`，编译失败会中断安装并提示重试命令。
> 产物由 Hyprland `execs.lua` 与 fish `config.fish` 通过 `QML2_IMPORT_PATH`
> 自动加载，**不会** `cmake --install` 写入系统目录。只引入插件本体，
> 不含 Caelestia shell / CLI。

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
| Super+鼠标滚轮 | scrolling 布局切换窗口；其他布局切换相邻工作区 |
| Super+Shift+方向键 | 移动窗口 |
| Super+Shift+S、Print | 区域截图 |
| Super+Shift+R | 区域录屏 |
| Super+Shift+P / N / B | 播放暂停 / 下一首 / 上一首 |
| Super+F1 | 重启 fcitx5 |
| Ctrl+Super+T | 壁纸选择器 |

完整列表：`~/.config/hypr/hyprland/keybinds.lua` 与
`~/.config/hypr/custom/keybinds.lua`。

其中，`Super+鼠标滚轮` 会根据当前工作区的布局自动选择行为：使用
`scrolling` 布局时在当前工作区内切换窗口；使用 `dwindle` 等其他布局时切换
相邻工作区，每次滚轮只移动一个工作区。向下滚动表示下一个窗口 / 工作区，向上
滚动表示上一个窗口 / 工作区。

## 目录结构

~~~
dot_config/
  hypr/
    hyprland.lua          配置入口
    hyprland/             模板层（keybinds、general、rules、env、execs、scripts）
    custom/               个人覆盖层（同名文件覆盖模板）
    hyprlock.conf         回退锁屏配置
    hyprlock/             配色与辅助脚本
  quickshell/end4-pC/     shell 差异层（modules、services、scripts）
    modules/ii/lock/      锁屏：Lock.qml 入口 + SerpantinumLockSurface.qml 视图
  fish/  kitty/  foot/  alacritty/  nvim/  btop/  fastfetch/  fuzzel/  mako/  matugen/
  fcitx5/
    config                fcitx5 主配置
    conf/classicui.conf   Theme=Matugen（matugen 取色联动）
    conf/*.conf           其余 fcitx5 插件配置
dot_local/share/fcitx5/
  rime/
    default.custom.yaml   全局按键 / 翻页设置
    rime_ice.custom.yaml  雾凇拼音语法权重调整 + `/` 符号候选框
install.sh                安装 / 卸载 / 回档 / 存档 / TUI
docs/                     设计说明与排障文档（见下）
~~~

## 说明

- 更换壁纸会触发重新取色；模板位于 `dot_config/matugen/templates/`
  （Hyprland 窗口阴影颜色也由此生成，见 `templates/hyprland/colors.lua`）
- 桌面歌词偏移微调：
  `qs -c end4-pC ipc call desktoplyrics offset_faster / offset_slower`
- 备份根目录：`~/.local/state/dotfiles-backup/`（`snapshots/`、`state/`）
- 桌面小部件布局编辑（右键拖动）：见 [docs/widgets-layout.md](docs/widgets-layout.md)
- 排障：见 [docs/troubleshooting.md](docs/troubleshooting.md)

## 文档与更新日志

- [CHANGELOG.md](CHANGELOG.md) — 全部历史变更
- [docs/](docs/README.md) — 设计说明、实现笔记与排障
  - [appearance.md](docs/appearance.md) — 视频壁纸后端与视差
  - [lockscreen.md](docs/lockscreen.md) — 锁屏
  - [dynamic-island-roadmap.md](docs/dynamic-island-roadmap.md) — 灵动岛
  - [widgets-layout.md](docs/widgets-layout.md) — 桌面小部件布局
  - [integrations.md](docs/integrations.md) — SPlayer / fcitx5-rime 联动
  - [troubleshooting.md](docs/troubleshooting.md) — 排障索引

## 致谢与上游

本项目的 Quickshell 桌面外壳并非从零编写，而是基于以下上游项目构建，特此声明并致谢。

### 直接上游

- **[pctrade/end4-pC](https://github.com/pctrade/end4-pC)** by [@pctrade](https://github.com/pctrade)
  - 本仓库的 Quickshell 差异层（`dot_config/quickshell/end4-pC/`）基于此项目修改而来。
  - 安装脚本在首次运行时克隆该仓库作为 Quickshell 底盘，本仓库仅维护差异层，不重复分发上游代码。

### 上游的上游

- **[end-4/dots-hyprland](https://github.com/end-4/dots-hyprland)** by [@end-4](https://github.com/end-4)
  - `end4-pC` 是该项目中 illogical-impulse shell 的个人 fork。
  - illogical-impulse 是这套 Quickshell 桌面外壳的原始实现。

### 其他致谢

- 天气组件所用的天气 API 集成来自 [@gh0stzk](https://github.com/gh0stzk)
- 部分 shader 过渡效果来自 [@simeulinuxkaliaiwr](https://github.com/simeulinuxkaliaiwr)
- 壁纸选择器的斜切轮播视图 UI 灵感来自 [ilyamiro/serpantinum](https://github.com/ilyamiro/serpantinum)
  by [@ilyamiro](https://github.com/ilyamiro)，按本项目设计令牌重写，未引入其运行时依赖
- 锁屏的三栏布局交互与 Hyprland 窗口阴影参数参考
  [caelestia-dots/caelestia](https://github.com/caelestia-dots/caelestia)
  by [@caelestia-dots](https://github.com/caelestia-dots)，按本项目设计令牌重写，
  未引入其 C++ 插件与运行时依赖

## 许可证

本项目采用 [GPL-3.0](LICENSE) 许可证，与上游项目一致。作为衍生作品，本仓库保留了
上游的版权与致谢信息，并对个人修改部分负责。
