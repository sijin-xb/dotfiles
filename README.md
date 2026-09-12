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
- [桌面小部件布局编辑（新手友好）](#桌面小部件布局编辑新手友好)
- [视频壁纸后端](#视频壁纸后端)
- [脚本命令](#脚本命令)
- [快捷键（节选）](#快捷键节选)
- [目录结构](#目录结构)
- [锁屏](#锁屏)
- [灵动岛](#灵动岛)
- [说明](#说明)
- [致谢与上游](#致谢与上游)
- [许可证](#许可证)

其他文档：

- [更新日志](CHANGELOG.md) — 全部历史变更
- [docs/](docs/README.md) — 设计说明与路线图

## 包含内容

- Hyprland 配置（Lua）。`hyprland/` 为模板层，`custom/` 为个人覆盖层
  （同名文件在模板之后加载并覆盖模板）
- Quickshell（end4-pC fork）差异层：栏、侧边栏、启动器、总览、设置面板
- 锁屏：Serpantinum 风格三栏布局（居中大时钟 → 点击展开系统监控 / 认证 /
  通知+媒体 三栏翼面板）；quickshell 未运行时回退 hyprlock
- 桌面歌词：逐字计时（酷狗 KRC），适配任意 MPRIS 播放器
- 灵动岛：音乐 / 音量 / 录屏活动的顶部动态胶囊，详见下文「灵动岛」章节
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

## 桌面小部件布局编辑（新手友好）

不需要手动修改 JSON 就能调整桌面小部件的位置：

1. 在桌面空白处**右键**，选择「编辑桌面布局」。
2. 直接拖动任意已启用的小部件；网格和中心线会帮助对齐。
3. 调整完成后再次右键桌面，选择「锁定桌面布局」。

位置会自动写入 `~/.config/illogical-impulse/config.json`，重启 Quickshell 后仍会保留。编辑模式会临时允许所有桌面小部件移动，包括原本使用“自动寻找壁纸空白区域”的小部件；拖动后会记住你选择的位置。音频可视化是全宽部件，横向位置固定，解锁后上下拖动即可调整高度。

开发者如果需要手动调整，可直接修改 `background.widgets.<widget>.x/y`；但建议先使用界面完成布局，再把配置纳入版本控制。

## 视频壁纸后端

视频壁纸可以在「设置 → 背景 → 视频壁纸后端」中选择：

| 后端 | 适合场景 |
|---|---|
| **Mpvpaper** | 推荐，稳定可靠，逐显示器启动 |
| **Phonto** | 适合测试 GPU 视频播放和低占用表现 |
| **Wallr** | 功能更完整，但存在视频随机冻结的已知问题，见下 |

Mpvpaper 是默认后端。Wallr 和 Phonto 都是可选依赖；没有安装时，脚本会自动回退到 Mpvpaper，不会影响已有视频壁纸。

### Wallr 已知问题：视频随机冻结

Wallr 的壁纸会**突然定格不动**——视频解码线程可能仍在运行，但渲染循环停止更新，画面停在最后一帧。常见触发场景包括：

- 显示器 DPMS 休眠后唤醒
- 全屏不透明窗口完全遮挡背景层
- 显示器热插拔或分辨率 / 缩放变更

临时恢复方法是重启 daemon（`pkill wallr` 后重新 `wallr daemon`）。

由于该问题尚未在上游修复，默认后端保持为 Mpvpaper。如果仍想试用 Wallr，可在设置中手动切换，并留意上述场景。

开发者可直接编辑：

```json
{
  "background": {
    "videoBackend": "mpvpaper"
  }
}
```

可选值为 `mpvpaper`、`phonto`、`wallr`。切换后重新选择一次视频壁纸即可生效。脚本会先停止其他视频壁纸进程，确保不会同时运行多个后端。

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
    modules/ii/lock/      锁屏：Lock.qml 入口 + SerpantinumLockSurface.qml 视图
  fish/  kitty/  foot/  alacritty/  nvim/  btop/  fastfetch/  fuzzel/  mako/  matugen/
install.sh                安装 / 卸载 / 回档 / 存档 / TUI
```

## 锁屏

`Super+L` 触发 `quickshell:lock`。锁屏采用 Serpantinum 风格三栏布局：初始
只有居中大时钟（时:分、日期、分时段问候），点击任意处或按任意键展开，大
时钟缩小上移，三栏翼面板从下方浮现。

| 栏位 | 内容 |
|---|---|
| 左翼 | 系统监控四宫格：CPU / 内存 / 温度 / 磁盘，环形进度 + 居中数值 |
| 中翼 | 头像、用户名与状态、密码框、键盘布局与电池胶囊、电源按钮（休眠 / 重启 / 关机） |
| 右翼 | 歌词卡（当前行前后共 7 行）、通知列表、媒体卡（封面、曲名、进度、播放控制） |

`Esc` 收起并清空密码。头像加载链与桌面 `UserCardWidget` 一致：
`Config.options.profile.avatarPath` 优先，否则读 `~/.face`，失败回退 person
图标。歌词直接复用 `LyricsService`，与桌面歌词同一数据源。

认证复用 `LockContext`（PAM + 指纹 + keyring），配色、圆角、字体、动画
曲线全部取自 `Appearance`。背景是模糊后的桌面壁纸（与桌面同一源链，含
`lockWall` 覆盖与视频缩略图分支）。hypridle 超时锁屏走同一入口；
quickshell 未运行时使用 hyprlock。

## 灵动岛

顶部居中的动态胶囊，按「当前活动」切换形态，同一时刻只显示优先级最高的
活动。数据源通过 `ActivityManager.set(type, payload, priority, options)` 注册，
UI 订阅 `currentType` / `currentPayload`。

| 活动 | 优先级 | 触发条件 | 主岛内容 |
|---|---|---|---|
| `volume` | 30 | 音量 / 静音变化（2 秒后自动消失） | 音量条 |
| `brightness` | 28 | 亮度变化（1.5 秒后自动消失） | 亮度条 |
| `music` | 10 | 任意 MPRIS 播放器有曲目 | 封面、频谱、标题 |
| `package` | 8 | 检测到 pacman / yay / paru / makepkg，或脚本主动上报 | 图标、进度条、百分比 |
| `download` | 7 | 检测到 curl / wget / aria2c，或脚本主动上报 | 图标、进度条、百分比 |
| `notification` | 6 | 收到桌面通知（4 秒后自动消失） | 铃铛、通知摘要 |
| `recording` | 5 | `states.json` 中 `record.enable` 为 true | 脉冲红点、计时 |
| `privacy` | 4 | 麦克风 / 摄像头被占用 | 警示圆点、设备图标 |

### 联动内核

灵动岛的活动之间不是孤立的，三个单例负责「联动」：

- **`ActivityManager`** — 活动注册表。除 `set` / `clear` 外提供：
  - `pulse(type, payload, priority, duration)`：统一暂态生命周期，数据源不再各自持有 Timer
  - `hold(type)` / `release(type, duration)`：展开态暂停 / 恢复过期
  - `group` 选项：同组任务在副岛合并渲染
  - 推导属性 `scene`（`recording` / `media` / `task` / `idle`）
- **`IslandContext`** — 场景门控。`suppressTransient` 为真时，音量 / 亮度 / 通知等
  瞬态活动不注册。两个来源：
  - 自动：录屏场景下静默瞬态，避免污染演示画面
  - 手动：设置 → 背景 → 「静默灵动岛提示」，或 IPC `island silent_toggle`
- **`IslandPalette`** — 取色中枢。媒体封面主色提升为全局状态，频谱条、亮度条、
  歌词高亮都读同一份颜色；封面偏暗时自动提亮到可读亮度。

副岛不再硬编码活动类型：任何声明了 `group` 的活动，只要没占着主岛就挂到右侧。
新增任务类型只需在 `TaskSource` 子类里写一行 `group`。

### 视觉与性能

- **主色全链路**：进度条渐变的起止色统一取自 `IslandPalette`，不再有硬编码的蓝紫。
  无封面主色时回退到原默认渐变，观感不变。
- **切换形变**：活动切换不再只是淡入，叠加 0.96 → 1 的缩放，让内容像从岛里长出来。
- **副岛过渡**：左右副岛的进出改为弹簧动画；显隐跟随宽度，退场可见而非瞬断。
- **分页指示点**：当前页拉长成胶囊，比单纯换色更易辨识。
- **进程探测合并**：`ProcessProbe` 用单次 `ps -eo comm=` 覆盖所有任务类型，
  替代原先每个 `TaskSource` 各自轮询；无订阅者时自动停表。
- **错误边界**：`cava` 异常退出后不再被无限重启；`ps` 空快照时保留上次结果。

### 音乐

- **收起**：圆形封面 + 6 段实时频谱（cava）+ 歌名，宽度随内容自适应（200–340px）
- **展开**：两页，左右滑动或点击底部指示点切换
  - 控制页：封面、歌名 / 艺术家、可拖拽进度条、上一首 / 播放暂停 / 下一首
  - 歌词页：当前行前后共 5 行，当前行逐字高亮，附翻译行

### 歌词逐字高亮

歌词取自酷狗 KRC，逐字格式为 `[start,duration]<offset,duration,0>字`。字的偏移量
**相对行首**（首个字为 0），解析后累加行起始时间得到每个字的绝对时间。

渲染采用**卡拉OK式字内填充**：每个字由暗色底层 + 亮色上层组成，上层按
`(当前时间 - 字起始) / 字时长` 的进度从左往右裁剪，所以高亮是"抹过去"而不是
在字边界上硬切。进度越过 1 后即整字点亮。

**点击任意歌词行可直接跳到该句**，当前行也可点击重播本行。命中检测放在灵动岛
的 `pillMouse` 里（把坐标映射进活动组件），而不是每行挂 `MouseArea`——后者既会
破坏 `Column` 布局，也会吞掉左右滑动翻页的手势。

中英对照来自 KRC 的 `[language:]` 块（Base64 内嵌 JSON）：取第一个非罗马音
语义块作为翻译，按行号对齐；日语歌曲的罗马音转写块会被自动跳过。

### 封面取色

`ArtColorSource` 会把当前封面量化成一个主色（必要时先下载并按 URL 哈希缓存），
歌词的卡拉OK高亮在有封面时用这个颜色，没有封面时退回纯白。切歌时颜色带 600ms
过渡，不会硬跳。

### 手势

| 位置 | 手势 | 作用 |
|---|---|---|
| 任意态 | 滚轮 | 调音量（上滚增大、下滚减小，每格 5%） |
| 展开态 | 左右滑 | 控制页 ↔ 歌词页 |
| 歌词页 | 点某行 | 跳到该句 |
| 任意态 | 右键拖动 | 移动灵动岛位置（持久化，重启保留） |

展开态的左右滑要求水平位移超过 8px，切页阈值 40px。手势坐标映射到固定尺寸的
容器而非 MouseArea 局部坐标——切页会让岛宽度变化，用局部坐标会把布局变化误算
成手指移动。

音量改由滚轮调节：鼠标一格 `angleDelta.y` 为 ±120，换算成 5% 步进；触控板是连续
小值，按比例缩放，手感更线性。滚轮改的仍是 PipeWire sink 音量，音量 OSD 照常弹出。

右键拖动只移动窗口内的岛，layer-shell 窗口本身保持全屏不动——改窗口 margins 会
让 Hyprland 反复重配 surface，指针事件坐标系跟着窗口跳变，拖动会抖甚至乱飞。偏移
量持久化在 `Persistent.states.island`，范围按岛（含副岛）的实际尺寸动态限制，不会
拖出屏幕。位置拖乱后可用 `qs -c end4-pC ipc call island reset_position` 一键复位。

### 伴随指示器（副岛）

主岛两侧可各挂一个小胶囊，让低优先级活动在音乐播放期间依然可见。两者与
主岛收起态等高（37px）、同圆角（19px）、同字号，视觉上连为一体。

**左侧 · 录屏**：脉冲红点 + 计时，**点击即可停止录屏**。

设计初衷是演示 / 录屏场景：主岛可以继续展示音乐，录屏状态又始终可见且可
操作。录屏单独存在（无音乐）时，它仍正常占用主岛。

**右侧 · 任务**：图标 + 迷你进度条 + 百分比，可同时挂多个。

目前有两类任务，都由通用骨架 `TaskSource` 驱动：

| 类型 | 自动探测的进程 | 优先级 |
|---|---|---|
| `package` | pacman / yay / paru / pikaur / makepkg | 8 |
| `download` | curl / wget / aria2c | 7 |

两种数据来源：

1. **自动探测** — 每 2 秒扫一次进程名，命中即显示（无精确进度时走不确定态动画）。
2. **主动上报** — 脚本用 IPC 推真实百分比：
   `qs -c end4-pC ipc call island task_begin "下载 foo.iso" download`，
   `task_progress 42 download`，`task_end download`。
   包管理另有 `pkg_*` 兼容别名。

在 PKGBUILD 的 `prepare()` / `build()` / `package()` 里插一行 `task_progress`，
就能让 AUR 构建进度实时反映到灵动岛。

想加新任务类型，写一个 `TaskSource` 配置实例即可（声明 `taskId`、`processNames`、
`priority`、`icon`），右侧副岛会自动多一个胶囊，不用改布局。

**右侧 · 通知**：铃铛 + 通知摘要，4 秒后自动消失。

来消息时轻轻顶一下，比弹窗安静又不会错过。多条通知只显示最新一条，期间再来
会重新计时。通知不抢占主岛，只在已有其它活动时作为副岛出现。

录屏指示器已统一到灵动岛：栏上原有的浮动录屏胶囊（`BarContent.qml` 的
`recordingPillLoader`）默认关闭，避免重复显示；把它的 `active` 改回
`Persistent.states.record.enable` 即可恢复。

## 说明

- 更换壁纸会触发重新取色；模板位于 `dot_config/matugen/templates/`
  （Hyprland 窗口阴影颜色也由此生成，见 `templates/hyprland/colors.lua`）
- 桌面歌词偏移微调：
  `qs -c end4-pC ipc call desktoplyrics offset_faster / offset_slower`
- 备份根目录：`~/.local/state/dotfiles-backup/`（`snapshots/`、`state/`）

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

### 许可证继承

本项目采用 [GPL-3.0](LICENSE) 许可证，与上游项目一致。作为衍生作品，本仓库保留了上游的版权与致谢信息，并对个人修改部分负责。

## 许可证

本项目采用 [GPL-3.0](LICENSE) 许可证。
