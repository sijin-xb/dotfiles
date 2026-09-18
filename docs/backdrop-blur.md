# 限定范围内的背景模糊（不依赖 Hyprland 全局模糊）

> 组件：`modules/common/widgets/GlassBackdrop.qml`
> 应用：旧时钟仪表盘卡片（`modules/ii/bar/ClockDashboard.qml`）
> 配置：`Config.options.appearance.transparency.qmlBackdropBlur` / `qmlBackdropBlurRadius`
>
> **现状**：栏中央已改为**岛屿**（`custom-island/IslandHost.qml`），它的面板是
> **不透明实体材质**、不依赖这套模糊，所以本机制目前**没有活跃消费者**（`GlassBackdrop`
> 只剩停用的 `ClockDashboard` 在用）。文档与组件都保留：切回 `ClockDashboard`
> （`panelFamilies/IllogicalImpulseFamily.qml` 里取消注释那一行）即恢复生效。

## 1. 为什么要自己做

原来面板的「毛玻璃」完全是**合成器代劳**的：QML 只画一块半透明色，由
`hl.layer_rule({ namespace = "quickshell:xxx", blur = true })` 让 Hyprland 去模糊
该图层背后的画面。这条路能用，但有四个绕不开的问题：

1. **模糊范围不可控**：Hyprland 模糊的是**整个图层 surface**。面板类窗口通常铺满整屏
   （为了拿全屏输入 mask 做「点空白关闭」），于是整屏都在模糊采样，
   只有完全透明的地方因为 `ignore_alpha` 才被跳过。
2. **`ignore_alpha` 陷阱**：它是「alpha 低于该值就跳过模糊」。
   通用规则里 `quickshell:.*` 设的是 `0.79`，而玻璃底色 alpha 常在 0.55~0.78
   —— 正好全部被跳过，表现为「玻璃糊不起来」，而且**不报任何错**。
3. **耦合多套 hack**：本仓库为了解决 tooltip 配色异常，不得不同时写
   `xray = false` 和 `ignore_alpha = 1`；`quickshell:popup` / `mediaControls` 也各自
   单独调过 `ignore_alpha`。这些参数互相影响，改一处容易连带别处出问题。
4. **不可移植**：换合成器（niri / 其他）就没有 `layerrule blur` 了。

自己抓屏自己糊，就把这四件事一次性解耦：模糊范围由**我们自己的裁剪区域**决定，
不依赖任何合成器参数。

## 2. 技术路线

```
┌─ ScreencopyView ─┐   ┌─ MultiEffect ─┐   ┌─ 父级 clip + 圆角 ─┐
│ wlr-screencopy   │ → │ 高斯模糊      │ → │ 裁成面板形状        │
│ 抓整个输出的画面  │   │ blur/blurMax  │   │ （面板之外的丢弃）  │
└──────────────────┘   └───────────────┘   └────────────────────┘
```

### 关键点：怎么让「整屏纹理」只显示面板那一块

`ScreencopyView` 抓的是**整个输出**的纹理，没有「只抓某块区域」的接口。
所以做法是：把整屏纹理按**屏幕坐标**摆好，再让面板自己裁。

`PanelWindow` 铺满整屏时，窗口坐标 == 该输出的屏幕坐标，因此：

```qml
readonly property real screenOffsetX: -root.mapToItem(null, 0, 0).x
readonly property real screenOffsetY: -root.mapToItem(null, 0, 0).y

ScreencopyView {
    x: root.screenOffsetX; y: root.screenOffsetY
    width: root.screen?.width ?? 0
    height: root.screen?.height ?? 0
    captureSource: root.screen
    live: false
    visible: false            // 纹理只当 source，不直接画
}

MultiEffect {
    x: root.screenOffsetX; y: root.screenOffsetY   // 同一套偏移，保证对齐
    width: root.screen?.width ?? 0
    height: root.screen?.height ?? 0
    source: capture
    blurEnabled: true
    blur: Math.min(root.blurRadius, root.blurMax)
    blurMax: root.blurMax
    opacity: 0.95 * root.intensity
}
```

父级是玻璃面板，`clip: true` + `radius` 会把整屏纹理裁成面板形状 ——
**模糊只发生在面板覆盖的那一块，屏幕其余部分完全不受影响。**

## 3. 关键实现步骤与所用接口

### 3.1 用到的接口

| 接口 | 来自 | 用途 |
|---|---|---|
| `ScreencopyView` | `Quickshell.Wayland._Screencopy` | 抓输出画面（wlr-screencopy） |
| `captureSource` | 同上 | 指定抓哪个输出（传 `PanelWindow.screen`） |
| `live` | 同上 | `false` = 只抓一帧；`true` = 持续抓帧 |
| `hasContent` | 同上 | 首帧是否到位（**异步**，必须等它） |
| `captureFrame()` | 同上 | 手动重抓一帧（`live: false` 时用） |
| `paintCursor` | 同上 | 是否把光标画进纹理 |
| `sourceSize` / `constraintSize` | 同上 | 抓取分辨率约束 |
| `MultiEffect.blur / blurMax / blurEnabled` | `QtQuick.Effects` | 高斯模糊 |
| `mapToItem(null, 0, 0)` | `QtQuick.Item` | 取自己在窗口/屏幕里的位置 |
| `WlrLayershell.*` | `Quickshell.Wayland` | 图层 namespace / 层级 / 键盘焦点 |

### 3.2 步骤

1. **组件放在玻璃面板内部**，`anchors.fill: parent`，`z: -1`
   （面板的玻璃高光层先声明、后绘制，正好压在模糊层上面）。
2. **`captureSource` 传面板所在输出的 screen**（`PanelWindow.screen`）。
3. **等 `hasContent`**。抓帧是异步的，首帧到达前 `hasContent` 为 `false`。
4. **`MultiEffect` 用同一套 `screenOffsetX/Y` 偏移**，与 `ScreencopyView` 对齐。
5. **父级 `clip: true` + `radius`** 裁形。
6. **需要重抓时调 `refresh()`**（内部转调 `captureFrame()`）。

### 3.3 必须处理的三个时序问题

#### (a) 自反馈：抓帧时自己不能已经画出来

如果面板已经可见再去抓屏，抓到的画面里**包含面板自己**，模糊后叠在面板上
= 无限套娃。所以面板的 `opacity` 挂在抓帧状态上：

```qml
opacity: (root.opened && (backdrop.ready || root.backdropGaveUp)) ? 1 : 0
```

先抓帧 → `hasContent` 变 true → 面板才淡入。抓到的就是「面板出现之前」的画面。

#### (b) 兜底：抓帧一直不来不能让面板打不开

`ScreencopyView` 依赖 wlr-screencopy 协议，理论上可能不可用。
一旦 `ready` 永远为 false，上面的 `opacity` 会把面板永久锁在透明状态。
必须加超时放行：

```qml
property bool backdropGaveUp: false
Timer {
    running: root.opened && !root.backdropGaveUp && !backdrop.ready
    interval: 300
    onTriggered: root.backdropGaveUp = true
}
```

超时后放弃模糊、直接显示面板（退化成纯玻璃底色）。

#### (c) 底色厚度要跟着模糊开关走

模糊生效时底色要压薄（否则糊了也透不出来），不生效时用原来的厚度：

```qml
tint: Qt.rgba(base.r, base.g, base.b,
    (Config.options.appearance.transparency.qmlBackdropBlur && backdrop.ready) ? 0.55 : 0.78)
```

`0.55` 是 `LiquidGlass.minAlpha` 的下限，不能再低 —— 再低就违反
「不使用纯透明背景」的约定。

## 4. 怎么规避 Hyprland 全局模糊的已知 bug

核心动作：**把该命名空间的合成器模糊关掉**，避免「合成器模糊 + QML 模糊」叠加。

```lua
-- ~/.config/hypr/hyprland/rules.lua
hl.layer_rule({ match = { namespace = "quickshell:clockDashboard" }, blur = false })
```

逐个对应前面列的问题：

| 已知问题 | 本方案怎么规避 |
|---|---|
| 模糊范围覆盖整个图层（面板铺满整屏 → 整屏采样） | 模糊由面板 `clip` 决定，**只糊面板那一块**，屏幕其余部分零影响 |
| `ignore_alpha` 阈值高于玻璃 alpha → 静默不糊 | 完全不看 `ignore_alpha`，不存在这个坑 |
| tooltip 配色异常要靠 `xray = false` + `ignore_alpha = 1` 双 hack | 不参与合成器模糊，这两条 hack 与该面板无关 |
| 各 namespace 参数互相牵连，改一处影响别处 | 只改自己组件内的 `blurRadius` / `tint`，**不碰任何 layerrule** |
| 换合成器（niri 等）没有 `layerrule blur` | 纯 QML + wlr-screencopy，与合成器模糊配置无关 |
| 全屏半透明图层导致整屏发灰 | 面板外的区域我们根本不绘制 |

> 注意：`quickshell:bar` / `quickshell:popup` 的 `ignore_alpha = 0.2` 仍在用，
> 那是给「栏药丸 / 小部件弹层」的合成器模糊准备的，本方案不影响它们。

## 5. 与依赖全局模糊的差异与取舍

| 维度 | 合成器模糊（`layerrule blur`） | 本方案（QML 自绘） |
|---|---|---|
| 模糊范围 | 整个图层 surface | **仅面板覆盖区域** |
| 是否实时 | 实时，背后内容一动就跟着变 | **快照**（`live: false`）；要实时得开 `live: true` |
| 视频壁纸 | 正常跟随 | `live: false` 会定格；`live: true` 开销明显 |
| 配置依赖 | 依赖 hypr 的 blur 开关、radius、passes、`ignore_alpha` | **只依赖 wlr-screencopy**，与合成器模糊配置无关 |
| 可移植性 | 仅 Hyprland | 任何支持 wlr-screencopy 的合成器 |
| 单次开销 | 合成器侧，几乎为零 | 每次打开一次抓帧（一次 buffer 往返 + 一次 GPU 模糊） |
| 持续开销 | 合成器 blur passes | 面板可见期间每帧一次 `MultiEffect` 模糊 |
| 可调粒度 | 每个 namespace 一套参数，互相牵连 | 每个组件独立 `blurRadius` / `intensity` |
| 与透明度设置的关系 | 需要 `ignore_alpha` 配合才看得见 | 无关，底色 alpha 自己控制 |
| 失败表现 | 静默不糊，无报错 | `hasContent` 不来 → 300ms 后兜底放行，功能不受影响 |

**结论与建议取舍**：

- **静态壁纸（本机现状）** → 用本方案，`live: false` 一次抓帧足够，
  范围可控、不受合成器参数影响。
- **视频壁纸 / 需要「真·实时」背景** → 把 `live: true` 打开，
  代价是持续抓帧（分辨率高时带宽和 GPU 都明显上升）。
  更省的做法是保持 `live: false`，在关键时机手动 `refresh()`
  （打开面板、切页、切工作区）。
- **想省电、可接受合成器那套参数** → 把 `qmlBackdropBlur` 关掉，
  并把 `quickshell:clockDashboard` 的 `blur` 改回 `true`，
  退回原来的「合成器模糊 + 厚玻璃底色」路径。

## 6. 调参与验证

```bash
# 1. 关掉该命名空间的合成器模糊，确认背景仍然糊（证明是 QML 在糊）
#    ~/.config/hypr/hyprland/rules.lua:
#    hl.layer_rule({ match = { namespace = "quickshell:clockDashboard" }, blur = false })
hyprctl reload

# 2. 重启 quickshell 并打开仪表盘
qs -c end4-pC ipc call clockdashboard toggle

# 3. 截图看面板区域
grim -o HDMI-1 /tmp/s.png
```

判断标准：

- **背景确实被糊**（面板背后的文字变成柔和的色块）→ 成功
- **面板内出现「面板自己」的轮廓** → 自反馈，检查 `opacity` 是否挂了 `backdrop.ready`
- **完全不糊、只有底色** → `hasContent` 没来（走兜底了），检查 `captureSource` 是否为有效输出
- **糊但位置偏了** → `screenOffsetX/Y` 没对齐，确认 `PanelWindow` 是否真的铺满整屏

调参：

| 想要的效果 | 改什么 |
|---|---|
| 更糊 | `blurRadius` ↑（上限 `blurMax`，当前 96） |
| 更透（看清背后颜色） | 面板 `tint` alpha ↓（下限 0.55） |
| 更实（内容更清晰） | 面板 `tint` alpha ↑，或 `MultiEffect.opacity` ↓ |
| 更省 | 保持 `live: false`，只按需 `refresh()` |
