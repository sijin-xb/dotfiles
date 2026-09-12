# 更新日志

> 本文件记录所有历史变更。用法说明见 [README.md](README.md)。


### 2026-09-12（第十六次）

**完善：灵动岛视觉动效与性能**

- 主色全链路：进度条渐变统一走 `IslandPalette`，消除硬编码颜色；封面偏暗时自动生成
  可读的渐变终止色。
- 活动切换加入缩放形变（0.96 → 1），不再是单纯的淡入。
- 左右副岛进出改为弹簧动画，显隐跟随宽度而非直接切换 `visible`，退场过渡可见。
- 分页指示点当前页拉长成胶囊，切换有过渡。
- 新增 `ProcessProbe` 共享进程探测器：单次 `ps` 覆盖所有任务类型，替代原先每个
  `TaskSource` 各自每 2 秒轮询一次；无订阅者时停表。
- 收起态内容退场：早期尝试过让内容在收起时淡出，但这会把 compact 内容一起
  透明化，导致岛变成黑色空条。改为收起后复位透明度，溢出交给 `clip` 裁剪。
- 错误边界：`cava` 异常退出后不再被 `running` 绑定无限重启；`ps` 返回空快照时
  保留上次结果，避免任务活动闪断。
- 修复副岛退场时主岛锚点跳变：锚点恒定指向副岛右缘，边距随宽度收缩。

### 2026-09-12（第十五次）

**新增：灵动岛联动内核 + 亮度 / 隐私指示**

- 新增联动内核：`ActivityManager` 支持 `pulse` / `hold` / `release` 统一暂态生命周期与
  `group` 分组；`IslandContext` 提供场景门控；`IslandPalette` 把封面主色提升为全局状态。
- 新增**亮度**活动（优先级 28），与音量对称，跟随焦点显示器，1.5 秒后自动消失。
- 新增**隐私指示**活动（优先级 4），麦克风 / 摄像头被占用时常驻提示；录屏期间自动收起，
  避免与录屏指示重复。
- 新增**专注模式**：设置 → 背景 → 「静默灵动岛提示」，静默音量 / 亮度 / 通知等瞬态活动。
  也可用 IPC：`qs -c end4-pC ipc call island silent_toggle`。
- 副岛布局数据化：不再硬编码活动类型，声明了 `group` 的任务自动挂到右侧。
- 主色全链路：频谱条、亮度进度条、歌词高亮共用 `IslandPalette` 的封面主色。

### 2026-09-12（第十四次）

**修复：视频壁纸默认后端回退到 Mpvpaper**

- 视频壁纸默认后端从 Wallr 改回 **Mpvpaper**。Wallr 存在视频随机冻结的已知问题（见「视频壁纸后端」章节），暂不推荐作为默认值。
- `Config.qml` 的 `videoBackend` 默认值、`switchwall.sh` 的 jq 回退默认值同步改为 `mpvpaper`。
- 设置页面后端下拉框调整顺序与文案：`Mpvpaper（推荐）` 置顶，`Wallr（可能卡顿）` 标注风险，`Phonto（GPU 视频）` 保留。
- 同步更新 `en_US.json` 与 `zh_CN.json` 翻译；其余语言通过翻译工具补齐。
- 修复「设置里切换视频后端后仍然沿用旧后端」的问题：现在切换会立即重新应用当前视频壁纸，替换掉正在运行的后端进程，不再需要手动重新选一次壁纸。

**使用方式**

- 默认即为 Mpvpaper，无需额外配置。
- 想尝试 Wallr：设置 → 背景 → 视频壁纸后端 → 选择「Wallr（可能卡顿）」；遇到画面定格执行 `pkill wallr && wallr daemon` 恢复。

### 2026-09-12（第十三次）

**修复：Wallr 启用与视频壁纸颜色刷新警告**

- Wallr 现在是视频壁纸默认后端；安装后无需额外改配置，重新选择一次视频壁纸即可启用。
- 修复旧的恢复脚本仍启动 Mpvpaper 的问题；Hyprland 重启后会按照当前后端恢复视频壁纸。
- 删除 `switchwall.sh` 中未使用的 `bc` 光标计算，消除系统未安装 `bc` 时的警告。
- 修复 `applycolor.sh` 和 `materialQT.sh` 仍使用旧 `ii` 配置目录的问题，终端配色刷新不再提前退出。
- 将颜色刷新脚本纳入 chezmoi，避免下次同步或部署时丢失修复。

**使用方式**

- 设置 → 背景 → 视频壁纸后端 → 选择「Wallr（推荐）」。
- 重新选择当前视频壁纸；如果 Wallr 不可用，脚本会自动回退到 Mpvpaper。

### 2026-09-12（第十二次）

**新增：视频壁纸后端切换**

- 新手：在设置 → 背景中可以选择 `Wallr（推荐）`、`Phonto（GPU 视频）` 或 `Mpvpaper（回退方案）`。
- 同一时间只会运行一个视频壁纸后端；Wallr 或 Phonto 未安装时会自动回退到 Mpvpaper，不会让桌面壁纸消失。
- 原有视频缩略图、Matugen 壁纸取色、Quickshell 背景部件和多显示器流程继续保留。

**开发者说明**

- 后端配置字段是 `background.videoBackend`，可选值为 `wallr`、`phonto`、`mpvpaper`。
- 视频切换和恢复脚本位于 `~/.config/quickshell/end4-pC/scripts/colors/switchwall.sh` 及其生成的 `__restore_video_wallpaper.sh`。
- Wallr 使用 background layer；Phonto 默认镜像到所有显示器；Mpvpaper 保留原有逐显示器启动参数。
- 后端切换只影响视频壁纸，静态图片壁纸流程不变。
- 当前系统未安装 Wallr/Phonto 时会自动继续使用 Mpvpaper；安装对应命令后，在设置中重新选择视频后端即可启用。
- 后端依赖不是必需同时安装：Wallr/Phonto 缺失不会影响已有的 Mpvpaper 壁纸。

### 2026-09-12（第十一次）

**新增：GTK Material You 主题整合**

- GTK3 和 GTK4 的 Matugen 模板现在纳入 chezmoi，包含统一的 Material You 配色、圆角控件、侧边栏、开关、进度条、弹出菜单和提示框样式。
- GTK 默认字体统一为 `Google Sans 11`，图标继续使用稳定的 `WhiteSur-dark`。
- 光标主题与 Hyprland 和壁纸取色流程同步，当前壁纸会自动选择匹配的 Catppuccin 光标颜色。
- Qt5/Qt6 的备用配置改为有效的 `MaterialYouDark.colors`，不再引用不存在的 `Darkly.colors`。

**开发者说明**

- GTK3 模板：`dot_config/matugen/templates/gtk-3.0/gtk.css`。
- GTK4 模板：`dot_config/matugen/templates/gtk-4.0/gtk.css`。
- GTK 运行时设置：`dot_config/gtk-3.0/settings.ini` 和 `dot_config/gtk-4.0/settings.ini`。
- 更换壁纸后，`matugen-update.sh` 会重新生成 GTK CSS，并同步 GTK 与 Hyprland 的动态光标。
- GTK3/GTK4 CSS 已用系统 GTK CSS parser 验证通过。

### 2026-09-12（第十次）

**新增：桌面小部件布局编辑器**

- 新手：在桌面空白处右键选择「编辑桌面布局」，即可拖动所有已启用的小部件；网格和中心线会帮助对齐，完成后选择「锁定桌面布局」。位置会自动保存，不需要手动编辑 JSON。
- 音频可视化现在可以拖动。它是全宽部件，横向位置固定，编辑模式下上下拖动即可调整高度。
- 自动布局的小部件也支持临时手动调整；释放鼠标后会保存位置并切换为自由定位。

**开发者说明**

- 右键菜单入口位于 `modules/ii/desktopMenu/DesktopMenu.qml`。
- 通用拖动和持久化逻辑位于 `modules/ii/background/widgets/AbstractBackgroundWidget.qml`；位置写入 `~/.config/illogical-impulse/config.json` 的 `background.widgets.<name>.x/y`。
- `modules/common/widgets/widgetCanvas/WidgetCanvas.qml` 在编辑模式显示网格和对齐参考线。
- 可视化部件移除了覆盖基类定位逻辑的硬编码坐标，首次显示使用底部定位，拖动后保存实际坐标。

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

