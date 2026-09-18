# 栏组件 · 岛屿仪表盘 · 液态玻璃

本文记录 `end4-pC`（Quickshell）栏侧的三块改动：**栏中央的岛屿与仪表盘**、**统一歌词源**、
以及**液态玻璃表面 + 动画令牌**。同时说明本轮对「悬停交互动效」的处理范围。

---

## 1. 居中时钟（`modules/ii/bar/ClockWidget.qml`）

> 岛屿上线后栏中间区默认是 `island`（见第 2 节），`clockWidget` 不再显示。本节描述的
> 组件仍在，可在 设置 → 栏 里加回中间区。

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

## 2. 岛屿 + 仪表盘（`custom-island/IslandHost.qml`）

### 2.1 定位

栏中央的交互岛：收起时是一颗胶囊（与左右两组胶囊同一条水平线），点一下从 Bar 中间
往下长成 930×590 的面板，再点缩回去。**常驻挂载在
`panelFamilies/IllogicalImpulseFamily.qml`**，不跟着栏一起销毁（否则栏自动隐藏时连
IPC 一起没了）—— 沿用旧 `ClockDashboard` 的结论。

视觉与动效来自 [Brain_Shell](https://github.com/Brainitech/Brain_Shell)，数据源换成
end4-pC 自己的服务。旧的 `ClockDashboard` 不再挂载（同一处 `PanelLoader` 注释保留，
一行可切回）。

### 2.2 架构：Bar 里只有一段透明槽位

Brain_Shell 的「从 Bar 里长出来」是两件事合成的：TopBar 的 `centerNotch` 宽度从 300
动画到 900（`SeamlessBarShape` 重绘整条 Bar 让中间无缝变宽），外加一个独立的
`Dashboard.qml` 面板窗口。

end4-pC 的 Bar 是普通 `Rectangle`、没法只重绘中间一段，所以这里把两件事合并进同一个
窗口（`custom-island/IslandHost.qml`）：**胶囊和面板是同一个 Item，宽高一起动画** ——
视觉结果一致，且完全不碰 Bar 的绘制代码。

```
IslandHost（WlrLayer.Overlay 的 PanelWindow）
└── surface    width: open ? 930 : 300   height: open ? 590 : 32   clip: true
    ├── 背景        收起态 = 纯色 colPrimaryContainer（与 Bar 右侧胶囊同款）
    │               展开态 = LiquidGlass（cornerStyle 3）/ 实底 Rectangle
    ├── header      height: 32，z: 1 —— Bar 中间那段 notch
    │    └── CenterContent   收起态轮播（clock / music / timer / stopwatch / recording）
    └── expandedArea   四周内缩 23px，opacity 0 → 1
         └── dashboard-caelestia 的 Content（页签条在 Content 内部）→ 5 页
             仪表盘 / 媒体 / Performance / 进程 / 天气
```

> **注意**：早期版本这里挂的是 `TabSwitcher` + 自研四页（Home / System /
> Weather / GitHub，对应 `DashHome` / `DashStats` / `DashWeather` /
> `DashGitHub`）。现在改成 Caelestia 上游的 `Content`（vendor 在
> `modules/ii/dashboard-caelestia/`），那几个 `Dash*.qml` 与 `TabSwitcher.qml`
> **文件还在但已不再挂载**，属于待清理的死代码 —— 改岛屿时不要照着它们改。

- `modules/ii/bar/Island.qml` 是 Bar 里那段等宽（300px）纯透明占位，
  `implicitHeight` 取 `Appearance.sizes.baseBarHeight`；
- **输入 mask 两态**：收起时只覆盖胶囊（其余位置穿透给 Bar），展开时铺满全屏用来
  捕获「点面板外关闭」—— 沿用同仓库 `DynamicIslandHost` 与 `ClockDashboard` 的做法；
- `WlrLayershell.keyboardFocus` 展开时 `Exclusive`（Esc 才收得到）、收起时立刻 `None`。

**底色为什么分两态**：收起态用 `Appearance.colors.colPrimaryContainer` —— 与 Bar 右侧
那几颗 material 胶囊（`BarContent.getMaterialPillColor()` 的默认分支）是**同一颗
token**，所以岛的紫和邻居逐像素一致（实测都是 `#513c73`），且随壁纸主色一起变，
不是写死的紫。展开后回到 `colLayer1Base`：面板里是十几张卡片，紫底会跟卡片抢视线。

收起态刻意**不用 `LiquidGlass`**（它在收起态会多一层顶部渐亮，和邻居并排就露馅），
也**不画描边** —— BarGroup 的背景本来就是一个无边框的纯色 `Rectangle`。
底色用 `ColorAnimation` 跟着生长动画一起过渡。

**收起态时钟的字体**用 `Theme.mainFontFamily`（= `appearance.fonts.main`），理由是复用
`StyledText` 的判定规则：

```qml
property bool shouldUseNumberFont: /^\d+$/.test(root.text)   // 整串都是数字才用 numbers
```

时钟文本在加了日期之后是混合文本（`2026年9月18日 11:19:06`），按同一条规则走 `main`，
于是跟 Bar 上其它组件（网络速度那种 `"1.2 MB/s"`）是同一套字形。计时器 / 秒表仍用
`monoFontFamily` —— 等宽是它们对齐数字的功能需求，不是审美选择。

### 2.3 几何：为什么是 9px / 32px

| 值 | 来源 |
|---|---|
| `capsuleOffset = 9` | Bar 窗口距屏幕边 5px + `BarGroup` 背景上下各内缩 4px |
| `capsuleHeight = 32` | 邻居胶囊的可见高度（`y = 9..41`） |
| `capsuleWidth = 300` | `Theme.cNotchMinWidth` |
| `panelWidth = 930` | `dashboardWidth(900) + notchRadius(15) × 2` |
| `panelHeight = 590` | `dashboardHeight(520) + 70` |

生长动画 320ms `InOutCubic`（与上游同参）；圆角收起时是正圆（`height / 2`），展开后
收敛到 `cornerRadius(17)`。

> Bar 中间区是 `anchors.centerIn`（`BarContent.qml` 的 `absoluteCenter`），中间组件
> 变宽不推动左右两组 —— 这是「岛撑开时左右胶囊纹丝不动」的原因，不是 bug。

### 2.4 五页

页签由 `modules/ii/dashboard-caelestia/dashboard/Content.qml` 的 `dashboardTabs`
定义，页签条（`Tabs.qml`）包含在 Content 内部，不再是外层的 `TabSwitcher`。

| 页 | 内容 | 数据源 |
|---|---|---|
| 仪表盘（Dashboard） | 头像 / 主机 · 天气小卡 · 日期时间 · 月历 · 系统资源 · 媒体卡 | Caelestia `shim/*`（转发到 end4-pC 的服务） |
| 媒体（Media） | 封面 + 曲目 + 进度 + 控制 + **歌词**（含翻译 / 音译副标题） | `MprisController` · `LyricsService`（经 `shim/Lyrics`） |
| Performance | CPU / GPU / 内存 / 磁盘 / 网络 / 电池 | Caelestia `Gpu` 等 · shim |
| **进程（Processes）** | 进程列表：搜索、按 CPU/内存/GPU/名称排序、kill（左键 TERM / 右键 KILL）、可点行改键 | `HyprlandKeybinds` · `ProcessList` |
| 天气（Weather） | 当前天气 + 逐时 + 多日 | `Weather`（shim） |

要点：

- **歌词同源**：媒体页歌词走 `shim/Lyrics.qml` → `LyricsService`，与桌面歌词
  浮层同一份数据。注意 `LyricList.qml` / `LyricsInfo.qml` 里**不能**
  `import Caelestia.Services` —— 那个 C++ 模块导出的单例也叫 `Lyrics`，会盖掉
  shim 的 QML 单例，于是读的是 Caelestia 自己的后端。更糟的是
  `CUtils.enumToString()` 带默认参数（= 多重载），喂进 QML 单例会直接段错误。
- **进程页**是本仓库新增的页（不在 Caelestia 上游），通过 `Content.qml` 的
  `dashboardTabs` 追加。它的数据来自 `scripts/hyprland/get_keybinds.py` 与
  `scripts/processes/process_sampler.py`，详见
  [keybind-manager.md](keybind-manager.md)。
- 页签的 `enabled` **不能**写 `Config.dashboard.showXxx` —— 那是 Caelestia 的
  C++ 配置，本仓库没有对应属性，读出来是 `undefined`，页签会被整个过滤掉。
  新增页签直接写 `enabled: true`。

### 2.5 在栏上的增删

`BarConfig.qml` 的 `allWidgets` 注册了
`{ id: "island", name: "Island", icon: "smart_display" }`，可在 设置 → 栏 里自由增删。
从中间区删掉 `island` 后整座岛（胶囊 + 面板）一起隐藏，并自动收掉展开态
（否则加回来时是个敞着的面板）。

**材质胶囊黑名单**：`BarContent.shouldPaintMaterialPill()` 与 `VerticalBarContent` 的
同名函数把 `"island"` 加进黑名单 —— 岛自己画表面（它要长到 Bar 外面去），Bar 再画
一层材质胶囊会叠成双层、还多出 5px padding。

### 2.6 IPC

```bash
qs -c end4-pC ipc call islanddashboard toggle
qs -c end4-pC ipc call islanddashboard page home   # home / stats / weather / github
qs -c end4-pC ipc call islanddashboard openPanel
qs -c end4-pC ipc call islanddashboard closePanel
qs -c end4-pC ipc call islanddashboard status
```

> target 用 `islanddashboard` 是为了避开灵动岛的 `island`；
> `openPanel` / `closePanel` 不能叫 `show` / `hide` —— 会和 `qs ipc` CLI 的保留字冲突。

### 2.7 录屏设置

收起态捕获条（`CenterContent.qml` 的 `record_setup` 页）和 Quickshell 设置应用
（设置 → 服务 → 屏幕录制）共用同一组开关，状态存在 `config.json` 的 `screenRecord` 下，
字段定义在 `modules/common/Config.qml`：

| 项 | 取值 | 说明 |
| --- | --- | --- |
| `captureTarget` | `screen` / `region` / `window` | `screen` 走 `--fullscreen`；`window` 在 record.sh 里没有对应模式，退化为区域选择 |
| `audioMic` / `audioSystem` | bool | 分别对应 record.sh 的 `--mic` / `--sound`；同时开启时系统声优先 |
| `quality` | `low` / `medium` / `high` | 映射到 libx264 的 `crf` / `preset`，**数值只在 record.sh 里定义** |

`record.sh` 用 jq 读同一份配置，所以改完不需要重启 quickshell。

捕获条上那两个按钮是**点击循环切换**，不是下拉 —— 上游的 hover 弹层没有移植过来，
原因见下。

### 2.8 踩坑

- **Nerd Font 私有区字形（U+E000–F8FF）必须显式写 `font.family`**：end4-pC 主字体
  不含这些码位，漏写就渲染成豆腐块。移植时给每个用图标的 `Text` 都补了
  `Theme.nerdFontFamily`（= `appearance.fonts.iconNerd`）。
- 顶部条带 `header` 的 `z` 要高于展开内容（上游 notch 由更上层的 layer surface
  绘制），但它自身透明且无 handler，只有中间 300px 的 `CenterContent`（自带
  `TapHandler`）吃事件 —— 否则会把下面页签的点击一起吞掉。
- 面板**必须是不透明实体材质**（沿用 `ClockDashboard` 的结论）：同一块屏幕上，
  半透明玻璃会让背后的代码/网页文字直接透进面板，可读性很差。`LiquidGlass` 只留
  边缘高光、关掉斜向高光带（大面板上它会横跨整个宽度，太抢）。
- **单例里用 `Translation` 必须 `import qs.services`**。`Translation` 住在
  `services/` 下，不在 `qs.modules.common` 里；漏了这行不会编译报错，而是在
  **属性初始化阶段**抛 `ReferenceError: Translation is not defined`，值静默退化成
  空字符串 —— 界面上只表现为「捕获条里只剩图标和 ▾，文字整段消失」，既不崩也不弹
  错误框。所以遇到「文字凭空不见」先去看 `qs` 启动日志里的 `WARN scene:`。
- 上游 Brain_Shell 在捕获条上给「捕获目标」「音频」配的是 **hover 展开的下拉弹层**
  （`openStrip` + `popupTargetX/popupTargetWidth` + `keepStripOpen/scheduleStripClose`），
  移植时只搬了按钮没搬弹层，那几个属性一直没有消费者。判断一个移植组件的功能是否
  真的完整，可以反查它的 API 有没有人调用 —— 零消费者的属性通常意味着配套 UI 没搬。

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
| 时钟容器（`bar.clock.background` 打开时） | `quickshell:bar` |

> **岛屿（`quickshell:island`）不在列**：它的面板是不透明实体材质、不依赖合成器模糊
> （见第 2.7 节）。旧 `quickshell:clockDashboard` 的两条规则随 `ClockDashboard` 停用
> 一并失效，留着无害。

对应 `~/.config/hypr/hyprland/rules.lua`：

```lua
hl.layer_rule({ match = { namespace = "quickshell:bar" }, ignore_alpha = 0.2})
hl.layer_rule({ match = { namespace = "quickshell:popup" }, ignore_alpha = 0.2})
-- 旧时钟仪表盘（已由岛屿取代）
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
