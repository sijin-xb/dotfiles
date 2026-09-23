# sijin-xb's dotfiles

个人桌面配置：Arch 系（开发环境 CachyOS）+ Wayland 合成器 + Quickshell。
合成器支持 **Hyprland**（默认）与 **niri**（滚动平铺），安装时二选一
（`COMPOSITOR=niri ./install.sh install`）。
源码树使用 chezmoi 风格命名（`dot_`、`executable_` 前缀），但安装由自带
bash 脚本完成，不需要 chezmoi 二进制。

> **English (brief)**: Personal desktop configuration for Arch-based systems
> with Hyprland (default) or niri, plus Quickshell. Clone the repo and run
> `./install.sh` (TUI) or `./install.sh install`; the same script provides
> `rollback`, `restore`, `archive` and `uninstall`. Full documentation below is
> in Chinese.

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

- **Hyprland** 配置（Lua）。`hyprland/` 为模板层，`custom/` 为个人覆盖层
  （同名文件在模板之后加载并覆盖模板）
- **niri** 配置（KDL）。`config.kdl` 为入口，按功能拆到 `binds` / `rule` /
  `layout` / `animations` / `blur` / `debug` 等文件；键位已从 Hyprland 迁移，
  桌面外壳由 DankMaterialShell（DMS）承担，DMS 自动生成的部分放在 `dms/`。
  间距 / 边框 / 焦点环 / 圆角由 `override-layout.kdl` 统一覆盖 DMS 的值
  ⚠️ 需要 SHORiN fork，见[环境要求](#环境要求)
- Quickshell（end4-pC fork）差异层：栏、侧边栏、启动器、总览、设置面板
- **岛屿 + 仪表盘**：栏中央一颗胶囊（时间 / 音乐 / 计时器 / 秒表 / 录屏 轮播），
  点击从 Bar 里生长成面板，再点缩回。五页（页签由 Caelestia 的 `Content` 提供）：
  - **仪表盘**：头像 / 主机 · 天气小卡 · 日期时间 · 月历 · 系统资源 · 媒体卡
  - **媒体**：封面 + 曲目 + 进度 + 控制 + 歌词（含翻译 / 音译副标题），
    与桌面歌词浮层**同源**
  - **Performance**：CPU / GPU / 内存 / 磁盘 / 网络 / 电池
  - **进程**：进程列表，支持搜索、按 CPU / 内存 / GPU / 名称排序、kill
    （左键 TERM / 右键 KILL），可点行改键
  - **天气**：当前天气 + 逐时 + 多日

  可在 设置 → 栏 的组件列表里增删（组件名 `Island`），删掉即整座岛隐藏。
  详见 [docs/bar-and-dashboard.md](docs/bar-and-dashboard.md)
- **快捷键管理器**：`Super + /` 弹出速查表，列出配置里真实存在的快捷键，
  可搜索、**可点行改键**（按下后先预览，按 Enter 才写入）。详见
  [docs/keybind-manager.md](docs/keybind-manager.md)
- GitHub 项目页：填用户名列出该用户仓库（名称 / 描述 / 语言 / Star / 更新时间），
  点击跳转。入口：设置 → GitHub。详见 [docs/github-page.md](docs/github-page.md)
- 锁屏：Caelestia 风格三栏布局（居中圆角方块 → 点击展开成横条，Material 3
  形状 morph 动画），按屏幕高度自适应并支持密码框自动 / 唤醒重聚焦；quickshell
  未运行时回退 hyprlock。依赖 `qt6-m3shapes-git`（AUR）与 Caelestia QML 插件。
  详见 [docs/lockscreen.md](docs/lockscreen.md)
- 桌面歌词：逐字计时（酷狗 KRC），适配任意 MPRIS 播放器；SPlayer 可走
  WebSocket 直推。详见 [docs/integrations.md](docs/integrations.md)
- 灵动岛：音乐 / 音量 / 录屏活动的顶部动态胶囊，详见
  [docs/dynamic-island.md](docs/dynamic-island.md)
- 壁纸视差与多后端视频壁纸，详见 [docs/appearance.md](docs/appearance.md)
- matugen 壁纸取色：kitty / alacritty / foot / fastfetch / fcitx5（含 fcitx5-rime
  候选框）/ mako / Hyprland 与 niri 联动配色（niri 侧含录屏选区界面的
  `screen-cast-picker`）
- fish（fzf 绑定、nvm）、btop、fastfetch、fuzzel、mako 配置
- **nvim（LazyVim，取向是「边用边学 vim」）**：保留不是 vim 动词的 Ctrl 系快捷键
  （`Ctrl+S` 存盘、`Ctrl+P` 找文件、`Ctrl+B` 文件树、``Ctrl+` `` 终端、`Ctrl+/` 注释），
  把 vim 动词（`yy` / `p` / `u` / `ggVG`）还给 vim 本身；picker / 文件树用
  Telescope + Neo-tree，中文输入法自动中英切换，光标形状随模式变色；
  GUI 前端 neovide，字体对齐 kitty。
  详见 [docs/nvim-keymaps.md](docs/nvim-keymaps.md)（速查表）与
  [docs/nvim-learning.md](docs/nvim-learning.md)（学习清单）

## 环境要求

- Arch 系发行版（存在 `/etc/arch-release`）
- Wayland 会话，合成器二选一（安装时选，或 `COMPOSITOR=` 预设）：
  - **Hyprland**（默认）
  - **niri**：必须是 [SHORiN-KiWATA/niri](https://github.com/SHORiN-KiWATA/niri)
    fork（AUR `niri-shorin-fork-git`）。本仓库的 niri 配置用到该 fork 独有的
    `magnifier` / `grid-overview` / `cursor shake-to-enlarge` / 内置
    screencast portal，换成上游 niri 会因未知配置项**拒绝加载配置**
    - ⚠️ `install.sh` 的 niri 路径目前装的仍是上游 `niri` 包，需要手动换成
      fork。详见 [CHANGELOG.md](CHANGELOG.md) 的「遗留」。
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

1. pacman 基础依赖（kitty、fish、fuzzel、fcitx5、cliphist、xdg portals、
   qt6 工具链，以及 Caelestia QML 插件编译所需的 aubio / libpipewire /
   libqalculate / lm_sensors / fftw / spirv-tools），另加合成器相关的包
   —— Hyprland：`hyprland hypridle hyprlock xdg-desktop-portal-hyprland`；
   niri：`niri xdg-desktop-portal-gnome`（其中 niri 需为 fork 包，
   见[环境要求](#环境要求)）。**默认只装缺失项，不滚动系统**；需要全量升级时用
   `FULL_UPGRADE=1 ./install.sh install`
2. AUR 包（matugen、mpvpaper、libcava、qt6-m3shapes-git）；无 AUR helper 时自动安装 yay
3. quickshell 三级回退：已有二进制 → pacman → AUR → 源码编译
4. **Caelestia QML 插件**：clone `caelestia-dots/shell` 并编译到
   `~/src/caelestia-build/qml`（失败中断，不静默跳过）
5. 部署 `dot_*` 条目到 `$HOME`；有差异的已存在文件先备份到
   `~/.local/state/dotfiles-backup/` 再覆盖
6. 首次运行克隆 quickshell 底盘（pctrade/end4-pC）
7. 创建 python venv（pypinyin、dbus-python），供启动器拼音搜索使用

重复运行幂等。

> **Caelestia QML 插件**：`[4/7]` 步会 clone `caelestia-dots/shell` 并编译
> 到 `~/src/caelestia-build/qml`，编译失败会中断安装并提示重试命令。编译前先应用
> `dot_config/quickshell/caelestia/` 覆盖层（含简体中文 `trs/zh_CN.po`），覆盖层
> 有变化时自动重编（`.overlay-stamp` 记 hash）。产物由 Hyprland `execs.lua` 与 fish
> `config.fish` 通过 `QML2_IMPORT_PATH` 自动加载，**不会** `cmake --install` 写入
> 系统目录。只引入插件本体，不含 Caelestia shell / CLI。

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
| Super+/ | 快捷键管理器（速查表；点行可改键，Enter 确认） |
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

完整列表：Hyprland 见 `~/.config/hypr/hyprland/keybinds.lua` 与
`~/.config/hypr/custom/keybinds.lua`；niri 见 `~/.config/niri/binds.kdl`，
DMS 相关的功能键位见 `~/.config/niri/dms/binds.kdl`。niri 那套是照着
Hyprland 的键位迁移过来的（同一功能、同一键位），所以上表在两个合成器下
基本通用；迁移中的差异与取舍写在
`dot_config/niri/binds-hyprland-migrated.kdl` 的注释里。

其中，`Super+鼠标滚轮` 会根据当前工作区的布局自动选择行为：使用
`scrolling` 布局时在当前工作区内切换窗口；使用 `dwindle` 等其他布局时切换
相邻工作区，每次滚轮只移动一个工作区。向下滚动表示下一个窗口 / 工作区，向上
滚动表示上一个窗口 / 工作区。（niri 是纯滚动平铺，所以恒为「切换窗口」。）

## 目录结构

~~~
dot_config/
  hypr/                   Hyprland（默认合成器）
    hyprland.lua          配置入口
    hyprland/             模板层（keybinds、general、rules、env、execs、scripts）
    custom/               个人覆盖层（同名文件覆盖模板）
    hyprlock.conf         回退锁屏配置
    hyprlock/             配色与辅助脚本
  niri/                   niri（可选合成器，需 SHORiN fork）
    config.kdl            配置入口（include 下面这些）
    binds.kdl             键位（自 Hyprland 迁移）
    binds-hyprland-migrated.kdl   迁移对照与差异说明
    rule.kdl              窗口 / 图层规则
    layout.kdl  animations.kdl  blur.kdl  output.kdl  debug.kdl
    override-layout.kdl   间距 / 边框 / 焦点环 / 圆角，覆盖 DMS 自动生成的值
    dms/binds.kdl         手写的 DMS 功能键位（dms/ 下其余文件由 DMS 生成，未纳管）
    scripts/              截图音效、fuzzel 切换器、电源菜单等辅助脚本
  xdg-desktop-portal/niri-portals.conf
                        niri 的 portal 路由：录屏 / 截图走 niri 本体，
                        密钥环走 gnome-keyring
  DankMaterialShell/plugins/   DMS 插件（cavaVisualizer、mpvpaper 视频壁纸）
  quickshell/end4-pC/     shell 差异层（modules、services、scripts）
    custom-island/        岛屿 + 仪表盘（独立于 modules/，见 docs/bar-and-dashboard.md）
    modules/ii/bar/Island.qml    栏里那段等宽透明占位（岛真身是 custom-island/IslandHost.qml）
    modules/ii/lock/      锁屏：Lock.qml 入口
      caelestia/          Caelestia 风格锁屏（内容、组件、形变动画）
      SerpantinumLockSurface.qml  旧版锁屏（保留可切回）
  fish/  kitty/  foot/  alacritty/  nvim/  neovide/  btop/  fastfetch/  fuzzel/  mako/  matugen/
  environment.d/cursor.conf  gtk-3.0/  gtk-4.0/  xsettingsd/
                        光标主题 / 尺寸：唯一来源是 DMS 的 cursorSettings，
                        其余几处只是跟着它保持一致（详见 CHANGELOG 2026-09-23）
  fontconfig/fonts.conf  无衬线 / 等宽方案（MiSans + 按语言切换 CJK 地区字形）
  fontconfig/conf.d/50-lxgw-wenkai.conf  衬线族（serif）：霞鹜文楷 + 楷体别名映射
  fcitx5/
    config                fcitx5 主配置
    conf/classicui.conf   Theme=Matugen（matugen 取色联动）
    conf/*.conf           其余 fcitx5 插件配置
dot_local/share/fcitx5/
  rime/
    default.custom.yaml   全局按键 / 翻页设置
    rime_ice.custom.yaml  雾凇拼音语法权重调整 + `/` 符号候选框
dot_vimrc                 vim（非 nvim）配置：fcitx5 自动切换 + 剪贴板降级
install.sh                安装 / 卸载 / 回档 / 存档 / TUI
docs/                     设计说明与排障文档（见下）
~~~

## 说明

- 更换壁纸会触发重新取色；模板位于 `dot_config/matugen/templates/`
  （Hyprland 窗口阴影颜色见 `templates/hyprland/colors.lua`；niri 的边框 /
  焦点环配色与录屏选区界面见 `templates/niri-colors.kdl`，输出到
  `~/.config/niri/matugen-colors.kdl`）
- 桌面歌词偏移微调：
  `qs -c end4-pC ipc call desktoplyrics offset_faster / offset_slower`
- 备份根目录：`~/.local/state/dotfiles-backup/`（`snapshots/`、`state/`）
- 桌面小部件布局编辑（右键拖动）：见 [docs/widgets-layout.md](docs/widgets-layout.md)
- 排障：见 [docs/troubleshooting.md](docs/troubleshooting.md)

## 文档与更新日志

- [CHANGELOG.md](CHANGELOG.md) — 全部历史变更
- [docs/README.md](docs/README.md) — **文档索引**（完整清单，本目录全部设计说明与排障文档）

常用几篇：

- [bar-and-dashboard.md](docs/bar-and-dashboard.md) — 岛屿 + 仪表盘、栏组件、统一歌词源、液态玻璃、悬停动效范围
- [compositor-effects.md](docs/compositor-effects.md) — 合成器层模糊与窗口透明度（niri ↔ Hyprland 参数对照与移植）
- [nvim-keymaps.md](docs/nvim-keymaps.md) — Neovim 快捷键速查表
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
- 锁屏的三栏布局与展开动画移植自
  [caelestia-dots/caelestia](https://github.com/caelestia-dots/caelestia)
  by [@caelestia-dots](https://github.com/caelestia-dots)（GPL-3.0），
  按本项目设计令牌（`Appearance`）重写配色与字体；形变动画依赖其生态的
  [soramanew/m3shapes](https://github.com/soramanew/m3shapes)（AUR 包
  `qt6-m3shapes-git`），配置层依赖 Caelestia QML 插件（`Caelestia.Config`
  的 `Tokens.anim.*`，由安装脚本 `[4/7]` 步编译）。认证、媒体、歌词等
  运行时逻辑仍走 end4-pC 自身服务，未引入 Caelestia shell / CLI。

## 许可证

本项目采用 [GPL-3.0](LICENSE) 许可证，与上游项目一致。作为衍生作品，本仓库保留了
上游的版权与致谢信息，并对个人修改部分负责。
