# 排障与已知问题

> 历史修复记录见 [CHANGELOG.md](../CHANGELOG.md)。本页只保留「症状 → 根因 → 修复」的排障索引。

## 登录后整个桌面卡死（tty 都进不去）

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

## Quickshell 报「Could not find 'end4-pC' config directory」

这不是路径不存在，而是 `~/.config/quickshell/end4-pC/` 下找不到可识别的入口
`shell.qml`。常见于把 `shell.qml` 改名为 `.off` 之后忘记改回。改回来即可。

## 设置面板某页无法向下滚动（滚到底就回弹）

**症状**：设置面板的某一页（典型是「界面」）滚到下半部分时，内容像被顶住
一样弹回，靠后的分节永远看不到。

**根因**：该页的 `contentHeight` 被低估。`ContentPage` 继承自
`StyledFlickable`，滚动上限是 `contentHeight - height`；一旦实际内容比
`contentHeight` 高，超出的部分就永远滚不到，表现为「回弹」。

最常见的原因是**把 `Repeater` 直接放进 `GroupedList`**：`GroupedList` 的
`default property list<Item> items` 只把 `Repeater` 本身算作一个 item，而
`Repeater` 没有 `implicitHeight`，展开出的子项高度全部丢失。

**修复**：分组列表用 `ColumnLayout` + `Repeater` 手写，给每个 delegate 显式
`implicitHeight`。参考 `BarConfig.qml`、`BackgroundConfig.qml` 的写法。

## 换壁纸后光标颜色不跟随

`~/.config/matugen/config.toml` 曾丢失 `post_hook`（光标主题重渲染钩子）以及
`[templates.yazi]`、`[templates.obs]`、`[templates.vscode]` 三块模板。完整内容
备份在 `config.toml.orig`。若发现光标不再随壁纸主色变化，先比对这两个文件。

## 栏里某个组件凭空消失 / 后面元素整体左移

**症状**：栏上某一组组件（典型是 `resources` 的环形指示器）不渲染了，
它后面的元素整体前移；日志里**没有 ERROR**。

**根因**：某个被它依赖的 QML 组件编译失败，变成了 `unavailable`。
最常见的写法错误是**在同一个对象上写两个 `Component.onCompleted`**
（QML 不允许同一属性重复赋值），日志里只有一行很容易被忽略的：

```
WARN scene: @modules/common/widgets/StyledPopup.qml[163:13]: Property value set multiple times
```

`StyledPopup` 一旦 unavailable，所有继承它的弹层（`ResourcesPopup` /
`ClockWidgetPopup` / `WeatherPopup` / `BatteryPopup` / `BluetoothPopup` /
`NetworkSpeedPopup`）会连锁失效，声明这些弹层的栏组件连带构建失败。

**排查**：这类问题的关键字是 `unavailable` 与 `Property value set multiple times`，
**不是** `ERROR`。只 grep `ERROR|ReferenceError|TypeError` 会完全漏掉。

```bash
killall qs
timeout 15 qs -c end4-pC > /tmp/qs-check.log 2>&1
grep -nE "unavailable|Property value set multiple times|Failed to load|Syntax error" /tmp/qs-check.log
```

另外可以用像素定位辅助判断：沿栏中线扫一行，比较改动前后各「药丸」色块的
起止 x 坐标，就能立刻看出是哪个组件变窄/消失了。

## 玻璃面板糊不起来（能看到壁纸但没模糊）

Hyprland 的 `ignore_alpha` 是「alpha 低于该值的像素直接跳过、不参与模糊采样」。
通用规则里 `quickshell:.*` 设的是 `ignore_alpha = 0.79`，而 `LiquidGlass`
底板的 alpha 在 0.55~0.78，正好全部被跳过。

**修复**：对需要玻璃质感的面板单独把阈值降下来（见 `hyprland/rules.lua` 末尾
「液态玻璃」一节），完全透明的空白段依然不会被模糊。

## 一切到仪表盘的「媒体」页就崩溃（段错误）

**症状**：打开岛屿 → 切到媒体页，qs 立刻 SIGSEGV。堆栈落在

```
QV4::QObjectMethod::resolveOverloaded
QMetaObject::inherits
```

**根因**：本机装了 Caelestia 的 C++ 插件
（`…/libcaelestia-services.so`），`Caelestia.Services` 导出的 **C++ 单例也叫
`Lyrics`**，会盖掉 `dashboard-caelestia/shim/Lyrics.qml` 的同名 QML 单例。于是
`LyricList.qml` 里的 `Lyrics` 解析到的是 Caelestia 的实现，而
`CUtils.enumToString()` **带默认参数（在 MOC 里等于多个重载）**，把 QML 单例喂给
重载方法会让 Qt 在 `resolveOverloaded` 里踩空 → 段错误。

**修复**：删除 `LyricList.qml` / `LyricsInfo.qml` 里的 `import Caelestia.Services`，
让 `Lyrics` 落到 shim 上；`LyricsInfo` 里改读 shim 新增的 `Lyrics.sourceName`
字符串，不再走 C++ 枚举转换。

**排查手法**：给 shim 加一个只有它才有的方法/属性，若报
`is not a function` 或 `Cannot read property … of undefined`，就说明解析到了 C++
那边。

> 通用教训：给 C++ 的 `Q_INVOKABLE` 传参时，**带默认参数 = 多重载**。传错类型不会
> 报错，而是直接段错误。堆栈落在 `resolveOverloaded` 时，先怀疑「有重载的 C++
> 方法收到了它不认识的 QML 对象」。

## 按 Super + / 没有反应

**根因一**：全局快捷键**在 qs 侧没注册**。`hyprctl globalshortcuts` 里查不到
`cheatsheetToggle` —— Hyprland 那条 `hl.dsp.global("quickshell:cheatsheetToggle")`
指向了一个不存在的处理器。

```bash
hyprctl globalshortcuts | grep -i cheat
```

若为空，说明 qs 没注册。注册必须放在 `Scope` **根**上常驻，写进面板内部的话
面板一收起注册就没了。

**根因二**：键位被覆盖。`custom/keybinds.lua` 若也绑了 `SUPER + Slash`，会顶掉
官方那条。注意**不要**在 custom 里补一条同样的绑定：同键位两条会同时触发，面板
会「开一次又关一次」，看起来仍然像没反应。

**根因三**（这类问题的通用排查）：确认按键到底有没有到达面板。

```bash
hyprctl dispatch 'hl.dsp.global("quickshell:cheatsheetToggle")'
```

这条会直接执行绑定指向的 dispatcher。若它能打开面板，说明键位与 dispatcher 都
没问题，只是物理按键没被合成器识别（`wtype` 注入的按键**到不了** Hyprland 的
全局快捷键层，测不出来，别据此判断功能坏了）。

## 改键改不动 / 改了没效果

- **PrtSc / ScrollLock / Pause 改不了**：这几个键曾未加入 `keyName()` 映射，按下
  后返回空串被当成「未识别的键」忽略。见 [keybind-manager.md](keybind-manager.md)。
- **R / E / T / S / C 改了没效果**：不是没写进去，是**目标键已被占用**（Hyprland
  对同键位的多条绑定会全部触发）。`SUPER + E/T/S/C` 分别被文件管理器 / 终端召唤 /
  暂存区 / 代码编辑器占用。面板会提示占用者，换个键或先改掉占用者。
- **改键时底下几行一起变了**：多行 `hl.bind(...)` 只改起始行即可，key 字符串总在
  第一行；不要试图重建 dispatcher。
