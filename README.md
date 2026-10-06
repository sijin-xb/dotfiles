# sijin-xb's dotfiles

Arch 系 + Wayland 的整套桌面配置。**会话三选一整体部署**，装哪套就只碰哪套，
不会去动机器上另一套的配置。

配置由自带的 bash 安装器落地，不依赖 chezmoi —— 源码树用 chezmoi 风格命名
（`dot_` 前缀目录 → `$HOME` 下的隐藏目录，`executable_` 前缀 → 剥前缀 + 恢复执行位），
但部署、快照、回档都是 `install.sh` 自己的活。

桌面外壳不是从零写的：Quickshell 部分基于 [pctrade/end4-PC](https://github.com/pctrade/end4-pC)
（上游的上游是 [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland)），
本仓库维护差异层，首次安装时克隆上游底盘。详见[致谢](#致谢与上游)。

## 快速开始

~~~bash
git clone https://github.com/sijin-xb/dotfiles.git
cd dotfiles
./install.sh              # TUI 二级菜单，第一次推荐走这里
./install.sh install      # 或直接跑完整安装（7 步，开始前自动快照）
~~~

只捞一个文件也能跑（自举；它会 clone 仓库到 `~/.local/share/dotfiles-src`
再用仓库里那份重新执行自己）：

~~~bash
curl -fsSL https://raw.githubusercontent.com/sijin-xb/dotfiles/main/install.sh \
    | bash -s -- update
~~~

**日常升级别重跑 `install`** —— 它会重装包、重拉上游底盘、冲掉本地对底盘的改动：

~~~bash
cd dotfiles && git pull
./install.sh update                    # 只做文件层增量同步
./install.sh update --with-packages    # 顺便补齐新增的依赖（只补不卸）
~~~

## 命令

| 命令 | 作用 |
|---|---|
| `install` | 完整安装（7 步），开始前创建 pre-install 快照 |
| `update` | 增量升级：只同步文件层，`--dry-run` / `--pull` / `--with-packages` / `--no-prune` / `--force` / `--yes` |
| `rollback` | 还原到 pre-install 快照（执行前先存 pre-rollback 快照） |
| `restore` | 撤销回档：重新应用 pre-rollback 快照 |
| `archive` | 打包配置 / 状态 / 缓存为 tar.gz（`-o PATH`、`--delete`） |
| `uninstall` | 可选先存档，再删除受管理路径 |
| `status` | 部署状态：会话 / 清单条目 / 上次 revision / 快照 / 占用（只读） |
| `doctor` | 环境体检：缺哪些包、配置在不在、QML 模块齐不齐（只读） |
| `deps` | 依赖清单，`--missing` 只看缺口（只读） |
| `theme` | 图标 / 光标 / GTK 主题在 9 个 sink 里的取值与一致性（只读） |
| `clean` | 清理临时残留；`--all` 连自举缓存、旧快照、旧备份一起清 |
| 无参数 / `--tui` | TUI 二级菜单 |

完整选项、环境变量与目录说明：`./install.sh --help`。
删除类操作（uninstall / archive --delete）只作用于当前会话的路径，
另一套会话的既有配置不动。

## 会话三选一

| `SESSION=` | 合成器 | 桌面外壳 | 配置入口 |
|---|---|---|---|
| `end4pc`（默认） | Hyprland | Quickshell（end4-PC 底盘） | `~/.config/hypr/hyprland.lua`、`~/.config/quickshell/end4-PC` |
| `caelestia` | Hyprland | caelestia shell | `~/.config/quickshell/caelestia` |
| `dms` | niri | DankMaterialShell | `~/.config/niri/config.kdl` |

- 不设 `SESSION` 时在 `[1/7]` 步交互询问；设了就跳过提问，适合脚本化重装。
- `end4pc` 与 `caelestia` 都会编译 **Caelestia QML 插件**到 `~/src/caelestia-build`
  （end4-PC 的锁屏硬依赖 `import Caelestia.Config`），`dms` 不需要。
- 两套合成器都要用：`INSTALL_BOTH_COMPOSITORS=1`。

## 环境要求

- **Arch 系**（存在 `/etc/arch-release`）· **Wayland 会话** · 普通用户运行（需要 sudo 装包，
  脚本会拒绝 root）
- 合成器随会话而定：Hyprland（`end4pc` / `caelestia`）或 niri（`dms`）
- **niri 必须是 [SHORiN-KiWATA/niri](https://github.com/SHORiN-KiWATA/niri) fork**
  （AUR `niri-shorin-fork-git`）。配置用到该 fork 独有的 `magnifier`、`grid-overview`、
  cursor shake-to-enlarge、`screen-cast-picker` 配色，以及单 `Mod` 键绑定；换成上游 niri
  或 `niri-spicy-git` 会因未知配置项**拒绝加载整份配置**。它是 `provides`/`conflicts niri`
  的包，换装前先 `sudo pacman -Rdd <旧包>`，换完 `niri validate`。
- quickshell / matugen / mpvpaper 缺失时由脚本自动安装（pacman → AUR → 源码编译）

字体是**可选**的：`FONTS=0` 一个字体包都不碰（也不移除文泉驿兜底），不设置则交互询问。
其余环境变量见 `./install.sh --help`。

## 包含什么

### 合成器

- **Hyprland**（Lua 配置）：`hyprland/` 是模板层，`custom/` 是个人覆盖层，同名文件后加载
- **niri**（KDL）：`config.kdl` 入口，按功能拆文件；键位自 Hyprland 迁移，差异写在
  `binds-hyprland-migrated.kdl`；间距 / 边框 / 焦点环由 `override-layout.kdl` 覆盖 DMS 生成值

### 桌面外壳（Quickshell，end4-PC 差异层）

- **岛屿 + 仪表盘**：栏中央一颗胶囊（时间 / 音乐 / 计时器 / 秒表 / 录屏轮播），点击生长成
  面板，五页（仪表盘 / 媒体 / Performance / 进程 / 天气）→ [bar-and-dashboard.md](docs/bar-and-dashboard.md)
- **灵动岛**：音乐 / 音量 / 录屏的顶部动态胶囊 → [dynamic-island.md](docs/dynamic-island.md)
- **锁屏**：Caelestia 风格三栏布局 + Material 3 形变动画，quickshell 未运行时回退 hyprlock
  → [lockscreen.md](docs/lockscreen.md)
- **快捷键管理器**：`Super + /` 速查表，可搜索、可点行改键（Enter 才写入）
  → [keybind-manager.md](docs/keybind-manager.md)
- **桌面歌词**：逐字计时（酷狗 KRC），适配任意 MPRIS 播放器 → [integrations.md](docs/integrations.md)
- **GitHub 项目页**：填用户名列出仓库，入口在设置里 → [github-page.md](docs/github-page.md)

### 外观与取色

- **matugen 壁纸取色**：kitty / alacritty / foot / fastfetch / fcitx5（含 rime 候选框）/
  mako / Hyprland 与 niri 联动配色，以及 Kvantum + Qt 应用（end4-PC 专属）；
  另有 micro / Kate / nvim 三个编辑器的原生配色主题
- **图标主题**：WhiteSur 打底，文件夹由 matugen 按壁纸次色系重着色（`WhiteSur-Matugen-{A,B}`
  覆盖主题，`Inherits=WhiteSur-dark`），A/B 交替绕开 GTK/Qt 的图标缓存；
  散在 gsettings / GTK2+3+4 / Qt5+6 / fuzzel / xsettingsd / rofi 的 9 处取值由
  `./install.sh theme` 一条命令核对一致性
- **壁纸**：视差 + 多后端视频壁纸 → [appearance.md](docs/appearance.md)
- **区域截图 / 录屏**：整屏压暗、把选区或指到的窗口挖空高亮，点一下即截该窗口

### 编辑器与终端

- **nvim（LazyVim）**：保留 Ctrl 系快捷键（存盘 / 找文件 / 文件树 / 终端 / 注释），vim 动词
  还给 vim；Telescope + Neo-tree，中文输入法自动切换，GUI 前端 neovide
  → [速查表](docs/nvim-keymaps.md) · [学习清单](docs/nvim-learning.md)
- fish（fzf 绑定、nvm）、kitty、foot、btop、fastfetch、fuzzel、mako、mpd

## 快捷键

| 按键 | 功能 |
|---|---|
| `Super` | 启动器（拼音搜索） |
| `Super+T` | 终端召唤（quake 风格 kitty） |
| `Super+/` | 快捷键管理器 |
| `Super+Q` | 关闭窗口 |
| `Super+S` | 临时工作区 scratchpad |
| `Super+L` | 锁屏 |
| `Super+1..0` | 切换工作区 |
| `Super+方向键` | 切换焦点 |
| `Super+Shift+方向键` | 移动窗口 |
| `Super+滚轮` | 切窗口 / 切工作区（看当前布局） |
| `Super+Shift+S`、`Print` | 区域截图 |
| `Super+Shift+R` | 区域录屏 |
| `Super+Shift+P/N/B` | 播放暂停 / 下一首 / 上一首 |
| `Ctrl+Super+T` | 壁纸选择器 |

完整列表在配置里：Hyprland 见 `hyprland/keybinds.lua` + `custom/keybinds.lua`，
niri 见 `binds.kdl` + `dms/binds.kdl`。两套键位是照着迁移的（同功能同键位），
所以上表基本通用。

## 目录结构

~~~
install.sh                 安装器引导（逻辑按职责在 lib/ 下分 20 个模块）
lib/                       安装器模块：部署、快照、包管理、TUI、各子命令
dot_config/                部署到 ~/.config（下列为其中的关键路径）
  hypr/                    Hyprland：hyprland.lua 入口 + hyprland/ 模板层 + custom/ 覆盖层
  niri/                    niri：config.kdl 入口 + binds/rule/layout/animations 等分片
  quickshell/end4-PC/      shell 差异层：custom-island/（岛屿）、modules/ii/（栏 · 锁屏 · 岛）
  DankMaterialShell/       DMS 插件（视频壁纸、cava 可视化）
  matugen/                 取色引擎：config.toml + templates/（各程序的配色模板与素材）
  fish/ kitty/ foot/ nvim/ neovide/ btop/ fastfetch/ fuzzel/ mako/ micro/ mpd/
  gtk-3.0/ gtk-4.0/ qt5ct/ qt6ct/ xsettingsd/
                           GTK / Qt / XSettings 的静态配置（主题名、字体、装饰）
  fontconfig/              MiSans + 按语言切换 CJK 地区字形；serif 走霞鹜文楷
  fcitx5/                  fcitx5 与 rime 配置
dot_local/share/fcitx5/     rime 方案自定义（雾凇拼音）
dot_icons/ dot_local/share/icons/default/
                           光标主题的兜底 Inherits
docs/                      设计说明与排障文档（见下）
tests/                     install.sh 的行为测试（6 个脚本）
check-qml-deps.py          QML 模块依赖自检，install 与 update 收尾各跑一次
~~~

## 文档

- **[docs/README.md](docs/README.md)** — 文档索引（18 篇，按主题分类）
- [CHANGELOG.md](CHANGELOG.md) — 全部历史变更

常翻的几篇：[troubleshooting.md](docs/troubleshooting.md)（排障索引）、
[bar-and-dashboard.md](docs/bar-and-dashboard.md)、
[compositor-effects.md](docs/compositor-effects.md)（niri ↔ Hyprland 参数对照）、
[nvim-keymaps.md](docs/nvim-keymaps.md)。

## 测试

改 `install.sh` 或 `lib/` 之后跑这些（都不需要 sudo / 网络 / 真实包管理器）：

| 脚本 | 覆盖 |
|---|---|
| `tests/install-sh-behaviour-test.sh` | 纯函数级：chezmoi 前缀、完整性自检、删除范围、忽略清单匹配、依赖矩阵 |
| `tests/install-sh-dryrun.sh` | 端到端：假命令 + 临时 `$HOME`，真实跑 `cmd_install` 三轮（安装 / 迁移 / 幂等） |
| `tests/install-sh-cli-test.sh` | CLI 一致性：子命令帮助、多余参数告警、未知选项退出码 |
| `tests/install-sh-prompt-test.sh` | `confirm` / `read_answer` 在 EOF、沉默管道、pty 下都不挂死 |
| `tests/install-sh-tmpfiles-test.sh` | 临时文件：统一 run 目录、EXIT trap、SIGINT 不留垃圾 |
| `tests/install-sh-archive-test.sh` | `archive` 打包内容、拒绝存档的返回码语义 |

失败时会打印「实际 vs 期望」并以非 0 退出；
`DRYRUN_ROOT=/tmp/xxx bash tests/install-sh-dryrun.sh` 可保留现场排查。

改 matugen 的终端配色模板（kitty / alacritty / foot / konsole）之后，跑
`python3 tools/term-color-audit.py`：它把四个终端的 16 个 ANSI 槽位拉齐算
WCAG 对比度，标出「暗背景上其实看不清」的槽位，以及 bright 反而比 normal
暗的错位 —— 这类问题肉眼很难发现（旧模板里 color0 的对比度 10.9 与 white
的 14.3 几乎平齐，"黑"根本不黑，看着却像正常配色）。

## 排障

- 备份与快照都在 `~/.local/state/dotfiles-backup/`（`snapshots/`、`state/`），
  出问题先 `./install.sh rollback`
- 装完某个组件没出现（栏少了东西、锁屏起不来）：多半是 QML 模块缺失 —— 跑
  `./install.sh doctor`，它会指出缺哪个包
- 主题不一致（文件管理器换了、fuzzel 没换）：`./install.sh theme` 列出 9 处取值
- 其余见 [docs/troubleshooting.md](docs/troubleshooting.md)

## 致谢与上游

**直接上游** — [pctrade/end4-pC](https://github.com/pctrade/end4-pC) by [@pctrade](https://github.com/pctrade)：
`dot_config/quickshell/end4-PC/` 基于此项目修改；安装时克隆它作为底盘，本仓库只维护差异层。

**上游的上游** — [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) by [@end-4](https://github.com/end-4)：
`end4-pC` 是该项目的 illogical-impulse shell 的个人 fork，也是这套 Quickshell 外壳的原始实现。

**其他** — 天气 API 集成来自 [@gh0stzk](https://github.com/gh0stzk)；部分 shader 过渡来自
[@simeulinuxkaliaiwr](https://github.com/simeulinuxkaliaiwr)；壁纸选择器的斜切轮播视图灵感来自
[ilyamiro/serpantinum](https://github.com/ilyamiro/serpantinum)；锁屏的三栏布局与展开动画移植自
[caelestia-dots/caelestia](https://github.com/caelestia-dots/caelestia)（GPL-3.0），按本项目设计
令牌重写配色与字体，形变动画依赖 [soramanew/m3shapes](https://github.com/soramanew/m3shapes)
（AUR `qt6-m3shapes-git`）。认证、媒体、歌词等运行时逻辑仍走 end4-PC 自身服务，
未引入 Caelestia shell / CLI。

## 许可证

[GPL-3.0](LICENSE)，与上游一致。作为衍生作品，本仓库保留上游的版权与致谢信息，
并对个人修改部分负责。
