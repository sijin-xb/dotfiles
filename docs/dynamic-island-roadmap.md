# 灵动岛完善路线图

> **状态**：规划中，未实施
> **范围**：`modules/ii/dynamicIsland/`（20 文件 / 2680 行）
> **最后更新**：2026-09-12

## 一、现状

### 架构分层

```
DynamicIslandHost.qml        窗口 + 数据源实例化 + 信号连接
└── DynamicIsland.qml        主容器：尺寸 / 动画 / 手势 / 副岛布局
    ├── IslandTheme.qml      主题 token（颜色 / 字体 / 尺寸 / 动画时长）
    ├── ActivityManager.qml  活动注册表（扁平 map，取优先级最高）
    ├── *Source.qml          数据源：监听系统 → 注册 / 清除活动
    └── *Activity.qml        活动视图：compact / expanded 两态
```

### 活动与优先级

| 活动 | 优先级 | 数据源 | 形态 |
|---|---|---|---|
| volume | 30 | VolumeSource | 瞬态，2s |
| music | 10 | MprisSource | 常驻，双页 |
| package | 8 | PackageSource | 任务，可副岛 |
| download | 7 | DownloadSource | 任务，可副岛 |
| notification | 6 | NotificationSource | 瞬态，4s |
| recording | 5 | RecordSource | 常驻，可副岛 |

### 数据源

- `MprisSource` — MPRIS 播放器
- `CavaSource` — 音频频谱
- `ArtColorSource` — 封面主色量化
- `VolumeSource` / `RecordSource` / `NotificationSource` — 瞬态 / 常驻活动
- `TaskSource` — 通用任务骨架（进程探测 + IPC 上报）

## 二、诊断

### 2.1 联动性缺失（核心痛点）

`ActivityManager` 是扁平 `{type: {payload, priority}}` 映射，`currentType` 取优先级最高者。它只能回答「谁占主岛」，无法表达活动之间的关系。

**a. 活动是孤岛**

每个源独立 `set` / `clear`，互不感知。音乐播放时开始录屏，两者都注册，但没有「音乐 + 录屏」的组合形态——只能靠 `DynamicIsland.qml` 里的副岛逻辑硬贴。新增活动就要再写一段硬编码 companion 判断（现有 `showCompanion` / `showPackageCompanion` / `showNotifCompanion` / `taskCompanionTypes` 已是四套）。

**b. 无上下文门控**

音量变化永远注册 `volume(30)`，即使正在全屏游戏或录屏演示。优先级决定「谁占主岛」，但不决定「该不该出现」。缺少「当前场景」概念来抑制不合时宜的瞬态活动。

**c. 无生命周期语义**

活动结束就是 `clear`，直接消失。缺少：

- 完成反馈（下载完成、录屏结束）
- 进入 / 停留 / 退出三态
- 最小展示时长（快速连发会闪）

**d. 数据不通**

- 封面主色走 `ArtColorSource` → `DynamicIsland.accentColor` → 注入活动，这条链只有音乐用得上。亮度、蓝牙等想用主色得再走一遍。
- 歌词高亮直接耦合在 `MusicActivity` 里读 `lyricsProvider`，不经过 `ActivityManager`。
- 活动之间无法读取彼此状态（如录屏想知道音乐是否在播）。

**e. 状态管理各自为政**

`VolumeSource` / `NotificationSource` 各自持有 `holdOpen` + `hideTimer`；`TaskSource` 有 `manualActive` / `autoActive` 双轨。没有统一的「暂态 / 常驻 / 任务」分类与超时策略。

### 2.2 功能缺口

已安装但未接入灵动岛的 `services/`：

**高价值**

- `Brightness.qml` — 亮度调节，与音量天然对称
- `Privacy.qml` — 麦克风 / 摄像头占用指示，与录屏强相关
- `BluetoothStatus.qml` / `Network.qml` — 连接状态瞬态
- `Battery.qml` — 低电量告警

**中价值**

- `TimerService.qml` — 倒计时
- `Todo.qml` — 待办提醒
- `Updates.qml` — 系统更新
- `Cliphist.qml` — 剪贴板历史

**锦上添花**

- `Weather.qml` / `SongRec.qml` / `EasyEffects.qml` / `ResourceUsage.qml`

### 2.3 视觉与动效缺口

- **活动切换只有 140ms fade**，没有形变过渡。尺寸用弹簧动画（果冻感），但内容是硬切。
- **主色只到歌词高亮**，频谱 `IslandVisualizer` 仍是固定色。
- **副岛进出是硬切**，没有与主岛联动的舒展。
- **展开 → 收起没有内容退场**，`opacity` 直接归零。
- **分页切换**用 `Translate` + 280ms，但页面指示点无过渡。

### 2.4 稳定性与性能缺口

- `TaskSource` 每个实例每 2s 跑一次 `ps | grep`，多任务类型时线性增长。
- `CavaSource` 跟随音乐常开。
- 歌词 `Repeater` 每次 `lyricWindow` 变化全量重建。
- 数据源无错误边界：`FileView` / `Process` 失败时静默。
- `DynamicIsland.qml` 640 行，副岛逻辑与主容器耦合。

## 三、路线图

### 阶段一：联动性内核（地基）

**目标**：让活动之间可组合、可门控、有生命周期。

1. **ActivityManager 扩展**
   - `set(type, payload, priority, options)`：新增 `options.group` / `options.transient` / `options.minDuration`
   - 同 group 活动合并渲染（如所有下载合并为一个进度胶囊）
   - 新增 `pulse(type, payload, duration)`：统一暂态，源不再自带 Timer

2. **IslandContext 单例**
   - 记录当前场景：`idle` / `media` / `recording` / `meeting` / `focus`
   - 数据源注册前查询：`if (IslandContext.suppressTransient) return`
   - 场景由活动组合推导（有 recording → recording 场景）

3. **IslandPalette 单例**
   - 主色从 `ArtColorSource` 提升为全局，任何活动可读
   - 保留 `effectiveAccent` 的亮度下限逻辑

4. **副岛布局数据化**
   - 把四套硬编码 companion 判断收敛为一份 `companionRules`
   - 新活动只需声明规则，不改 `DynamicIsland.qml`

### 阶段二：功能扩展

按优先级接入，每个都走阶段一的 `pulse` / `context`：

1. 亮度（与音量共用形态）
2. 隐私指示（麦克风 / 摄像头）
3. 蓝牙 / 网络连接
4. 电池低电量
5. 倒计时
6. 待办 / 更新
7. 剪贴板

### 阶段三：视觉与动效

1. 活动切换形变（fade + scale + 圆角过渡）
2. 主色全链路（频谱、进度条、副岛）
3. 副岛进出动画（与主岛同步的弹簧）
4. 收起态内容退场
5. 分页指示点过渡

### 阶段四：稳定性与性能

1. 数据源错误边界（失败降级，不静默）
2. 轮询合并（所有 TaskSource 共享一次 `ps`）
3. 歌词 window 差量更新
4. 性能预算与回归基线

## 四、文档 / i18n / 更新日志约定

每阶段完成后：

- **文档**：更新 README「灵动岛」章节；阶段一额外补架构说明
- **更新日志**：README「更新日志」新增条目，标注阶段
- **i18n**：所有新增 `Translation.tr()` 文本同步 `en_US.json` 与 `zh_CN.json`，其余语言用 `translations/tools/manage-translations.sh` 补齐
- **提交**：每个可独立验证的改动单独 commit
