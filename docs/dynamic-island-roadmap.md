# 灵动岛路线图

> **范围**：`modules/ii/dynamicIsland/`
> **最后更新**：2026-09-12
> **历史变更**：[CHANGELOG.md](../CHANGELOG.md)

## 进度总览

| 阶段 | 状态 |
|---|---|
| 一 · 联动性内核 | 完成 |
| 二 · 功能扩展 | 部分（4/7） |
| 三 · 视觉与动效 | 完成 |
| 四 · 稳定性与性能 | 部分（3/4） |

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

### 活动与优先级

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

### 联动机制

- **生命周期**：`ActivityManager.pulse` 统一暂态，`hold` / `release` 处理展开态暂停。
- **场景门控**：`IslandContext.suppressTransient` 为真时抑制瞬态活动。两个来源——
  录屏场景自动静默，以及用户手动开启的专注模式。
- **分组渲染**：声明了 `group` 的任务活动自动挂到右侧副岛，无需改主容器。
- **全局取色**：`IslandPalette` 对外提供 `accentOr` / `progressStart` / `progressEnd`。

## 阶段一 · 联动性内核

状态：完成

- [x] `ActivityManager` 扩展：`options.group` / `options.transient`、`pulse` / `hold` / `release`
- [x] 推导属性 `scene`（`recording` / `media` / `task` / `idle`）
- [x] `IslandContext` 单例：场景门控 + 手动静默
- [x] `IslandPalette` 单例：主色提升为全局
- [x] 副岛布局数据化：group 声明驱动，取代四套硬编码判断

## 阶段二 · 功能扩展

状态：部分完成。按优先级接入，每个都走阶段一的 `pulse` / `context`。

- [x] 亮度
- [x] 隐私指示（麦克风 / 摄像头）
- [x] 蓝牙 / 网络连接
- [x] 电池低电量
- [ ] 倒计时
- [ ] 待办 / 更新
- [ ] 剪贴板

## 阶段三 · 视觉与动效

状态：完成

- [x] 活动切换形变（fade + scale）
- [x] 主色全链路（频谱、进度条、副岛）
- [x] 副岛进出动画（弹簧，显隐跟随宽度）
- [x] 分页指示点过渡（当前页拉长）
- [x] 收起态处理：不淡出内容，溢出交给 clip

## 阶段四 · 稳定性与性能

状态：部分完成

- [x] 轮询合并：`ProcessProbe` 单次 `ps` 覆盖所有任务类型
- [x] 数据源错误边界：cava 失败不重启、ps 空快照保留上次结果
- [x] 歌词 window 差量更新：整数 model + 索引访问，delegate 恒定复用
- [ ] 性能预算与回归基线

## 约定

每个可独立验证的改动：

- **文档**：更新 README 对应章节
- **更新日志**：`CHANGELOG.md` 新增条目
- **i18n**：新增 `Translation.tr()` 文本同步 `en_US.json` 与 `zh_CN.json`，
  其余语言用 `translations/tools/manage-translations.sh` 补齐
- **提交**：单独 commit
