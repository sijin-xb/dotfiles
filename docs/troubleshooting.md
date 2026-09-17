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
