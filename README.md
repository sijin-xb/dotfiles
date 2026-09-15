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
- [壁纸视差](#壁纸视差)
- [脚本命令](#脚本命令)
- [快捷键（节选）](#快捷键节选)
- [目录结构](#目录结构)
- [锁屏](#锁屏)
- [灵动岛](#灵动岛)
- [说明](#说明)
- [SPlayer 歌词联动](#splayer-歌词联动)
- [fcitx5-rime × matugen 取色联动](#fcitx5-rime--matugen-取色联动)
- [排障与已知问题](#排障与已知问题)
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

> Mpvpaper 后端启动时会额外带上 `input-ipc-server=~/.cache/quickshell/mpvpaper/mpvpaper-<显示器名>.sock`，
> 供 Quickshell 实现视频壁纸视差（见下一节）。其他后端不带该 socket，视差会自动跳过。

## 壁纸视差

「设置 → 背景 → 壁纸视差」开启后，切换工作区 / 开合侧栏 / 移动鼠标时壁纸会做
轻微平移，产生景深感。静态壁纸和视频壁纸都支持，两者的位移量完全一致。

### 静态壁纸

- 壁纸在 Quickshell 内绘制：先按 `workspaceZoom`（默认 1.07）缩放，再平移，
  位移被 clamp 在缩放留出的余量内。
- **工作区映射覆盖全部工作区**：按工作区号线性映射到 `-1 ~ +1` 再乘可移动余量。
  工作区总数取「设置 → 工作区数量」、「已出现过的最大工作区号」、「概览网格列数」
  三者中的最大值，因此第 6~10 个工作区也有各自独立的视差位置
  （旧实现按概览列数取模，超过 5 个工作区位置就开始重复）。
- **光标跟随只作用于壁纸层**：开启后桌面部件不会跟着鼠标抖动。部件层只跟随
  侧栏开合做轻微景深位移（`widgetsFactor`），工作区切换时保持原位。
- **缩放余量自动补足**：开启侧栏平移时 `workspaceZoom` 会自动提升到
  「可移动余量 ≥ sidebarShift」，避免侧栏位移被 clamp 截断；否则壁纸在
  某些分辨率下会移不到位。
- **过渡动画用 `Easing.OutCubic`，时长默认 400ms**。
  - 时长：Hyprland 的 `workspaces` 是 `speed = 7` 即 700ms（`speed` 的单位是
    ds，1ds = 100ms），但滚轮连续切工作区时 700ms 太长、视差追不上切换，
    看起来就是卡，所以取 400ms。可用「工作区过渡时长」在 200~1400ms 之间调。
  - 曲线：**不要用 `Easing.BezierSpline` + 4 个值的 `bezierCurve`**。
    Qt 需要 3 个控制点（6 个值，末点必须是 `1, 1`），少写终点不会报错，
    而是**静默退化成匀速直线**——实测 400ms 的动画到 192ms 才走到 50%，
    壁纸就会匀速慢慢挪、比窗口滑动"慢半拍"。OutCubic 实测 52ms 走 39%、
    192ms 走 88%、352ms 收尾，前段跟手且尾巴很短。
- **不要在每个 Hyprland 事件上做全量刷新**：`services/HyprlandData.qml` 原来
  对每个事件都调 `updateAll()`，而一轮 `updateAll()` 要起 5 个 `hyprctl`
  子进程（实测每个 3~5ms CPU，合计约 20ms）；一次工作区切换会收到近十个事件，
  滚轮连切时成倍，主线程被进程创建拖住，壁纸视差就会掉帧、慢半拍。
  现在按事件类型只刷该刷的数据，并用 40ms 定时器把同一波事件合并成一次；
  `openlayer`/`closelayer` 直接跳过（quickshell 自己开关面板就会发这个事件，
  实测短时间内能来 6 个）。实测 10 个事件只触发 2 轮刷新。
- 壁纸按「显示尺寸 × 缩放」解码（`sourceSize`），8K 壁纸不会整幅载入内存，
  视差放大后也不会发虚。

### 视频壁纸

视频由 mpvpaper 在后景层绘制，Quickshell 碰不到它的图层，因此改为用
**mpv 的 JSON IPC** 驱动：

```
switchwall.sh 启动 mpvpaper 时加 input-ipc-server=<socket>
  └─ Quickshell 连上该 socket
       └─ set_property video-zoom / video-align-x / video-align-y
```

- socket 路径：`~/.cache/quickshell/mpvpaper/mpvpaper-<显示器名>.sock`
  （两端都基于 XDG 缓存目录，可用 `background.parallax.videoSocketDir` 覆盖）。
- `video-zoom` 传 log2 倍率（`log2(parallaxZoom)`），`video-align-x/y` 传归一化到
  `-1 ~ +1` 的偏移，与静态壁纸的位移等价。
  **注意 mpv 的 `align` 符号与 QML 的 `x/y` 相反**，代码里已取负号，
  两个后端的移动方向保持一致。
- 动画期间约 50Hz 推送、静止时按 `cursorPollInterval` 推送，且**只发送真正
  变化的属性**——否则动画期间每帧重发没变的 `video-zoom`，mpv 每帧都要重配
  视频链，画面会明显卡顿。推送频率也不要超过显示器刷新率：mpv 每收到一次
  `set_property` 就会让视频输出重绘一次，推得太快（试过 125Hz）在滚轮连续
  切工作区时会把 GPU 顶满。
- mpvpaper 比 Quickshell 起得晚时，每 2 秒重建一次连接重试（Quickshell 的
  `Socket` 一次连接失败后不会自己重连）。
- 仅 **mpvpaper** 后端支持；Wallr / Phonto 下视差自动跳过。

### 相关配置

```json
{
  "background": {
    "parallax": {
      "enable": true,
      "enableWorkspace": true,
      "workspaceCount": 10,
      "workspaceAnimationDuration": 400,
      "workspaceZoom": 1.07,
      "enableSidebar": true,
      "sidebarShift": 80,
      "widgetsFactor": 1.2,
      "enableCursor": false,
      "cursorSensitivity": 0.3,
      "cursorPollInterval": 50,
      "enableVideo": true,
      "videoSocketDir": ""
    }
  }
}
```

> - `workspaceZoom` 决定位移幅度（也是唯一的幅度旋钮）：可移动余量 =
>   `屏宽 × (zoom - 1) / 2`。1920 宽屏下：1.02 → 总位移 19px（每工作区约 4px，
>   几乎看不出来）、1.07 → 67px、**1.15 → 288px（每工作区 32px，明显有视差感）**。
>   想更夸张就继续加，代价是壁纸被裁得更多（1.15 约裁掉 26% 面积）。
> - `workspaceAnimationDuration` 太大会在滚轮连续切工作区时追不上切换，
>   看起来发卡；400ms 左右比较跟手。

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
  fcitx5/
    config                fcitx5 主配置
    conf/classicui.conf   Theme=Matugen（matugen 取色联动）
    conf/*.conf           其余 fcitx5 插件配置
dot_local/share/fcitx5/
  rime/
    default.custom.yaml   全局按键 / 翻页设置
    rime_ice.custom.yaml  雾凇拼音语法权重调整 + `/` 符号候选框
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
| `connectivity` | 25 | 蓝牙 / WiFi 连接或断开（2 秒后自动消失） | 连接图标、设备名 |
| `notification` | 6 | 收到桌面通知（4 秒后自动消失） | 铃铛、通知摘要 |
| `recording` | 5 | `states.json` 中 `record.enable` 为 true | 脉冲红点、计时 |
| `privacy` | 4 | 麦克风 / 摄像头被占用 | 警示圆点、设备图标 |
| `battery` | 3 | 插拔电源 / 低电量 / 充满（2.5 秒后自动消失） | 电池图标、状态、百分比 |

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

## SPlayer 歌词联动

桌面歌词默认走 MPRIS + 酷狗抓词。如果播放器是 **SPlayer**，可以在它的
「设置 → WebSocket 服务」里打开服务（默认端口 **25885**），歌词会直接由
SPlayer 推送，省掉抓取、也不用等网络。

```
SPlayer --WebSocket(25885)--> scripts/desktopLyrics/splayer-ws.py
                                    │ 每行一个 JSON（stdout）
                                    ▼
                        Quickshell DesktopLyrics（Process + SplitParser）
```

协议（从 SPlayer 的 app.asar 里确认，WS 为单向广播）：

| 消息 | data |
|---|---|
| `welcome` | 连接成功 |
| `song-change` | `title` / `name` / `artist` / `album` / `duration` |
| `lyric-change` | `lrcData` / `yrcData`（**行数组**，每行含 `startTime`/`endTime`/`words[].word`/`translatedLyric`，时间单位 ms） |
| `progress-change` | `currentTime` / `duration`（ms，约每 0.5s） |
| `status-change` | `status`（播放/暂停） |

实现要点：

- `scripts/desktopLyrics/splayer-ws.py` 是纯标准库的极简 WebSocket 客户端，
  把上述消息归一成 `{"type":"lyric","lines":[...]}` 等 JSON 行写 stdout，
  断开后每 3s 自动重连（SPlayer 重启无需干预）。
- QML 侧把数据喂给现有的 `lyricLines` / `currentTime` / `isPlaying`，
  下游（歌词视图、锁屏、桌面宠物）无需改动。
- **只有真的收到 WS 歌词才接管**（`splayerHasLyrics`）：SPlayer 只在换歌时
  推 `lyric-change`，刚连上时可能还没有歌词，此时保留 MPRIS + 酷狗流程兜底。
- 接管后 `doFetch()` 直接返回、MPRIS 精同步定时器停摆，避免两边互相覆盖。
- 关闭：`background.desktopLyricsSplayerEnable = false`（或改端口
  `desktopLyricsSplayerPort`）。

## 排障与已知问题

### 登录后整个桌面卡死（tty 都进不去）

**症状**：Hyprland 登录后整个合成器无响应，鼠标键盘全无反应，连
`Ctrl+Alt+F3` 切 tty 都无效，只能硬重启。

**根因**：Quickshell 由 `hypr/hyprland/execs.lua` 在登录时自动拉起。早期该行
注入了 `QT_IM_MODULE=fcitx`、`GTK_IM_MODULE=fcitx`、`QT_WAYLAND_TEXT_INPUT_PROTOCOL=zwp_text_input_v3`
一整套输入法环境变量，该组合与 layer-shell 存在死锁，在合成器刚启动、环境
尚未稳定时会把整个会话一起拖死。

**修复**：启动行改为干净的 `qs -c $qsConfig`，不再注入那套变量。输入法环境
由前一行 `dbus-update-activation-environment --systemd XMODIFIERS GTK_IM_MODULE …`
全局设置，无需在 QS 启动时重复注入。

**另注意 Hyprland 版本**：`0.56.2-2.1` / `0.56.2-2` 已长期稳定；升级到
`0.56.2-3.1` 后曾出现 Quickshell 一启动就把会话拖死的情况。排查期间建议锁定
版本（在 `/etc/pacman.conf` 加 `IgnorePkg = hyprland`）。

**临时禁用 QS 自启动**：把 `~/.config/quickshell/end4-pC/shell.qml` 改名为
`shell.qml.off` 即可让 Quickshell 找不到入口而不启动，排查时很有用。

### Quickshell 报 “Could not find \"end4-pC\" config directory”

这不是路径不存在，而是 `~/.config/quickshell/end4-pC/` 下找不到可识别的入口
`shell.qml`。常见于把 `shell.qml` 改名为 `.off` 之后忘记改回。改回来即可。

### 设置面板某页无法向下滚动（滚到底就回弹）

**症状**：设置面板的某一页（典型是「界面」）滚到下半部分时，内容像被顶住
一样弹回，靠后的分节永远看不到。

**根因**：该页的 `contentHeight` 被低估。`ContentPage` 继承自
`StyledFlickable`，滚动上限是 `contentHeight - height`；一旦实际内容比
`contentHeight` 高，超出的部分就永远滚不到，表现为"回弹"。

最常见的原因是**把 `Repeater` 直接放进 `GroupedList`**：`GroupedList` 的
`default property list<Item> items` 只把 `Repeater` 本身算作一个 item，而
`Repeater` 没有 `implicitHeight`，展开出的子项高度全部丢失。

**修复**：分组列表用 `ColumnLayout` + `Repeater` 手写，给每个 delegate 显式
`implicitHeight`。参考 `BarConfig.qml`、`BackgroundConfig.qml` 的写法。

### 换壁纸后光标颜色不跟随

`~/.config/matugen/config.toml` 曾丢失 `post_hook`（光标主题重渲染钩子）以及
`[templates.yazi]`、`[templates.obs]`、`[templates.vscode]` 三块模板。完整内容
备份在 `config.toml.orig`。若发现光标不再随壁纸主色变化，先比对这两个文件。

## 说明

- 更换壁纸会触发重新取色；模板位于 `dot_config/matugen/templates/`
  （Hyprland 窗口阴影颜色也由此生成，见 `templates/hyprland/colors.lua`）
- 桌面歌词偏移微调：
  `qs -c end4-pC ipc call desktoplyrics offset_faster / offset_slower`
- 备份根目录：`~/.local/state/dotfiles-backup/`（`snapshots/`、`state/`）

## fcitx5-rime × matugen 取色联动

fcitx5-rime 的候选框外观由 fcitx5 的 Classic UI 主题控制，matugen 每次换壁纸后
自动重新生成该主题文件，实现输入法配色与壁纸同步。

### 工作原理

```
壁纸换色（switchwall.sh）
  └─ matugen 取色
       └─ [templates.fcitx5] → ~/.local/share/fcitx5/themes/Matugen/theme.conf
                                  ↑ 由 dot_config/matugen/templates/fcitx5-theme.conf 渲染
```

`fcitx5-theme.conf` 模板使用 Material You 语义颜色：

| 模板变量 | 含义 | 用途 |
|---|---|---|
| `colors.surface_container` | 表面容器色 | 候选框背景 |
| `colors.primary` | 主色 | 预编辑高亮背景 |
| `colors.secondary_container` | 次级容器色 | 选中候选背景 |
| `colors.on_surface` | 表面前景色 | 普通文字 |
| `colors.on_primary` | 主色前景 | 预编辑高亮文字 |
| `colors.on_secondary_container` | 次级前景 | 选中候选文字 |
| `colors.outline` | 轮廓色 | 边框 |

### 相关文件

| 文件 | 说明 |
|---|---|
| `dot_config/matugen/templates/fcitx5-theme.conf` | matugen 模板，每次换壁纸重新渲染 |
| `dot_config/matugen/config.toml` → `[templates.fcitx5]` | 模板注册条目 |
| `dot_config/fcitx5/conf/classicui.conf` | `Theme=Matugen`（启用生成的主题） |
| `dot_local/share/fcitx5/rime/default.custom.yaml` | 全局按键 / 翻页定制 |
| `dot_local/share/fcitx5/rime/rime_ice.custom.yaml` | 雾凇拼音语法权重调整 + `/` 符号候选框 |

> **注**：fcitx5-rime 在 Linux 下无独立的皮肤系统（squirrel.yaml / weasel.yaml
> 是 macOS / Windows 专用），候选框样式完全由 fcitx5 Classic UI 主题决定，因此
> 接入 matugen 只需配置该主题即可，无需额外处理 rime 侧的配色。

### 中文模式下 `/` 弹出符号候选框

中文模式下按 `/` 会弹出常用符号候选框（`， 。 、 ； ： ？ ！ “ ” × ÷ ± ≈ ∞ √ ★ ☆ → ← ● ◆ ✓` 等
48 个），用 `,` / `.` 翻页（`default.custom.yaml` 里已把它们映射为 Page_Up / Page_Down）。
需要字面量半角斜杠时切到英文（Shift / Ctrl+Space）即可。

实现方式是把 `half_shape` 里的 `/` 由单值 `'/'` 改成多值列表。
原理见 librime `src/rime/gear/punctuator.cc`：取到标点定义并把按键推入输入串后，
只有**单值映射**才会立即上屏（`ConfirmUniquePunct`），列表型映射只列出候选，
交给用户选择。

改这个配置有两个坑：

1. 必须写成扁平路径 `punctuator/half_shape/+`（映射追加）的形式。
   写成嵌套结构 `punctuator: { half_shape: ... }` 会把整个 `punctuator` 节点
   替换掉，v 模式符号表和全角标点会一起消失。
2. 键名 `/` 不能出现在路径里（会被当成路径分隔符），只能放在值里。

改完需要重新部署才会生效：

```bash
rime_deployer --build ~/.local/share/fcitx5/rime /usr/share/rime-data
fcitx5-remote -r      # 让 fcitx5 重新加载
```

部署后可用 `build/rime_ice.schema.yaml` 校验合并结果
（`punctuator.half_shape` 应保留全部 32 个键，`/` 是多值列表，
`punctuator.symbols` 应仍有 266 项）。


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
