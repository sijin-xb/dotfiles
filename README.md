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
活动。数据源通过 `ActivityManager.set(type, payload, priority)` 注册，UI 订阅
`currentType` / `currentPayload`。

| 活动 | 优先级 | 触发条件 | 主岛内容 |
|---|---|---|---|
| `volume` | 30 | 音量 / 静音变化（2 秒后自动消失） | 音量条 |
| `music` | 10 | 任意 MPRIS 播放器有曲目 | 封面、频谱、标题 |
| `package` | 8 | 检测到 pacman / yay / paru / makepkg，或脚本主动上报 | 图标、进度条、百分比 |
| `download` | 7 | 检测到 curl / wget / aria2c，或脚本主动上报 | 图标、进度条、百分比 |
| `notification` | 6 | 收到桌面通知（4 秒后自动消失） | 铃铛、通知摘要 |
| `recording` | 5 | `states.json` 中 `record.enable` 为 true | 脉冲红点、计时 |

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

## 更新日志

### 2026-09-12（第九次）

**新增**

- 锁屏改为 Serpantinum 风格三栏布局：居中大时钟 + 左翼系统监控 / 中翼认证 /
  右翼歌词、通知、媒体。交互结构参考
  [Serpantinum](https://github.com/ilyamiro/serpantinum)，但配色、组件、字体、
  动画曲线全部改用本项目已有的设计令牌，未引入其运行时依赖。
- 锁屏头像改用与桌面 `UserCardWidget` 相同的加载链（`avatarPath` → `~/.face`
  → 图标回退），此前是写死的占位图标。
- 锁屏右翼加入歌词卡，复用 `LyricsService`（与桌面歌词同一数据源，无额外拉取）。
- Hyprland 窗口阴影对齐 Caelestia：`range` 48 → 15、`render_power` 17 → 4、
  偏移归零、颜色由纯黑改为随主题变化的 `inverse_primary`。阴影改由 matugen
  模板生成，换壁纸自动跟随。

**修复**

- 字体配置指向不存在的 `Google Sans Flex`，`fc-match` 静默回退到 Noto Sans CJK，
  全局实际一直在用思源黑体。改为 `Google Sans`。

**说明**

- 锁屏 QML 基于 Qt6：`Button.contentItem` 是 FINAL 属性不可覆盖，圆形图标
  按钮改为自绘；`clip: true` 只裁矩形，圆形头像用 `OpacityMask`。

### 2026-09-12（第八次）

**调整**

- 灵动岛音量调节由「收起态上下滑」改为「滚轮」。上下滑要占用整个收起态的拖动
  手势，和点击展开互相干扰；滚轮不冲突，每格 5% 步进，触控板连续值按比例缩放，
  手感更线性。改的仍是 PipeWire sink 音量，音量 OSD 照常弹出。

**新增**

- 灵动岛支持右键拖动调整位置。拖动只移动窗口内的岛，layer-shell 窗口保持全屏
  不动，避免改 margins 触发 Hyprland 重配 surface 导致拖动抖动。偏移量持久化在
  `Persistent.states.island`，范围按岛的实际尺寸动态限制，不会拖出屏幕。
- IPC `island reset_position`：位置拖乱后一键复位。

**调整**

- `Persistent.qml` 纳入差异层：新增 `island` 字段承载灵动岛偏移量（此前该文件
  完全跟随上游，拖拽所需的持久化字段无处存放）。

### 2026-09-11（第七次）

**修复**

- 灵动岛歌词页点击某一行无反应。`MusicActivity.qml` 里 `seekAtY()` 调用了
  `root.seekRequested(...)`，但这个信号从未声明，运行时报
  `TypeError: Property 'seekRequested' is not a function`；同时 `DynamicIsland.qml`
  的 `if (item.seekRequested !== undefined)` 因此恒为 false，连接根本没建立。
  补上信号声明后，点击歌词行即可跳转。

**调整**

- 歌词逐字高亮取色提亮。封面主色经量化后常常偏暗（深色封面尤其明显），而灵动岛
  底色是纯黑，直接使用会导致高亮几乎读不出来。现对高亮色设亮度下限
  `0.62` 并轻微提饱和（×1.15），保留封面色相的同时保证对比度。
- 点击歌词行跳转时补偿歌词偏移。行时间是歌词坐标系的时间，而当前行判定用的是
  `currentTime + effectiveOffset`，跳转前扣掉该偏移，手动调过歌词偏移后点击
  才能精确落到目标行。

### 2026-09-11（第六次）

**调整**

- Dock 自动隐藏逻辑优化：空工作区不再自动显示 Dock，仅由鼠标悬浮到底部、应用请求、拖拽或手动 pinned 触发，方便录屏 / 截图时获得干净桌面。
- 新增 `dock.revealOnDesktop` 配置项（默认 `false`），方便用户根据需要随时恢复旧版“空桌面自动显示”行为。

### 2026-09-11（第五次）

**新增**

- 壁纸选择器斜切轮播视图：水平轮播，选中项居中放大，相邻项按距离缩放 / 倾斜，
  动态圆角，支持滚轮与方向键；灵感来自 [Serpantinum](https://github.com/ilyamiro/serpantinum)
- 浮动筛选胶囊：全部 / 历史 / 视频 + 颜色圆点（只显示当前目录实际存在的色桶）+ 内联搜索框
- 颜色索引脚本 `scripts/wallpapers/index_colors.py`：多线程算主色并分桶，
  按 `(文件名, mtime, size)` 增量缓存到 `~/.cache/quickshell/wallpapers/`
- `wallpaperSelector.viewMode` 配置项（`grid` 默认，`carousel` 可选），工具栏可一键切换

**说明**

- 网格仍是默认视图，轮播为可选；既有渲染、mpvpaper 视频播放与 matugen 取色均未改动

### 2026-09-11（第四次）

**新增**

- 封面取色：量化当前封面主色，歌词高亮随之着色（`ArtColorSource`）
- 灵动岛手势：收起态上下滑调音量
- `TaskSource` 通用骨架：把「进程探测 + IPC 上报」抽出来复用，新增 `download` 任务源
- 右侧副岛改为列表驱动 + Repeater 渲染，加任务类型不用改布局
- IPC 泛化为 `task_begin` / `task_progress` / `task_end`（`pkg_*` 保留为别名）

**调整**

- 锁屏背景固定为桌面壁纸，移除了播放时淡入的模糊专辑封面背景
- `PackageActivity` 的图标改为读 `payload.icon`，可复用于下载等任务

### 2026-09-11（第三次）

**新增**

- 通知副岛：收到通知时在主岛右侧显示铃铛 + 摘要，4 秒后自动消失，不抢占主岛
- 歌词行点击跳转：点任意一行跳到该句，当前行可点击重播
- 卡拉OK式逐字填充：字内按进度从左往右点亮，取代原来的整字硬切

**调整**

- 展开 / 收起的过渡由 `OutQuint` 换成弹簧动画（`spring: 3.2, damping: 0.45`），
  带轻微回弹的"果冻感"
- 右侧副岛组改为按显示标志计算尺寸，避免 `Row.implicitWidth` 默认为 0 导致整组塌陷
- `MprisSource` 新增 `seekTo(seconds)`，用可写的 `position` 属性做绝对定位

### 2026-09-11（第二次）

**新增**

- 包管理副岛：主岛右侧显示下载 / AUR 构建进度，支持进程自动探测与 IPC 主动上报
- `IslandTheme` 补充 `package` 尺寸项

**修复**

- 栏上反复报 `Cannot assign to read-only property "mirrored"`。守卫用的
  `item.hasOwnProperty("mirrored")` 会命中原生只读属性 `QQuickItem.mirrored`，
  于是对非 visualizer 组件也尝试赋值。改为判断 `modelData === "visualizer"`。
- `MprisSource` 偶发 `Cannot read property 'trackTitle' of null`。改为先缓存
  `player` 到局部变量再判空，避免两次求值之间播放器退出。

**调整**

- 栏上的旧录屏胶囊默认关闭（录屏指示统一到灵动岛）
- 灵动岛窗口宽度 480 → 640，容纳左右两侧副岛

### 2026-09-11

**修复**

- 灵动岛歌词页当前行整行不可见。当前行容器误用 `Layout.fillWidth` / `Layout.fillHeight`，
  但它的 delegate 根节点是普通 `Column`，这些附加属性不生效，容器实际尺寸为 0；
  叠加 `clip: true` 后主文本被整条裁掉，只剩翻译行可见。改为显式设置宽高。
- KRC 逐字高亮错乱。旧代码用 `rawStart >= krc[1]` 判断偏移是绝对时间还是相对
  时间，会把同一行内偏移较大的字误判为绝对时间，产生非单调时间戳，高亮忽前
  忽后。已统一按「相对行首」累加。

**新增**

- 灵动岛录屏伴随指示器：主岛左侧的小胶囊，点击停止录屏
- `IslandTheme` 补充 `recording` 尺寸项，避免单独录屏时回退到 `idle` 尺寸

**调整**

- `recording` 活动优先级由 20 下调至 5，使录屏与音乐并存时主岛显示音乐
- 灵动岛窗口宽度 360 → 480，mask 改为覆盖整条内容行（含伴随指示器）
- 伴随指示器尺寸与主岛收起态对齐，UI 规格统一

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
