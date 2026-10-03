# Easy Effects 样式溯源与 Material Design 3 改造

> **范围**：Easy Effects 8.3.0（Arch 包 `easyeffects 8.3.0-1.1`）的界面样式来源分析、MD3 配色接入方案，以及与 matugen 集成的收尾说明。
> **历史变更**：[CHANGELOG.md](../CHANGELOG.md)

## 核心结论

**Easy Effects 8.3.0 已从 GTK4/libadwaita 迁移到 Qt6 + KDE Frameworks 6
(Kirigami)**。源码树中不存在任何 `.css`、`.ui` 或 GResource 定义文件，全部 UI
由 QML 实现，颜色由 `KColorScheme`（KDE 配色方案体系）驱动。因此：

1. 不存在「libadwaita 自定义 CSS」或「adw-gtk3 主题包依赖」。
2. 配色来源是 KDE color scheme 文件（`~/.local/share/color-schemes/*.colors`），
   由 `~/.config/kdeglobals` 的 `[General] ColorScheme=` 指定当前生效方案。
3. 接入 matugen 的路径已存在：matugen 的 `[templates.kde_colorscheme]`
   生成 `Matugen.colors`，`post_hook.sh` §6 把 `kdeglobals` 指过去。
4. 不需要对 Easy Effects 源码做任何修改，也不需要写 GTK CSS 片段。

## 一、样式溯源

### 技术栈确认

| 项目 | 值 |
|---|---|
| 上游版本 | 8.3.0 |
| UI 框架 | Qt6 Quick + QML |
| 组件库 | KDE Kirigami (`org.kde.kirigami`) + KirigamiAddons |
| 颜色管理 | `KColorSchemeManager`（`kcolor_manager.cpp`） |
| 配置后端 | KConfig (`easyeffects_db.kcfg`) |
| Qt Controls Style | `org.kde.desktop`（默认），可被 `forceBreezeTheme` 覆盖为 Breeze |
| 构建系统 | CMake + ECM (extra-cmake-modules) |

源码路径引用：
- `src/CMakeLists.txt:258-266`—链接 `KF6::ColorScheme`、`KF6::ConfigCore` 等
- `src/main.cpp:442`—`KColorSchemeManager::instance()`
- `src/main.cpp:477`—`KColorManager` 实例化
- `src/main.cpp:485-487`—Qt Quick Controls style 设为 `org.kde.desktop`
- `src/kcolor_manager.cpp`—颜色方案切换逻辑
- `src/contents/ui/*.qml`—全部 UI 由 QML 实现，颜色通过
  `Kirigami.Theme.textColor` / `backgroundColor` / `highlightColor` 等语义角色引用

### 配色链路

```
壁纸图片
  └─ matugen image <壁纸> -t ... -m ...
       └─ [templates.kde_colorscheme]
            input:  ~/.config/matugen/templates/Matugen.colors (模板)
            output: ~/.local/share/color-schemes/Matugen.colors (产物)
       └─ [templates.kvantum]
            input:  ~/.config/matugen/templates/kvantum/MaterialAdw.kvconfig
            output: ~/.config/Kvantum/MaterialAdw/MaterialAdw.kvconfig
       └─ post_hook.sh §6
            比较 kdeglobals 与 Matugen.colors 的 Colors:Window BackgroundNormal
            不一致 → plasma-apply-colorscheme BreezeDark → Matugen（双步强制应用）
            一致 → 跳过
                 └─ kdeglobals [Colors:*] 段写入 matugen 颜色值
                      └─ KColorSchemeManager 读取 kdeglobals
                           └─ Kirigami.Theme 属性传播到全部 QML 控件
                                └─ Easy Effects 界面获得 matugen 配色
```

> **关键**：KColorScheme 运行时读的是 kdeglobals 里的颜色值，不是 `.colors`
> 文件。`.colors` 只是预设，`plasma-apply-colorscheme` 把预设的值复制进
> kdeglobals。如果只改 `ColorScheme=Matugen` 这个名字而不应用值，
> 所有 Qt6/KF6 应用看到的还是旧颜色。

### Easy Effects 内部颜色机制

1. **`KColorSchemeManager`**（`main.cpp:442`）：全局 KDE 颜色方案管理器，
   Easy Effects 启动时自动初始化。
2. **`KColorManager`**（`main.cpp:477`，`kcolor_manager.cpp`）：封装方案切换，
   QML 中通过 `KColorManager.activeScheme()` / `activateScheme(idx)` 调用。
3. **`Kirigami.Theme`**：QML 控件通过语义角色名引用颜色（如
   `Kirigami.Theme.textColor`、`backgroundColor`、`highlightColor`、
   `negativeTextColor`、`positiveTextColor`），不硬编码 hex。
4. **`forceBreezeTheme`**（KConfig `[Style] forceBreezeTheme`，默认 `true`）：
   启动时调用 `QApplication::setStyle("breeze")`，强制 Qt widget style
   为 Breeze。这只影响 QStyle 绘制的原生控件（滚动条、对话框按钮等），
   不影响 Kirigami 主题颜色。
5. **图表颜色**：`EeChart.qml` 使用 `GraphsTheme`，颜色由 `DbGraph`（KConfig
   `[Graphs]` 组）存储，支持自动/浅色/深色三种 colorScheme 和 8 种预设 colorTheme
   + 用户自定义。与 KDE color scheme 是独立的。
6. **`QT_QUICK_CONTROLS_STYLE`**：若环境变量已设则尊重之，否则设为
   `org.kde.desktop`。

### 当前状态判断

| 检查项 | 当前值 | 判断 |
|---|---|---|
| `~/.config/kdeglobals` ColorScheme | `Matugen` | matugen 已接管 |
| kdeglobals 颜色值 | 与 Matugen.colors 一致 | 配色已真正应用 |
| `~/.local/share/color-schemes/Matugen.colors` | 存在 | matugen 产物就位 |
| `~/.config/easyeffects/easyeffects.conf` forceBreezeTheme | `false` | 已关闭 |
| `QT_QPA_PLATFORMTHEME` (niri config.kdl) | `xdgdesktopportal` | 不再走 gtk3 桥接 |
| `QT_STYLE_OVERRIDE` (niri config.kdl) | `kvantum` | Qt 控件走 MaterialAdw 主题 |
| matugen `post_hook.sh` §6 | 比颜色值，不比名字 | 换壁纸后自动强制应用 |

**三个根因及修复（2026-10-04）**：

1. **kdeglobals 颜色值与方案名不一致**：`ColorScheme=Matugen` 但 `[Colors:*]`
   段还是旧的蓝色值。`plasma-apply-colorscheme` 只比名字，同名跳过。
   → 修复：post_hook §6 改为比较 `Colors:Window BackgroundNormal` 颜色值，
   不一致时走 BreezeDark→Matugen 双步切换强制应用。

2. **`QT_QPA_PLATFORMTHEME=gtk3`**：niri 的 `environment` 块把 Qt5/Qt6
   都设为 `gtk3` 桥接，绕过了 Kvantum 主题和 KDE 配色方案，所有 Qt 应用
   渲染成朴素 GTK 外观。
   → 修复：改为 `QT_QPA_PLATFORMTHEME=xdgdesktopportal` +
   `QT_STYLE_OVERRIDE=kvantum`。

3. **Easy Effects `forceBreezeTheme` 默认 `true`**：即使 Kvantum 生效，
   Easy Effects 仍会 `QApplication::setStyle("breeze")` 覆盖。
   → 修复：`kwriteconfig6 --file easyeffects/easyeffects.conf --group
   General --key forceBreezeTheme false`。

### 与 GTK4/libadwaita 的关系

Easy Effects 8.3.0 的安装包不包含任何 GTK 资源文件：

```
$ pacman -Ql easyeffects | grep -E '\.(css|gresource|ui)$'
（无输出）
```

安装文件仅包含：
- `/usr/bin/easyeffects`（Qt6 二进制）
- `/usr/share/applications/com.github.wwmm.easyeffects.desktop`
- `/usr/share/icons/hicolor/scalable/apps/com.github.wwmm.easyeffects*.svg`
- `/usr/share/locale/*/LC_MESSAGES/easyeffects.mo`
- `/usr/share/metainfo/com.github.wwmm.easyeffects.metainfo.xml`

本机的 `~/.config/gtk-3.0/gtk.css` 和 `~/.config/gtk-4.0/gtk.css`（matugen 生成）
对 Easy Effects **完全无效**——它们只作用于 GTK 应用。

## 二、MD3 改造方案

### 现状

Easy Effects 已经通过以下链路获得了 Material Design 3 配色：

- matugen 从壁纸提取种子色，按 MD3 tonal palette 生成 50 个语义角色
- `Matugen.colors` 模板把这些角色映射到 KDE color scheme 的
  `[Colors:Window]`、`[Colors:View]`、`[Colors:Selection]` 等段
- `kdeglobals` 指向 `Matugen`，KColorScheme 读取这些段
- Kirigami.Theme 将 KDE color scheme 的各段暴露为 QML 可读的语义属性

因此，Easy Effects 已经**在事实上被 MD3 化**了——它的 accent color、背景色、
前景色、高亮色全部来自 matugen 生成的 MD3 调色板。

### 待优化项

#### 2.1 关闭 `forceBreezeTheme`

**问题**：`forceBreezeTheme` 默认为 `true`，启动时强制
`QApplication::setStyle("breeze")`。这会让 Qt widget style（滚动条、
对话框按钮、输入框边框等）使用 Breeze 而非系统的 `kvantum-dark`，
与桌面其余 Qt 应用不一致。

**修复**：
```bash
kwriteconfig6 --file easyeffects/easyeffects.conf \
    --group General --key forceBreezeTheme false
```

#### 2.2 修复 `QT_QPA_PLATFORMTHEME`

**问题**：niri `config.kdl` 的 `environment` 块设了
`QT_QPA_PLATFORMTHEME=gtk3`，这让 Qt5/Qt6 通过 `libqgtk3.so` 桥接
获取主题——完全绕过 Kvantum 和 KDE 配色方案。所有 Qt 应用渲染成
朴素 GTK 外观，matugen 配色不生效。

**修复**（`~/.config/niri/config.kdl`）：
```
QT_QPA_PLATFORMTHEME "xdgdesktopportal"
QT_STYLE_OVERRIDE "kvantum"
```

`xdgdesktopportal` 让 Qt 通过 portal 获取主题/配色（不强制 GTK），
`kvantum` 作为 style plugin 被 Qt 自动加载。

#### 2.3 修复 post_hook.sh §6 颜色值同步

**问题**：旧逻辑只检查 `ColorScheme=Matugen` 这个名字——同名就跳过。
但 kdeglobals 里的颜色值可以和 Matugen.colors 完全不一致。
`plasma-apply-colorscheme` 也比较名字，同名不重新应用颜色。

**修复**：post_hook §6 改为比较 `Colors:Window BackgroundNormal` 颜色值，
不一致时走 `plasma-apply-colorscheme BreezeDark → Matugen` 双步切换。

#### 2.4 图表配色对齐（可选）

Easy Effects 的频谱图/频率响应图默认使用 Qt 内置的 `QtGreenNeon` 主题。
若要让图表也跟随 MD3 配色，在 Easy Effects 设置中：

- `偏好设置 → 图表 → Color theme` 选 `User`
- 手动设置 Background、Plot area background、Series colors 等颜色
  为 matugen 的 surface/primary 等

由于图表颜色由 `DbGraph` KConfig 存储（不走 KDE color scheme），无法通过
matugen 模板自动注入。如需自动化，可以写一个 matugen 模板直接生成
`~/.config/easyeffects/db/easyeffectsrc` 的 `[Graphs]` 段，但这会
覆盖用户手动设置的其他图表参数。

#### 2.5 深浅色模式

Easy Effects 跟随 KDE color scheme 的明暗。matugen 的 `Matugen.colors` 模板
同时输出 `[Dark]` 和 `[Light]` 段。当系统在深/浅之间切换时：

- niri 会话：DMS 管理 `kdeglobals` 的 `ColorScheme`，切换 `Matugen` ↔
  `MatugenLight`（或同文件内 prefer Dark/Light）
- Hyprland 会话：`post_hook.sh` §6 只保证指向 `Matugen`，明暗由 matugen
  `--mode` 参数控制

Easy Effects 的 `KColorSchemeManager` 在配色方案变更时会自动更新，
无需重启。

### 验证方式

```bash
# 1. 确认 kdeglobals 颜色值与 Matugen.colors 一致
KG=$(kreadconfig6 --file kdeglobals --group "Colors:Window" --key BackgroundNormal)
MC=$(kreadconfig6 --file ~/.local/share/color-schemes/Matugen.colors --group "Colors:Window" --key BackgroundNormal)
echo "kdeglobals: $KG  Matugen.colors: $MC"
# 预期: 两个值相同

# 2. 确认 forceBreezeTheme 已关闭
kreadconfig6 --file easyeffects/easyeffects.conf \
    --group General --key forceBreezeTheme
# 预期: false

# 3. 确认 Qt 主题设置
grep QT_QPA_PLATFORMTHEME ~/.config/niri/config.kdl
# 预期: "xdgdesktopportal"

# 4. 确认 EasyEffects 加载了 Kvantum
cat /proc/$(pgrep -x easyeffects)/maps | grep kvantum
# 预期: libkvantum.so 出现, libqgtk3.so 不出现
```

## 三、控件可用性约束

Easy Effects 的关键控件及其颜色依赖：

| 控件 | QML 文件 | 颜色来源 | 约束 |
|---|---|---|---|
| 开关 (Switch) | `EeSwitch.qml` | `Kirigami.Theme.textColor` / `disabledTextColor` | 开/关状态需对比度 ≥ 3:1 |
| 滑块 (Slider) | 各插件 QML | `Kirigami.Theme.highlightColor` | trough 与 fill 需可区分 |
| 频谱图 | `EeChart.qml` | `DbGraph.*`（KConfig） | 独立于 KDE color scheme，需单独设 |
| 下拉框 | `FormCard.FormComboBoxDelegate` | Kirigami Theme | 弹出层背景需与窗口背景有层级差 |
| 列表行 | `FormCard.AbstractFormDelegate` | `Kirigami.Theme.backgroundColor` | 选中态需 accent_bg + accent_fg |
| 音量电平 | `EeAudioLevel.qml` | `Kirigami.Theme.backgroundColor` + `neutralTextColor` + `negativeTextColor` | 过载区（红色）必须可识别 |

matugen 的 contrast = 0.3 已保证 surface_container 与 on_surface 对比度 ≥ 7:1
（AAA），上述约束均满足。

## 四、仓库收尾

### 文档

新增本文档（`docs/easyeffects-styling.md`），在 `docs/README.md` 索引中
补充条目。

### 安装脚本

`install.sh` 中 `easyeffects` 已在依赖列表中（第 832 行），无需修改。
不需要为 Easy Effects 额外安装 GTK 主题包或 adw-gtk3。

### 配置同步

本机 `~/.config/easyeffects/` 目前只有 `db/` 目录（KConfig 状态），
不纳入 dotfiles（ chezmoi ignore 里的 `.config/easyeffects/db/` 被
排除）。需要做的只有：

1. 关闭 `forceBreezeTheme`（通过 kwriteconfig6 或 GUI）
2. 确认 matugen 的 `kde_colorscheme` 模板和 `post_hook.sh` §6 正常工作

无新增配置文件需要提交到 dotfiles 仓库。