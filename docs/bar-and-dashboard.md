# 栏组件 · 居中时钟仪表盘 · 液态玻璃

本文记录 `end4-pC`（Quickshell）栏侧的三块改动：**居中时钟与其仪表盘**、**统一歌词源**、
以及**液态玻璃表面 + 动画令牌**。同时说明本轮对「悬停交互动效」的处理范围。

---

## 1. 居中时钟（`modules/ii/bar/ClockWidget.qml`）

### 1.1 显示项：对齐 caelestia 的 `bar.clock`

配置项在 `Config.options.bar.clock`（设置 → 栏 → Clock）：

| 键 | 默认 | 说明 |
|---|---|---|
| `showIcon` | `true` | 时间前的 `calendar_month` 图标 |
| `showDate` | `true` | 日期（沿用 `time.dateFormat`） |
| `showSeconds` | `true` | 是否显示秒。默认 `true` 是为了沿用旧的 `hh:mm:ss` 观感 |
| `showAmPm` | `true` | 12 小时制时显示 AM/PM |
| `background` | `false` | 给整个时钟垫一层液态玻璃容器 |

时间取值直接来自 `DateTime` 单例（`SystemClock` 已按 `time.secondPrecision` 刷新），
组件内部**不再自己起定时器**。

### 1.2 交互（全部是点击/滚轮，没有悬停触发）

| 操作 | 行为 |
|---|---|
| 左键 | `bar.clock.clickAction`：`dashboard`（默认）/ `sidebarRight` / `wallpaperSelector` / `none` |
| 右键 | 开合右侧边栏（日历 + 通知） |
| 中键 | 复制「日期 + 时间」到剪贴板（`bar.clock.middleClickCopy`） |
| 滚轮 | 切换秒显示（`bar.clock.wheelSwitchSeconds`）；按住 **Shift** 滚轮切换 12/24 小时制 |
| Esc / 点空白 | 关闭仪表盘 |

---

## 2. 时钟仪表盘（`modules/ii/bar/ClockDashboard.qml`）

### 2.1 定位

对齐 caelestia 的 Dashboard：把和时间相关的信息集中到一个从栏中央拉开的浮层，
而不是只靠悬停看一个小 tooltip。**常驻挂载在 `panelFamilies/IllogicalImpulseFamily.qml`**，
不跟着栏一起销毁（否则栏自动隐藏时连 IPC 一起没了）。

### 2.2 结构：固定状态栏 + 多页（参考 caelestia 的分页式 Dashboard）

```
LiquidGlass 卡片
├── 固定状态栏（切页时不变）
│    左：工作区胶囊（当前高亮）
│    中：日期 / 星期 + 大号 时:分
│    右：音量 % · 亮度 % · 电量 %（没有电池的台式机整行隐藏）
├── 分隔线
├── SwipeView（5 页，左右滑动切换）
│    页 0「概览」 月历 · 世界时钟 · 最近通知
│    页 1「媒体」 圆形封面 · 曲目 · 可拖动进度 · 控制 · 5 行歌词
│    页 2「系统」 CPU / 内存 / 交换 / 磁盘 · 用户名/发行版 · 运行时间 · 进程列表
│    页 3「天气」 当前天气 + 湿度/风/降水/能见度/气压/云量 · 刷新按钮
│    页 4「GitHub」 用户名 → 仓库卡片
└── 分隔线
     页指示（图标 + 文字，可点）+ 切页提示 + 通知/壁纸/关闭
```

- 月历复用 `modules/ii/sidebarRight/calendar/CalendarWidget.qml`（可翻月）
- 世界时钟取 `WorldClock.entries` 前 4 个时区，带昼夜图标；卡片进入时错峰淡入上移
- 概览页最近通知复用全局 `NotificationAppIcon` 组件显示应用图标，支持一键清空与单条删除
- 媒体页的歌词直接读 `LyricsService`（见第 3 节），和桌面歌词/灵动岛同一份数据；
  渲染成 5 行窗口（上 2 + 当前 + 下 2），当前行主色加粗，其余按距离衰减透明度
- 媒体页进度条可拖动 seek，播放时卡片左侧滑出音频可视化（cava 输出同源）
- 系统页进程列表走 `services/ProcessList.qml`，`ListView { reuseItems: true }` 渲染，
  支持搜索、排序、hover kill；只在停留系统页时轮询
- 天气页读 `Weather.data`，图标用 `Icons.getWeatherIcon(wCode)`

### 2.3 交互

| 操作 | 行为 |
|---|---|
| 左键栏中央时钟 | 开合仪表盘 |
| 左右滑动 / 滚轮 / ← → | 切页 |
| 点击页指示 | 跳到该页 |
| 点浮层外任意位置 / Esc | 关闭 |

打开时把 layer surface 的输入 mask 扩到整屏，垫一层透明捕获层实现「点空白关闭」——
沿用 `modules/ii/overview/Overview.qml` 的做法，**故意不用 `HyprlandFocusGrab`**，
它会打断 fcitx5 的输入法桥接。

**页高踩过的坑**：概览页的月历 6 行固定占位较高，页高（`pageHeight`）要留够；
另外概览页第一列必须显式写 `Layout.alignment: Qt.AlignTop` ——
RowLayout 里默认会垂直居中，被撑高后月历会被往下推、最后一行超出页面被
`SwipeView` 的 `clip` 裁掉（看起来像「月历缺了一行」）。

### 2.4 IPC

```bash
qs -c end4-pC ipc call clockdashboard toggle
qs -c end4-pC ipc call clockdashboard page 2      # 跳到指定页（0-3）
qs -c end4-pC ipc call clockdashboard nextPage
qs -c end4-pC ipc call clockdashboard previousPage
```

> 注意：`ipc call <target> show` 会被 `qs ipc show` 这个子命令名抢占，命令行下用 `toggle` 更稳。

---

## 3. 统一歌词源（`services/LyricsService.qml`）

### 3.1 背景

原来歌词有两条互不相干的链路：桌面歌词浮层自己抓，栏/锁屏/侧边栏走另一个
`services/LyricsService.qml`（读 `scripts/lyrics/lyrics.py`）。两边时间基准、翻译/音译
处理都不一样，同一个歌会显示不同内容。

### 3.2 现在

**全 shell 只有一个歌词数据源**：`LyricsService`。

- 主源：`scripts/desktopLyrics/splayer-ws.py`（SPlayer WebSocket 桥接，逐字 + 翻译 + 音译）
- 退路：`scripts/lyrics/kugou_lyrics.py`（按 MPRIS 元数据取词；MPRIS 没元数据时用音频指纹认歌）

消费方（全部只读 `LyricsService`，不再各自维护取词逻辑）：

| 组件 | 用到的东西 |
|---|---|
| `modules/common/widgets/Lyrics.qml` | `status` / `slots` / `before` / `restartLyrics()` |
| `modules/ii/desktopLyrics/DesktopLyrics.qml` | 全部（这个文件现在只剩视图 + IPC） |
| `modules/ii/lock/caelestia/content/LockLyrics.qml` | `slots` / `before` |
| `modules/ii/lock/SerpantinumLockSurface.qml` | `status` |
| `modules/ii/dynamicIsland/MusicActivity.qml` | `lyricLines` / `currentLineIndex` / `adjustedTime` / `effectiveOffset` |

灵动岛的 `lyricsProvider` 在 `shell.qml` 里直接指向 `LyricsService`，
不再依赖桌面歌词那个窗口对象。

### 3.3 对外 API（旧名字保持兼容）

```
status          "loading" | "ok" | "not_found" | "no_info"
slots           7 行窗口（当前行居中），供栏/锁屏的固定槽位渲染
before/after/total
activeIndex     当前行在 lyricsLines 里的下标
lyricsLines     [{ time, text, trans, roman, words }]
restartLyrics() 强制重新取词
source          "splayer" | "kugou" | "none"
currentText / currentTrans / currentRoman / nextText
currentTime / duration / isPlaying / effectiveOffset / adjustedTime
buildLineHtml(line)   逐字高亮 HTML
```

时间补偿（每播放器自动补偿 + 按播放器持久化的手动偏移）也一起搬进了服务，
IPC 命令不变：

```bash
qs -c end4-pC ipc call desktoplyrics refetch
qs -c end4-pC ipc call desktoplyrics offset_faster    # 歌词提前 100ms
qs -c end4-pC ipc call desktoplyrics offset_slower    # 歌词延后 100ms
qs -c end4-pC ipc call desktoplyrics get_offset
```

> `scripts/lyrics/lyrics.py` 已不再被引用（保留文件，未删除）。

---

## 4. 液态玻璃（`modules/common/widgets/LiquidGlass.qml`）

### 4.1 分层

1. **基底** —— 半透明但**绝不纯透明**的着色层（`minAlpha = 0.55` 兜底）
2. **透光** —— 顶部柔和的高光渐变，模拟光从上方穿过玻璃
3. **折射** —— 斜向高光带 + 底部回光，模拟厚度带来的偏折
4. **高光边** —— 内外两层描边（外亮内暗），勾出玻璃的「厚度」

用法：

```qml
LiquidGlass {
    anchors.fill: parent
    radius: Appearance.rounding.large
    level: 0                 // 0/1/2 对应 colLayer0/1/2
    tint: Qt.rgba(...)       // 也可显式给底色，透明色会被抬到 minAlpha 以上
}
```

### 4.2 真正把背景糊掉的是合成器

QML 只负责玻璃本身的质感；**背景模糊由 Hyprland 的 layer rule 提供**。
已应用玻璃的 surface：

| 组件 | namespace |
|---|---|
| 栏上的三个 material 药丸（`modules/ii/bar/BarContent.qml`） | `quickshell:bar` |
| 栏上小部件弹层（`modules/common/widgets/StyledPopup.qml`） | `quickshell:popup` |
| 时钟仪表盘卡片 | `quickshell:clockDashboard` |
| 时钟容器（`bar.clock.background` 打开时） | `quickshell:bar` |

对应 `~/.config/hypr/hyprland/rules.lua`：

```lua
hl.layer_rule({ match = { namespace = "quickshell:bar" }, ignore_alpha = 0.2})
hl.layer_rule({ match = { namespace = "quickshell:popup" }, ignore_alpha = 0.2})
hl.layer_rule({ match = { namespace = "quickshell:clockDashboard" }, blur = true})
hl.layer_rule({ match = { namespace = "quickshell:clockDashboard" }, ignore_alpha = 0.2})
```

**为什么要单独调 `ignore_alpha`**：上面 `quickshell:.*` 的通用规则是
`ignore_alpha = 0.79`，意思是「alpha 低于 0.79 的像素直接跳过，不参与模糊采样」。
玻璃底板的 alpha 大约 0.55~0.78，正好被这条规则全部跳过 → 玻璃糊不起来。
把阈值降到 0.2 之后，玻璃块会被采样，而完全透明的空白段（alpha 0）依然不模糊。

---

## 5. 动画令牌（对齐 caelestia）

`Appearance.animationCurves` 的取值与 caelestia `Tokens.anim` 逐条对齐，本轮补齐：

| 令牌 | 曲线 | 时长 |
|---|---|---|
| `expressiveFastEffects` | `[0.31, 0.94, 0.34, 1, 1, 1]` | 150ms |
| `expressiveDefaultEffects` | `[0.34, 0.80, 0.34, 1, 1, 1]` | 200ms |
| `expressiveSlowEffects` | `[0.34, 0.88, 0.34, 1, 1, 1]` | 300ms |
| `durationSmall / Normal / Large / ExtraLarge` | —— | 200 / 400 / 600 / 1000ms |

`Appearance.animation` 新增：`expressiveFastEffects` / `expressiveDefaultEffects` /
`expressiveSlowEffects`（带 `numberAnimation`、`colorAnimation` 工厂）、
`standardSmall/Normal/Large`、以及弹层用的 `popout` / `popoutExit`。

`StyledPopup` 的开合节奏走 `popout`：从锚点方向缩放入场，`transformOrigin` 跟着栏的边缘走。

> 空间类过渡（`elementMove*`）用带过冲的 spatial 曲线；纯透明度/颜色过渡用 effects 曲线，
> 不做过冲，避免「颜色抖一下」。这是 caelestia 的分法。

---

## 6. 悬停交互：只对 bar 时钟做了移除

**唯一的改动范围是栏上的居中时钟（`modules/ii/bar/ClockWidget.qml`）。**
它的悬停被**彻底移除**：不弹预览弹窗、不变色、不改指针形状。

- 删掉了 `ClockWidgetPopup` 的实例化（文件本身保留，没有删除）
- MouseArea 不再设 `hoverEnabled`，也没有 `cursorShape`
- 时钟的交互全部改走点击/滚轮（见第 1.2 节），功能没有减少

**其余所有悬停交互一律保持原样，没有被改动**：

| 组件 | 悬停行为 |
|---|---|
| `UtilButton` | 悬停变宽（26→54）+ 颜色过渡 |
| `Workspaces` | 悬停预览高亮、指针离开才压暗特殊工作区 |
| 各栏小部件弹层（`StyledPopup`） | 悬停触发弹出 |
| `WeatherBar` / `NetworkSpeed` / `BatteryIndicator` / `Bluetooth` / `Resources` | `hoverEnabled` + 悬停弹层 |
| 悬停 tooltip、设置页表单控件 | 原样 |

> 如果后续想调整别的组件的悬停，改对应文件即可 —— 不要在 `StyledPopup` 这类
> 公共基类上动手，会一次性影响所有弹层。

---

## 7. 排障：组件「凭空消失」怎么查

本轮踩过一个坑，值得记下来。

**症状**：栏里 `resources` 那组环形指示器消失，其后的元素整体左移；没有 ERROR。

**根因**：`StyledPopup.qml` 里同一个 `Rectangle` 上写了**两个 `Component.onCompleted`**。
QML 不允许同一属性重复赋值，日志里只有一行不起眼的：

```
WARN scene: @modules/common/widgets/StyledPopup.qml[163:13]: Property value set multiple times
```

它让 `StyledPopup` 编译失败变成 **unavailable**，于是所有继承它的弹层
（`ResourcesPopup` / `ClockWidgetPopup` / `WeatherPopup` / `BatteryPopup` / …）全部不可用，
声明这些弹层的栏组件连带构建失败。

**排查要点**：这类问题的日志关键字是 `unavailable` 和
`Property value set multiple times`，**不是** `ERROR`。
只 grep `ERROR|ReferenceError|TypeError` 会完全漏掉。

用 `scripts/../` 之外的临时脚本或直接：

```bash
killall qs; timeout 15 qs -c end4-pC > /tmp/qs-check.log 2>&1
grep -nE "unavailable|Property value set multiple times|Failed to load|Syntax error" /tmp/qs-check.log
```
