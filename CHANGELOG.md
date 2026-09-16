# 更新日志

> 本文件记录所有历史变更。用法说明见 [README.md](README.md)。

## 2026-09-16（晚）

### 差异层完整性审计 + 设置页预加载修复

**差异层有洞，install.sh 装完不会复现。** 仓库的架构是「chezmoi 只存差异层，
底盘由 install.sh 从 `pctrade/end4-PC` 拉取」，所以任何与底盘不同的文件都必须
在差异层里。实际审计（拿工作树与差异层逐个对照）发现 4 个文件没进去：

| 文件 | 后果 |
|---|---|
| `services/Updates.qml` | pacman 锁竞争修复装完不生效 |
| `services/SystemTheming.qml` | 你的定制装完丢失 |
| `modules/common/widgets/StyledFlickable.qml` | 同上 |
| `modules/ii/wallpaperSelector/LocalWallpaperGrid.qml` | 同上 |

4 个都已补入 `dot_config/quickshell/end4-pC/`。以后新增/修改底盘文件时记得一并
放进差异层，否则「本机好、重装丢」——而且不会有任何报错。

**设置面板的懒加载被自己作废了。** `SettingsContent.qml` 里每个设置页的
`Loader.active` 本来写的是 `Config.ready && (currentPage === index || item !== null)`
—— 只加载当前页、访问过的保留，完全正确。但 `Component.onCompleted` 里有一段
`Qt.callLater` 循环把所有页面 Loader 强制 `active = true`，等于把懒加载整个废掉：
7 个设置页（合计约 7200 行 QML，含 1400+ 行的 `InterfaceConfig` / `BackgroundConfig`）
在 shell 启动时就全部实例化并常驻，而设置面板可能一整天都不开一次。

去掉预热是安全的 —— 搜索跳转本来就处理了「目标页还没加载」的情况
（`onSettingsPageChanged` 里的 `loader.onLoaded` 分支），而 `item !== null` 保证
访问过的页面不会被回收，重复打开不会再付构建成本。

顺带修了 `profileLoader`：它的 `active` 是硬编码 `false`，原来只靠那段强制激活
才加载得到；现在改成 `root.showingProfile || item !== null`，与设置页一致。

### 排查记录：为什么面板不能改成按需加载

一度尝试把 `PanelLoader` 改成「按需创建」（`active` 额外依赖一个 open 标志），
**已撤回** —— 每个面板自己注册了 Hyprland 全局快捷键与 IPC target：

```
modules/ii/overview/Overview.qml        → quickshell:overviewWorkspacesToggle
modules/ii/sidebarLeft/SidebarLeft.qml  → quickshell:sidebarLeftToggle
modules/ii/onScreenKeyboard/…           → quickshell:oskToggle
modules/ii/wallpaperSelector/…          → quickshell:wallpaperSelectorToggle
…（另有 settings / session / mediaControls / region / overlay / screenTranslator / desktopmenu 的 IpcHandler）
```

而快捷键是 `hl.dsp.global("quickshell:xxxToggle")`、面板打开也走 `qs ipc call`。
面板不加载 → 快捷键与 IPC target 都不存在 → 直接失效。所以「启动即实例化」是这套
架构的必然结果，不是疏漏。真要按需加载，得先把这些注册集中到一个常驻的小单例里，
再让面板懒加载 —— 那是独立的一轮重构。

### 内存归因（qs 实测 RSS 964.9 MB）

- **706 MB 是堆上的匿名内存**（Pss_Anon），映射文件只占 81 MB → 主要是 QML 对象图、
  JS 数据与图像数据，不是 mmap 的库。
- 95 个线程，其中 18 组 `qs:gl0` / `qs:gdrv0` + 9 个 `QSGRenderThread`，对应 9 个
  layer surface（4 个 `screenframe` + bar / dock / background / dynamicIsland / 通用）。
- 已排除：壁纸选择器不是大户（`sourceSize` 降采样 + `cache: false` 都做了）。
- 已修：设置页预加载（见上）。**注意 quickshell 的热重载不会释放旧对象图**，
  所以这个改动要在下一次全新启动才看得到效果，原地测量只会看到数值不降反升。

## 2026-09-16（下午）

### 配色链路：加固、去冗余、修三处静默失效

**修复三个「不报错但功能是坏的」问题：**

- **视频壁纸换色会永久挂死**。`switchwall.sh` 用 `ffmpeg` 抽视频首帧当取色源，
  但没加 `-nostdin`；quickshell / 设置面板 / 快捷键都以「常开管道」的形式拉起脚本，
  ffmpeg 会去读 stdin 并一直等下去（实测零 CPU 卡死 2 分钟以上，配色不更新也没有报错）。
  除加 `-nostdin` 外，脚本入口统一 `exec </dev/null`，从根上杜绝这一类问题。
  顺带：缩略图比视频新时直接复用，不再每次换色都重新抽帧（4K 视频省下大头）。
- **`palette.type = auto` 从来没生效过**。`scheme_for_image.py` 依赖 `cv2`，而 venv 里
  没装 OpenCV，脚本一直抛 `ModuleNotFoundError`，被调用方当成「识别失败」静默退回
  `scheme-tonal-spot`。改用 Pillow 重写彩色度指标（`ImageChops` + `ImageStat`，
  都是 C 实现），既去掉了 OpenCV 这个重依赖，也真正让 auto 开始工作。
  另外视频壁纸现在用可推导的缩略图路径做识别，不再拿 mp4 去喂 PIL。
- **SUPER+ALT+T「切换配色策略」是坏的**。`matugen-update.sh` 只从 niri/awww 和
  waypaper 找当前壁纸，两者都是上一套 rice 的残留（niri socket 不存在、waypaper 指向的
  文件已删），必然 `exit 1`。改为优先读 Quickshell 的 `background.wallpaperPath`，
  并把取色与分发整体委托给 `switchwall.sh`（新增 `--index` 参数），
  不再自己调 matugen —— 否则会出现「Quickshell 变了、终端没变」。

**去冗余：**

- `applycolor.sh` 里 kitty 主题渲染出的文件**没有任何消费者**（kitty 读的是 matugen
  直接写的 `~/.config/kitty/current-theme.conf`），`$alpha` 替换也是空操作（模板里
  没有这个占位符）。整块删掉，只保留「发 SIGUSR1 让 kitty 重读配置」。
- 终端配色的 scss 解析原来用 `cut -d ' ' -f2`，依赖「冒号后正好一个空格」这种排版细节，
  排版一变就会静默抽出空值、把终端刷成一片黑。换成 `render_terminal_theme.py`：
  显式解析 + 替换，**替换不完整就报错退出**，绝不把半成品推给终端。
- `switchwall.sh` 删掉未使用的 `MATUGEN_DIR`、`post_process` 的三个未用参数，
  以及只为它们服务的 `hyprctl monitors` 调用；`set_wallpaper_path` /
  `set_thumbnail_path` / `set_accent_color` 三处重复的原子写合并成一个函数。
- `matugen-update.sh` 里 gsettings 分支先 set 再反向 set 同一个键（净效果靠最后一次
  覆盖），且与 `switchwall.sh` 的 `pre_process` 完全重复 —— 全部删掉，统一由后者处理。

**提升健壮性：**

- matugen 是「全有或全无」的：任一模板的 `input_path` 不存在，整轮渲染直接失败，
  所有应用一起停在旧配色。新增 `filter_matugen_templates.py` 做调用前预检，
  缺哪个跳过哪个，并在日志 / 通知里点名缺失项。
- 加依赖自检（jq / matugen 缺失时给出可执行的安装命令）、matugen 与
  `generate_colors_material.py` 的退出码检查与失败通知。
- `ILLOGICAL_IMPULSE_VIRTUAL_ENV` 未导出时退回默认 venv 路径并显式 export，
  让两个 python 脚本的 shebang 也能拿到。
- KDE/Qt 配色助手在 Hyprland 下会因 KWin 不存在而抛 DBus 异常刷屏，
  输出改为归档到 `~/.cache/quickshell/kde-colors.log`，日志不再被污染。

**准确性：**

- **同源取色**：`generate_colors_material.py` 有自己的取色算法（`Score.score`），
  与 matugen 的 `--source-color-index` 不是一回事 —— 两边各挑各的，终端 16 色和
  Quickshell 的 M3 就会来自同一张图的不同颜色。现在直接把 matugen 选定的源色
  （`[templates.kde_colors]` 已写入 `color.txt`）通过 `--color` 喂给
  `generate_colors_material.py`，两边同源；`--cache` 也不再互相覆盖同一个文件。
- `get_type_from_config` / `get_accent_color_from_config` 的 `|| echo 默认值` 从来不生效
  （jq 键不存在时输出 `null` 且退出码为 0），改成 `// 默认值`。

### btop 配色适配

`btop.conf` 一直指向 `ii-auto`，但 `~/.config/btop/themes/ii-auto.theme` 是个**没有任何
脚本生成的静态死文件** —— 换壁纸后 btop 配色永远不变。现在：

- 新增 `dot_config/matugen/templates/btop.theme`（`[templates.btop]` 注册在
  `config.toml` / `config.toml.orig`），用 M3 语义 token 映射 btop 的 16 个槽位，
  与 kitty / foot / alacritty 用同一套 token 对应关系，终端 ANSI 色和 btop 曲线同色系；
- 补齐 btop 1.4 的 `graph_text` / `meter_bg` 两个槽位；
- 修正 4 个内存/磁盘仪表的渐变方向（原先终点用 `*_container`，暗色模式下反而更暗，
  与「越满越醒目」相反）；
- `post_hook` 发 **SIGUSR2**（等价界面里的 Ctrl+R，实测确认是热重载配置），
  正在运行的 btop 立刻换色，不需要重启。

### 模板入仓（兼容性）

`config.toml` 引用 22 个模板，仓库里只跟踪了 8 个；另有 `switchwall.sh` 依赖的
`kde/kde-material-you-colors-wrapper.sh` 也未入仓。**全新安装时 matugen 会因为
input_path 缺失整体失败**，等于零配色。缺的 12 个模板与 kde wrapper 已全部纳入
`dot_config/matugen/`。

### 移除桌宠

`modules/ii/pet/`（`Pet.qml` 2009 行 + `PetState.qml` + `PetWindow.qml`，合计约 2288 行）
与 `scripts/pet/petMetrics.sh` 整体删除：`shell.qml` 里的 `PetWindow` 实例与 import、
`Config.options.petEnabled`、设置 → 桌面 → 小部件里的「Desktop pet (bongo cat)」开关、
install.sh / 帮助文案里的相关描述一并清掉。`scripts/pet/winStats.sh` 保留 ——
总览的窗口统计卡片在用它。

### 卡顿：pacman 装包时输入延迟

`services/Updates.qml` 每 2 小时执行 `checkupdates` + `yay -Qua`。pacman 装包时它持有
`/var/lib/pacman/db.lck`，这两个命令会一起阻塞在锁上 —— 一个检查能挂满整轮安装，
期间白占进程和 IO，正是「后台装软件时桌面发卡」的来源之一。现在：

- 锁文件存在时直接沿用上次结果，不去抢锁；
- `timeout` 兜底，helper 卡住不会留进程常驻；
- 结果落盘缓存（`~/.cache/quickshell/updates-count`）；
- AUR helper 改为 paru 优先（`paru -Qua` 比 yay 快不少，与 `install.sh` 的选择一致）。

## 2026-09-16

### 锁屏：Caelestia 风格移植与收尾

新增 `modules/ii/lock/caelestia/`（28 个 QML，约 2000 行）：方块展开动画、分色大时钟、
Material 3 形状形变的密码框、媒体卡、资源卡、歌词卡。视觉 1:1 来自 `qt6-m3shapes-git`
（与 Caelestia `flake.nix` pin 的 commit 一致）与 Caelestia QML 插件（`Caelestia.Config`
提供 Tokens / AnimCurves）；配色零转换（`Colours.palette.m3*` 与 `Appearance.m3colors.m3*` 同名）。

底层复用 end4-pC：认证走 `LockContext`（PAM + 指纹 + keyring），媒体走 `MprisController`，
资源走 `ResourceUsage`，歌词走 `LyricsService`。**歌词卡是本仓库独有** —— Caelestia 锁屏
本身没有歌词。旧 `SerpantinumLockSurface.qml` 完整保留，`Lock.qml` 一行即可切回。

收尾修正：

- `CaelestiaLockSurface`：屏幕高度改取 `root.height`（不再走 `parent.screen` 父链，
  否则展开尺寸算成 0、三栏布局塌缩到右下角）；背景换成真实模糊壁纸
  （`MultiEffect blurMax 64` + `m3scrim` 25%）；圆角/字体/配色统一走 `Appearance`。
- `Resources.qml`：三个 `MaterialShape`（Pentagon / Slanted / Gem）视觉占比不同导致高低不齐，
  统一取 `Math.min(width, height)` 作为形状尺寸并 `anchors.centerIn`。
- i18n 补全 `Unlocking…` / `Enter your password` / `Nothing playing` / `Try playing some music!`。
- `docs/lockscreen.md` 补「屏幕尺寸」「视觉细节」「i18n」「依赖」四节，删除过时的 `screen` 传递描述。

### install.sh：7 步流程 + 依赖补齐 + 字体

安装流程 6 步 → 7 步，新增 `[4/7] Caelestia QML 插件`：clone `caelestia-dots/shell`
到 `~/src/caelestia-shell`，编译到 `build/qml`，产物由 Hyprland `execs.lua` 与 fish
`config.fish` 通过 `QML2_IMPORT_PATH` 自动加载（目录不存在时这两处自动跳过）。
该步骤**失败即中断**，缺 cmake/ninja、clone 失败、CMake 配置失败、编译失败都 `die`
并给出手动重试命令；`build/qml/Caelestia/*.so` 已存在则跳过编译。移除了
`CAELESTIA_PLUGIN=0` 跳过开关与「可选」措辞。

依赖调整：

- `PACMAN_PKGS` 追加 `spirv-tools`（插件 shader 编译调用 `spirv-opt`）、
  `aubio libpipewire libqalculate lm_sensors fftw`；AUR 循环加入 `libcava` 与 `qt6-m3shapes-git`。
- 新增终端字体：`ttf-jetbrains-mono-nerd`（kitty 的 `font_family` 所需，含 Nerd 图标）、
  `ttf-nerd-fonts-symbols`，中文 / emoji 兜底的 `noto-fonts` / `noto-fonts-cjk` / `noto-fonts-emoji`；
  `[6/7]` 末尾加 `fc-cache -f` 兜底（pacman 装字体包本身有 hook，这步让手动放进
  `~/.local/share/fonts/` 的字体重跑脚本后也生效）。
- **不引入** `caelestia-shell` / `caelestia-meta` / `caelestia-cli`：脚本只备齐编译
  插件所需的库，运行时逻辑仍走 end4-pC 自身服务。

`[1/7]` 默认改为 `pacman -S --needed`，只安装缺失的包，不再无条件滚动整个系统；
需要全量升级时用 `FULL_UPGRADE=1 ./install.sh install`。

### install.sh：TUI 与 Caelestia 编译修复

- **TUI 乱码**：`draw_line` 用 `tr ' ' '─'` 在多字节 locale 下按字节替换，
  把 `─`(E2 94 80) 拆成 3 个字节产生非法 UTF-8；`draw_header` 用
  `cut -c$((...+${#title}))`，`${#title}` 是字节数而 cut 也按字节切，中文标题被从字符中间切开。
  分别改为按字符循环打印、不截断输出。
- **TUI 卡死**：`set -euo pipefail` 下，`for p in ...; do [[ -e ... ]] && cnt=$((cnt+1)); done`
  末次 `[[ ]]` 失败会让 for 返回 1 直接杀掉脚本；且 `cmd_install` 内部的 `die`(=exit)
  会连带把 TUI 一起 exit 掉。改为 `if` 语句 + TUI 调用各 `cmd_*` 时用子 shell 包裹 + `set +e`
  单独处理返回码，主菜单 `read` 加 EOF 保护。
- **`read -i` 报错**：`detail_archive` 里 `read -r -i "$out_path" out_path` 依赖 readline，
  未加 `-e` 时行为未定义。改为手动提示 + 空则保留默认值。
- **Caelestia 编译 FATAL**：`--depth=1` clone 不带 tag，上游 CMakeLists 用
  `git describe --tags` 取版本失败即 `FATAL_ERROR`。脚本改为 clone 后 `git fetch --tags`
  并显式传 `-DVERSION=`；上游 CMakeLists 同时改为探测失败时 `WARNING` + 回退
  （`VERSION=0.0.0` / `GIT_REVISION=unknown`）。

### 文档：README 瘦身 + docs/ 拆分

根 README 从 653 行降到入口页（包含内容 / 安装 / 命令 / 快捷键 / 目录结构 / 链接），
深度实现笔记移出到 5 篇 docs：`appearance.md`（视频壁纸后端 + 视差）、`lockscreen.md`、
`widgets-layout.md`、`integrations.md`（SPlayer + fcitx5-rime）、`troubleshooting.md`。
这样 README 只回答「是什么 / 怎么装 / 怎么用」，「为什么这么实现」归 docs，
「改了什么」归 CHANGELOG。README 致谢段如实列出 `qt6-m3shapes-git` 与 Caelestia QML 插件依赖。

## 2026-09-15

### 壁纸视差补全（视频壁纸 + 全工作区 + 光标隔离 + 缩放/曲线）

- **视频壁纸视差**：视频由 mpvpaper 在后景层绘制，Quickshell 碰不到它的图层，
  改为走 **mpv 的 JSON IPC** —— `switchwall.sh` 启动 mpvpaper 时加
  `input-ipc-server=~/.cache/quickshell/mpvpaper/mpvpaper-<显示器名>.sock`，
  Quickshell 连上后设置 `video-zoom` / `video-align-x` / `video-align-y`。
  `video-zoom` 传 `log2(parallaxZoom)`，`video-align` 传归一化到 `-1 ~ +1` 的偏移。
- **工作区视差覆盖全部工作区**：旧实现用 `(工作区号 - 1) % 概览列数` 定位，
  概览列数是 5，所以第 6 个工作区开始位置重复。改为按工作区总数线性映射，
  总数取「设置值 / 已出现的最大工作区号 / 概览列数」的最大值，新增「工作区数量」滑杆。
- **光标跟随只作用于壁纸层**：`WidgetCanvas` 之前也叠加了光标偏移导致鼠标一动
  桌面部件跟着抖；现在部件只跟随侧栏开合做景深位移。
- **缩放逻辑**：开启侧栏平移时自动把 `workspaceZoom` 提升到「可移动余量 ≥ sidebarShift」；
  壁纸按「显示尺寸 × 缩放」解码（`sourceSize`），8K 壁纸不再整幅载入内存；
  **桌面部件坐标系修正** —— 部件画布是屏幕尺寸、不随壁纸缩放，之前一直按
  「壁纸缩放空间」定位，`y = -1` 的部件会被推到屏幕外，现统一改回屏幕坐标系。
- **过渡动画**：时长默认 400ms（Hyprland 的 `workspaces` 是 700ms，滚轮连续切工作区时
  视差追不上切换就是卡），新增「工作区过渡时长」滑杆（200~1400ms）。

**踩坑：`Easing.BezierSpline` 的 `bezierCurve` 必须给 3 个控制点（6 个值，末点 `1, 1`）**。
按 CSS 写法只给 4 个值 `[0.1, 1.0, 0.0, 1.0]` 时 Qt 不报错，而是**静默退化成匀速直线**
（无窗口 QML 探针实测：400ms 动画到 192ms 才走到 50%，同样条件下 OutCubic 已到 88%）。
已改用 `Easing.OutCubic`。

### 修复：静态壁纸开启视差会被放大

平移视差需要可移动余量，原实现直接 `scale = parallaxZoom`，所以开启视差就会永久裁切放大
壁纸（强度 1.15 即放大 15%）。新方案：**静态壁纸本体始终 scale=1**；后面垫一层同一张壁纸
的 `FastBlur` 缓存层（四周额外铺 80px 防止模糊暗边），平移露出来的边缘显示虚化的同款画面。
模糊层静止不动，`layer.enabled` 可缓存，只在换壁纸时重渲染。锁屏 GaussianBlur 与
用户/概览 FastBlur 两层残留的 `parallaxZoom` 一并移除。设置文案 `工作区缩放` →
`工作区视差强度`。视频壁纸是 mpvpaper 独立图层，无法垫模糊副本，仍需 `video-zoom` 留余量。

### 性能：Hyprland 事件风暴 + ResourceUsage 采样

- **事件风暴**：`services/HyprlandData.qml` 对**每一个** Hyprland 事件都调 `updateAll()`，
  而一轮 `updateAll()` 要起 5 个 `hyprctl` 子进程（合计约 20ms CPU）。一次工作区切换
  会收到近十个事件，主线程被进程创建拖住。修复：按事件名只刷对应数据，并用 40ms 定时器
  把同一波事件合并成一次刷新；`openlayer`/`closelayer` 直接跳过。实测 10 个事件从
  50 个子进程降到 2 轮刷新。
- **ResourceUsage**：采样定时器写成 `interval: 1` 且 `repeat: true` —— 每秒上千次
  reload `/proc` + 正则匹配 + 重建历史数组。改为读取
  `Config.options.resources.updateInterval`（默认 3000ms），空闲 CPU 3.0% → 0.8%。

### 功能：设置面板搜索框

侧边栏（导航栏展开时）加搜索输入框，输入即列出匹配的页面与小节，点击跳转并自动滚动定位。
索引由 `scripts/settings/build-search-index.py` 扫描各页的 `ContentSection/ContentSubsection`
标题生成（10 页 / 98 节），存为 `modules/ii/settings/settingsSearchIndex.json`；运行时用
`Translation.tr` 翻成当前语言再匹配，中英文都能搜。跳转复用已有的
`GlobalStates.settingsPage = "页面:小节"` 深链，没有新增导航机制。

坑：`StyledTextInput` 的根是 `TextInput`，**不支持 `placeholderText`**；
要占位符得用 `MaterialTextField`（`TextField` 子类）。

### 功能：SPlayer 歌词联动

桌面歌词接入 SPlayer 的 WebSocket（设置 → WebSocket 服务，默认 25885）。协议从 SPlayer
的 `app.asar` 里逆出来（WS 是单向广播）：`welcome` / `song-change` / `lyric-change` /
`progress-change` / `status-change`；其中 `lyric-change` 的 `lrcData`/`yrcData` 是行数组，
每行含 `startTime`/`endTime`/`words[].word`/`translatedLyric`，时间单位 ms。

- 新增 `scripts/desktopLyrics/splayer-ws.py`：纯标准库的极简 WS 客户端，归一成每行
  一个 JSON 写到 stdout，断开后自动重连。
- QML 侧复用现有 `lyricLines`/`currentTime`/`isPlaying`，下游无需改动；**只有真收到 WS
  歌词才接管**，否则保留 MPRIS + 酷狗兜底；接管后停掉酷狗抓取与 MPRIS 精同步。
- **修复**：`lyric-change` 的 `lrcData`/`yrcData` 在只有 LRC（没有逐字歌词）的歌上是
  **纯文本 LRC 字符串**而不是行数组，桥接脚本只认数组 → 解析成空、歌词完全不显示
  （《unravel》即属此类）。已支持字符串形式（按 `[mm:ss.xx]` 解析，结束时间取下一行
  开始时间）。另加 `--debug <file>` 转储原始 WS 报文。

### rime：`/` 符号候选框

`rime_ice.custom.yaml` 把 `half_shape` 的 `/` 由单值 `'/'` 改成 48 项常用符号列表，
按 `/` 弹候选框，`,` / `.` 翻页。librime 的 `PunctTranslator` 用 `FifoTranslation`，
**列表顺序就是候选顺序**，所以「权重」= 列表顺序。已按中文书写频率重排 49 项：
第一页（`page_size = 9`）为 `/ ， 。 、 ？ ！ ： ； "`，日常写中文不用翻页；
第二页放 `' ' （ ） 《 》 —— …… ·`，之后依次是数学符号、箭头图形等。半角 `/` 保留
在首位，打 `/` 后按空格即可上屏字面量斜杠，写路径/URL 不受影响。

原理（librime `gear/punctuator.cc`）：取到标点定义后只有**单值映射**会立即上屏，
列表型映射只列候选。

**坑一**：必须用 `punctuator/half_shape/+` 这种扁平路径。写成嵌套结构
`punctuator: { half_shape: ... }` 会把整个 `punctuator` 节点替换掉，v 模式符号表（266 项）
和全角标点会一起消失。
**坑二**：键名 `/` 不能写在路径里（会被当成路径分隔符），只能放在值里。
校验：`rime_deployer --build` 后检查 `build/rime_ice.schema.yaml`。

### 修复：设置页下拉框吞字 + 光标开关

- **下拉框吞字**：`ConfigComboBox` 的 `fieldWidth` 同时决定按钮和弹窗宽度
  （`StyledComboBox` 里 `popup.width = root.width`），而视频壁纸后端 / 过渡动画把它设成了
  **50px**，按钮和弹窗文案全被截断。修复：控件层按模型里最长的文案用 `TextMetrics`
  量一次宽度，`fieldWidth` 降级为下限 —— 所有页面一起修好，换语言也不会整段被吞。
- **光标开关坏了**：`InterfaceConfig.qml` 的开关绑到
  `appearance.wallpaperTheming.enableCursor`，但 `Config.qml` 里没有这个键 → 绑到 undefined
  （日志报 `Unable to assign [undefined] to bool`），点了没反应。该键实际由
  `generate_cursor_theme.py` 读取（缺键按启用处理），所以脚本一直在跑，只是设置里关不掉。
  已补上 `property bool enableCursor: true`。

### 记录：Hyprland 0.56 Lua 配置模式的两个坑

- `hyprctl dispatch <dispatcher> <args>` 的传统写法**不再可用**：0.56 会把参数整体当
  Lua 表达式解析，报 `')' expected near ...`。必须写 Lua 形式，如
  `hyprctl dispatch 'hl.dsp.global("quickshell:lock")'`。
- `hyprctl keyword <name> <value>` 直接报
  "keyword can't work with non-legacy parsers. Use eval."，要改用 `hyprctl eval`。
- 排查手法：`hyprctl eval` 可执行任意 Lua（返回 ok），配合 `io.open("/tmp/x","w")`
  把结果写文件，就能安全探测 API 是否存在。

### 审查：matugen 取色 + install.sh

- **matugen 取色**：用同一张壁纸 + 同参数重算，主色与已生成文件完全一致
  （`#d6bbfb` / `#cec2da` / `#f2b7c2` / `#151218`），各应用文件时间戳一致 ——
  **取色管线是确定性的，没有偏差**。顺带发现：8K 壁纸跑一次 matugen 约需 2 分钟
  （每次换壁纸都会等这么久），换壁纸时的体感延迟主要来自这里。
- **install.sh 审查**：
  - 全新安装会丢可执行位：`scripts/colors/` 下同时存在 `switchwall.sh` 与
    `executable_switchwall.sh`（前者是同步时漏加 chezmoi 前缀留下的重复），
    安装器只按 `executable_` 前缀恢复执行位，两个同名目标互相覆盖。已删除无前缀那份。
  - quickshell 底盘 clone 会硬失败：`git clone ... "$QS_BASE"` 在目录已存在且非空时报错，
    配合 `set -e` 直接中断。改为先克隆到临时目录再 `cp -a` 合并。
  - 快照文件数统计会输出两行：`grep -cv '/$' || echo 0` 在计数为 0 时 `grep -c` 本身
    已打印 `0` 但返回 1，于是又追加一个 `0`。改为 `grep -v '/$' | wc -l`。

## 2026-09-14

### 灵动岛：动画调优 + 下载进度 + 展开态

- **动画**：`IslandTheme.expandedSizes` 中 `recording`/`battery` 的展开尺寸仍是
  `{ h: 37, r: 19 }`（与 compact 相同），展开态内容被 `clip` 裁掉；改为
  `{ w: 320, h: 120, r: 28 }`。SpringAnimation `epsilon` 0.5→0.1（大尺寸跳变时不再有
  "咔"一下）；内容进场缩放 0.96→0.92、easing `OutCubic`→`OutBack`。
- **下载进度**：新增 fish 包装函数 `pacman`/`yay`/`paru`/`curl`/`wget`，解析输出百分比，
  通过 `qs ipc call island task_progress` 上报到灵动岛。`pacman` 包装自动判断需要 root
  的操作（`-S`/`-U`/`-R` 且非只读子项）并加 `sudo`，解决 `sudo pacman` 绕过函数的问题。
  `DownloadSource` 关掉 curl/wget 自动探测（后台脚本的 curl 会让下载胶囊乱闪）；
  `TaskSource.begin` 在任务进行中再次调用只换标签不重置进度。
- **通知头像**：`NotificationSource` 传 `image`/`appIcon`，`NotificationActivity` compact
  与 expanded 双态直接复用 `NotificationAppIcon` 组件，用 `implicitSize` 控制尺寸
  （22px/44px），避免 `scale` 双重缩放导致头像只显示 ~13px。
- **展开态补齐**：`RecordingActivity`（脉冲点 + 录制提示 + 放大计时）、
  `BatteryActivity`（电量条 + 低电量红色警示），参考 macOS Dynamic Island HIG。

### 性能：pacman 装包后卡顿 + OBS 录屏时打字延迟

- **pacman 卡顿**：`services/AppSearch.qml` 的桌面文件去重用 `filter` 套 `findIndex`，
  是 O(n²)。pacman 写入 `.desktop` 触发 `DesktopEntries.applications` 更新，整条响应式链
  在主线程同步重算，1000+ 桌面文件 ≈ 百万次比较。修复：去重改用 `Set` 一次遍历（O(n)）；
  拼音查找的 `list.find` 换成预建的 `entryById` Map（用 Map 规避 `constructor` 等
  原型链键碰撞）。
- **OBS 打字延迟**：`services/LauncherSearch.qml` 的 `results` 绑定逐键同步执行全量 fuzzy
  搜索 + 为每个匹配结果 `createObject` 建 QObject，无防抖。修复：新增 `debouncedQuery`
  （60ms Timer），`results` 跟随它；`query` 仍即时；应用结果截断到 50（渲染只展示前 15）。

### 修复：Super+滚轮一次切两个工作区

`dwindle` 等非滚动布局下，`Super + 鼠标滚轮` 一次会跳过两个工作区。根因：默认模板
`hyprland/keybinds.lua` 已注册 `SUPER + mouse_up/down` 切换工作区；后加载的
`custom/keybinds.lua` 又注册了相同按键的布局感知绑定。`hl.bind` 不会自动替换旧绑定，
两套都会执行。修复：在动态滚轮绑定前 `hl.unbind("SUPER + mouse_up")` /
`hl.unbind("SUPER + mouse_down")`，`CTRL + SUPER` 组合不受影响。
同时 `scrolling` 布局下 `Super + 滚轮` 改为在当前工作区内切换窗口（`layout focus r/l`）。

### 修复：日文歌桌面歌词不显示中文翻译

`kugou_lyrics.py` 的 `download_lyrics()` 只遍历 `candidates[:2]` 并返回第一个能解密的候选。
Kugou 对同一首歌返回多个 KRC 变体，排在前面的只内嵌罗马音块，中文翻译块排在后面，
于是永远命中罗马音版本，QML 侧 `parseTranslations()` 正确丢弃罗马音块 → 翻译行因此为空。

修复：新增 `classify_translation_block()` 三态分类（`cjk` / `romaji` / `none`），
`download_lyrics()` 扫描前 6 个候选，优先返回带 CJK 翻译的版本。缓存自愈：旧的罗马音
缓存视为过期；若上游确实只有罗马音，写入 `[kugou:no-cjk-translation]` 标记避免反复重取。

### 修复：设置面板「界面」页无法向下滚动

该页把 `Repeater` 直接嵌进 `GroupedList`。`GroupedList` 的 `default property list<Item> items`
只把 `Repeater` 本身算作一个 item，而 `Repeater` 没有 `implicitHeight`，展开出的
`ConfigSwitch` 高度完全不计入 `implicitHeight`，`maxY` 被压到接近 0，向下滚动被夹回原位。
改为 `ColumnLayout` + `Repeater` 手写分组列表，每个 delegate 显式声明 `implicitHeight`。

顺带 i18n：补入 `Applications`、`matugen.%1`、`Terminal options` 及 matugen 模板说明长句，
共 4 个键覆盖 14 个语言文件；修正 `zh_CN.json` 被误改为 2 空格缩进导致的整文件重排。

## 2026-09-13

### 修复：登录时 Quickshell 自动启动导致整个桌面卡死

Hyprland 登录后自动拉起 Quickshell，随即整个合成器无响应，连 tty 都切不进去。
根因：`execs.lua` 启动 Quickshell 时注入了 `QT_IM_MODULE=fcitx`、`GTK_IM_MODULE=fcitx`、
`QT_WAYLAND_TEXT_INPUT_PROTOCOL=zwp_text_input_v3` 等一整套输入法环境变量，
该组合与 layer-shell 存在已知死锁。修复：去掉那套环境变量，改为干净的 `qs -c $qsConfig`
（输入法环境已由前一行 `dbus-update-activation-environment` 全局设置）。
同时移除 `SUPER + I` 的「下一工作区」绑定，让位给设置面板切换。

### 修复：matugen `config.toml` 丢失光标钩子与部分模板块

`config.toml` 此前丢失了 `post_hook`（光标主题重渲染钩子）以及 `[templates.yazi]`、
`[templates.obs]`、`[templates.vscode]` 三块，换壁纸后光标颜色不再跟随主色。
从 `config.toml.orig` 恢复完整内容。

### 调整：光标尺寸 32 → 24

`custom/env.lua` 的 `XCURSOR_SIZE` / `HYPRCURSOR_SIZE` 从 32 改为 24；同步 `gsettings`
的 `cursor-size` 为 24，GTK 应用读到的尺寸与 Hyprland 一致（此前 Hyprland 24 /
`gsettings` 32，光标大小表现不稳定）。

### 调整：壁纸选择器改为自屏幕底部滑入 / 滑出

开合动画由「中心缩放 + 淡入」改为「向下位移 + 淡入」，入场 520ms / 退场 380ms。
`rules.lua` 中该图层由 `animation = "slide top"` 改为 `no_anim`，避免 Hyprland
在合成器层再做一次顶部滑入、与 QML 动画叠加。

## 2026-09-12

### 视频壁纸后端：切换 / Wallr 启用 / 回退 Mpvpaper

- 设置 → 背景中可选择 `Wallr（推荐）`、`Phonto（GPU 视频）` 或 `Mpvpaper（回退方案）`。
  同一时间只运行一个后端；Wallr 或 Phonto 未安装时自动回退 Mpvpaper。
- 后端配置字段是 `background.videoBackend`（`wallr` / `phonto` / `mpvpaper`）。
  切换会立即重新应用当前视频壁纸，替换掉正在运行的后端进程，不再需要手动重新选一次。
- 修复旧的恢复脚本仍启动 Mpvpaper 的问题；Hyprland 重启后会按当前后端恢复视频壁纸。
- 删除 `switchwall.sh` 中未使用的 `bc` 光标计算，消除未安装 `bc` 时的警告。
- 修复 `applycolor.sh` / `materialQT.sh` 仍使用旧 `ii` 配置目录的问题；
  颜色刷新脚本纳入 chezmoi。
- **最终回退**：视频壁纸默认后端从 Wallr 改回 **Mpvpaper**。Wallr 存在视频随机冻结的
  已知问题，暂不推荐作为默认值。设置页顺序：`Mpvpaper（推荐）` 置顶，
  `Wallr（可能卡顿）` 标注风险，`Phonto（GPU 视频）` 保留。

### 灵动岛：联动内核 + 亮度/隐私 + 视觉动效

- 新增联动内核：`ActivityManager` 支持 `pulse` / `hold` / `release` 统一暂态生命周期与
  `group` 分组；`IslandContext` 提供场景门控；`IslandPalette` 把封面主色提升为全局状态。
- 新增**亮度**活动（优先级 28），与音量对称，跟随焦点显示器，1.5 秒后自动消失。
- 新增**隐私指示**活动（优先级 4），麦克风 / 摄像头被占用时常驻提示；录屏期间自动收起。
- 新增**专注模式**：设置 → 背景 → 「静默灵动岛提示」，也可用 IPC
  `qs -c end4-pC ipc call island silent_toggle`。
- 副岛布局数据化：声明了 `group` 的任务自动挂到右侧。
- **视觉动效**：主色全链路（进度条渐变统一走 `IslandPalette`，封面偏暗时自动生成
  可读的渐变终止色）；活动切换加入缩放形变（0.96 → 1）；左右副岛进出改为弹簧动画，
  显隐跟随宽度而非直接切 `visible`；分页指示点当前页拉长成胶囊。
- **性能**：新增 `ProcessProbe` 共享进程探测器，单次 `ps` 覆盖所有任务类型，
  替代原先每个 `TaskSource` 各自每 2 秒轮询；无订阅者时停表。
- **错误边界**：`cava` 异常退出后不再被 `running` 绑定无限重启；`ps` 返回空快照时
  保留上次结果。
- 收起态内容退场：早期尝试过让内容在收起时淡出，但会把 compact 内容一起透明化
  导致岛变成黑色空条；改为收起后复位透明度，溢出交给 `clip` 裁剪。
- 修复副岛退场时主岛锚点跳变：锚点恒定指向副岛右缘，边距随宽度收缩。

### 灵动岛：连接状态 + 电池提示

- 新增 `connectivity` 活动（优先级 25）：蓝牙 / WiFi 连接与断开提示，2 秒后消失。
- 新增 `battery` 活动（优先级 3）：插拔电源、低电量、充满提示；台式机无电池时整体跳过。
- 两者都走 `IslandContext` 门控，专注模式或录屏时静默；启动时的初始状态填充不算事件。

### 灵动岛：歌词窗口差量更新

歌词 `Repeater` 的 model 从「每次重建的数组」改为固定槽位数（5），delegate 恒定复用，
窗口滑动时只更新属性，不再销毁重建整棵对象树（含内层逐字 Repeater）。槽位到歌词下标的
映射由 `lyricIndexAt(slot)` 计算；行暗度改用槽位下标直接计算，去掉每次渲染的
`Array.indexOf` 扫描；`seekAtY` 改用 delegate 自身携带的行数据。

### 修复：浏览器播放网页视频被识别为音乐

灵动岛的 `MprisSource` 原先直接遍历 `Mpris.players.values`，绕过了 `MprisController` 的
去重逻辑。Chrome 视频会同时经原生 bus 与 `plasma-browser-integration` 上报两次，
而 MPRIS 协议本身不区分音频与视频，于是看视频时弹出音乐岛。改为走 `MprisController`
的已过滤列表，新增可配置的浏览器过滤（默认开启）与设置项「忽略浏览器媒体」。

`MprisController.activePlayer` 增加准入校验：被过滤掉的播放器不再作为回退值。
浏览器识别用**词边界正则**而非子串匹配，避免 `edge` 误命中 `knowledge` 这类词。
修正上游 `isRealPlayer` 的浏览器去重：它按 `dbusName` 前缀判断，而所有 Electron 应用的
bus 名都是 `org.mpris.MediaPlayer2.chromium.instanceN`，于是 MoeKoeMusic / Vesktop 这类
真正的播放器被一并过滤。改用身份判定。

### 新增：GTK Material You 主题整合

GTK3 和 GTK4 的 Matugen 模板纳入 chezmoi，包含统一的 Material You 配色、圆角控件、
侧边栏、开关、进度条、弹出菜单和提示框样式。GTK 默认字体统一为 `Google Sans 11`，
图标继续使用 `WhiteSur-dark`。光标主题与 Hyprland 和壁纸取色流程同步。
Qt5/Qt6 的备用配置改为有效的 `MaterialYouDark.colors`，不再引用不存在的 `Darkly.colors`。

模板路径：`dot_config/matugen/templates/gtk-3.0/gtk.css` 与 `gtk-4.0/gtk.css`；
运行时设置：`dot_config/gtk-3.0/settings.ini` 和 `gtk-4.0/settings.ini`。
更换壁纸后 `matugen-update.sh` 会重新生成 GTK CSS。

### 新增：桌面小部件布局编辑器

桌面空白处右键选择「编辑桌面布局」，即可拖动所有已启用的小部件；网格和中心线帮助对齐，
完成后选择「锁定桌面布局」。位置自动保存到 `~/.config/illogical-impulse/config.json`
的 `background.widgets.<name>.x/y`，不需要手动编辑 JSON。音频可视化也可拖动
（全宽部件，横向位置固定，编辑模式下上下拖动调整高度）。自动布局的小部件也支持临时
手动调整；释放鼠标后保存位置并切换为自由定位。

入口：`modules/ii/desktopMenu/DesktopMenu.qml`；通用拖动与持久化逻辑：
`modules/ii/background/widgets/AbstractBackgroundWidget.qml`；
编辑模式网格：`modules/common/widgets/widgetCanvas/WidgetCanvas.qml`。

### 锁屏：Serpantinum 风格三栏布局

锁屏改为三栏布局：居中大时钟 + 左翼系统监控 / 中翼认证 / 右翼歌词、通知、媒体。
交互结构参考 [Serpantinum](https://github.com/ilyamiro/serpantinum)，但配色、组件、字体、
动画曲线全部改用本项目已有的设计令牌。锁屏头像改用与桌面 `UserCardWidget` 相同的加载链
（`avatarPath` → `~/.face` → 图标回退）；右翼歌词卡复用 `LyricsService`。

Hyprland 窗口阴影对齐 Caelestia：`range` 48 → 15、`render_power` 17 → 4、偏移归零、
颜色由纯黑改为随主题变化的 `inverse_primary`，由 matugen 模板生成。

修复：字体配置指向不存在的 `Google Sans Flex`，`fc-match` 静默回退到 Noto Sans CJK，
全局实际一直在用思源黑体。改为 `Google Sans`。

说明：锁屏 QML 基于 Qt6 —— `Button.contentItem` 是 FINAL 属性不可覆盖，圆形图标按钮
改为自绘；`clip: true` 只裁矩形，圆形头像用 `OpacityMask`。

## 2026-09-11

### 灵动岛：音量滚轮 + 右键拖动

- 音量调节由「收起态上下滑」改为「滚轮」。上下滑要占用整个收起态的拖动手势，
  和点击展开互相干扰；滚轮不冲突，每格 5% 步进，触控板连续值按比例缩放。
- 支持右键拖动调整位置。拖动只移动窗口内的岛，layer-shell 窗口保持全屏不动，
  避免改 margins 触发 Hyprland 重配 surface 导致拖动抖动。偏移量持久化在
  `Persistent.states.island`。IPC `island reset_position` 一键复位。
- `Persistent.qml` 纳入差异层：新增 `island` 字段承载灵动岛偏移量。

### 灵动岛：歌词点击跳转 + 逐字高亮

- **点击跳转修复**：`MusicActivity.qml` 里 `seekAtY()` 调用了 `root.seekRequested(...)`，
  但这个信号从未声明，运行时报 `TypeError: Property 'seekRequested' is not a function`；
  同时 `DynamicIsland.qml` 的 `if (item.seekRequested !== undefined)` 因此恒为 false。
  补上信号声明后，点击歌词行即可跳转。
- **逐字高亮取色提亮**：封面主色经量化后常常偏暗，而灵动岛底色是纯黑，直接使用会导致
  高亮几乎读不出来。对高亮色设亮度下限 `0.62` 并轻微提饱和（×1.15）。
- **跳转补偿歌词偏移**：行时间是歌词坐标系的时间，而当前行判定用的是
  `currentTime + effectiveOffset`，跳转前扣掉该偏移。
- **KRC 逐字高亮错乱**：旧代码用 `rawStart >= krc[1]` 判断偏移是绝对时间还是相对时间，
  会把同一行内偏移较大的字误判为绝对时间，产生非单调时间戳。已统一按「相对行首」累加。
- **当前行整行不可见**：当前行容器误用 `Layout.fillWidth` / `Layout.fillHeight`，
  但它的 delegate 根节点是普通 `Column`，这些附加属性不生效，容器实际尺寸为 0，
  叠加 `clip: true` 后主文本被整条裁掉。改为显式设置宽高。

### 灵动岛：包管理副岛 + 通知副岛

- **包管理副岛**：主岛右侧显示下载 / AUR 构建进度，支持进程自动探测与 IPC 主动上报；
  `IslandTheme` 补充 `package` 尺寸项。IPC 泛化为 `task_begin` / `task_progress` /
  `task_end`（`pkg_*` 保留为别名）。
- **通知副岛**：收到通知时在主岛右侧显示铃铛 + 摘要，4 秒后自动消失，不抢占主岛。
- **封面取色**：量化当前封面主色，歌词高亮随之着色（`ArtColorSource`）。
- **`TaskSource` 通用骨架**：把「进程探测 + IPC 上报」抽出来复用，新增 `download` 任务源；
  右侧副岛改为列表驱动 + Repeater 渲染。
- **录屏伴随指示器**：主岛左侧的小胶囊，点击停止录屏；`IslandTheme` 补充 `recording`
  尺寸项。`recording` 活动优先级由 20 下调至 5，使录屏与音乐并存时主岛显示音乐。
- **调整**：锁屏背景固定为桌面壁纸，移除了播放时淡入的模糊专辑封面背景；
  栏上的旧录屏胶囊默认关闭；灵动岛窗口宽度 360 → 480 → 640。
- **修复**：栏上反复报 `Cannot assign to read-only property "mirrored"` ——
  守卫用的 `item.hasOwnProperty("mirrored")` 会命中原生只读属性 `QQuickItem.mirrored`，
  改为判断 `modelData === "visualizer"`。`MprisSource` 偶发
  `Cannot read property 'trackTitle' of null` —— 改为先缓存 `player` 到局部变量再判空。

### 新增：壁纸选择器斜切轮播视图

水平轮播，选中项居中放大，相邻项按距离缩放 / 倾斜，动态圆角，支持滚轮与方向键；
灵感来自 [Serpantinum](https://github.com/ilyamiro/serpantinum)。浮动筛选胶囊：
全部 / 历史 / 视频 + 颜色圆点 + 内联搜索框。颜色索引脚本
`scripts/wallpapers/index_colors.py` 多线程算主色并分桶，按 `(文件名, mtime, size)`
增量缓存到 `~/.cache/quickshell/wallpapers/`。`wallpaperSelector.viewMode`
（`grid` 默认，`carousel` 可选），工具栏可一键切换。

### 调整：Dock 自动隐藏

空工作区不再自动显示 Dock，仅由鼠标悬浮到底部、应用请求、拖拽或手动 pinned 触发。
新增 `dock.revealOnDesktop` 配置项（默认 `false`）。
