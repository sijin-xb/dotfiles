# 灵动岛

> **范围**：`modules/ii/dynamicIsland/`
> **历史变更**：[CHANGELOG.md](../CHANGELOG.md)

栏顶部的动态胶囊：把音量、媒体、通知、任务进度、录屏等瞬时状态收敛到一个位置，
按优先级决定当前显示哪个活动，必要时在主岛两侧展开副岛。

## 文件职责

| 文件 | 职责 |
|---|---|
| `DynamicIslandHost.qml` | 窗口 + 数据源实例化 + 信号连接 |
| `DynamicIsland.qml` | 主容器：尺寸 / 动画 / 手势 / 副岛布局 |
| `IslandTheme.qml` | 主题 token（颜色 / 字体 / 尺寸 / 动画时长） |
| `IslandContext.qml` | 场景门控（自动推导 + 手动静默） |
| `IslandPalette.qml` | 取色中枢（媒体主色 → 全局） |
| `ProcessProbe.qml` | 共享进程探测器（单次 ps 覆盖所有任务） |
| `ActivityManager.qml` | 活动注册表（优先级 + 分组 + 生命周期） |
| `*Source.qml` | 数据源：监听系统 → 注册 / 清除活动 |
| `*Activity.qml` | 活动视图：compact / expanded 两态 |

## 活动与优先级

数值越大越优先，同优先级按注册顺序。

| 活动 | 优先级 | 数据源 | 形态 |
|---|---|---|---|
| volume | 30 | VolumeSource | 瞬态，2s |
| brightness | 28 | BrightnessSource | 瞬态，1.5s |
| connectivity | 25 | ConnectivitySource | 瞬态，2s |
| music | 10 | MprisSource | 常驻，双页 |
| package | 8 | PackageSource | 任务，可副岛 |
| download | 7 | DownloadSource | 任务，可副岛 |
| notification | 6 | NotificationSource | 瞬态，4s |
| recording | 5 | RecordSource | 常驻，可副岛 |
| privacy | 4 | PrivacySource | 常驻 |
| battery | 3 | BatterySource | 瞬态，2.5s |

## 联动机制

- **生命周期**：`ActivityManager.pulse` 统一暂态，`hold` / `release` 处理展开态暂停。
- **场景门控**：`IslandContext.suppressTransient` 为真时抑制瞬态活动。两个来源 ——
  录屏场景自动静默，以及用户手动开启的专注模式。
- **分组渲染**：声明了 `group` 的任务活动自动挂到右侧副岛，无需改主容器。
- **全局取色**：`IslandPalette` 对外提供 `accentOr` / `progressStart` / `progressEnd`。

## 相关

- 桌面歌词与灵动岛共用 `services/LyricsService.qml`，见 [integrations.md](integrations.md)
- 静默开关：设置 → 背景 → 「静默灵动岛提示」，或
  `qs -c end4-pC ipc call island silent_toggle`
