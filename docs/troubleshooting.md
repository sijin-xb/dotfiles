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

## 登录后黑屏 / 空桌面，只剩鼠标光标

**症状**：Hyprland 起来了（能切 tty、`hyprctl` 有响应），但屏幕上什么都没有，
只有鼠标指针。没有栏、没有壁纸、快捷键没反应。

**这和上面那条「整个桌面卡死」不是一回事**：那条是合成器一起死了，这条是
**合成器正常、桌面 Shell 没起来**。

### 根因一：Quickshell 被输入法「等就绪」卡死（已修）

`hyprland/execs.lua` 里启动 qs 的那一行，前面串着一个**无界等待**：

```sh
while ! fcitx5-remote --check >/dev/null 2>&1; do sleep 0.1; done; ... ; qs -c $qsConfig
```

`fcitx5-remote --check` 的语义是「Fcitx 已在运行返回 0，否则返回 1」。于是
**fcitx5 没起来 / DBus 不可用 / fcitx5-remote 不存在**时它恒为假，循环永不退出，
`qs` 永远不会被执行 → 只剩光标。

修复：输入法初始化与 Shell 启动**解耦**，两边都有明确超时。

| 文件 | 作用 |
|---|---|
| `hyprland/scripts/fcitx_init.sh` | 有界等待（默认 10s，`FCITX_READY_TIMEOUT_SEC` 可调），失败只记日志、退出 0 |
| `hyprland/scripts/start_quickshell.sh` | 独立启动 Shell、健康检查、失败回退，全过程写日志 |

### 怎么查

```bash
cat ~/.local/state/dotfiles/quickshell-startup.log      # Shell 启动全过程
cat ~/.local/state/dotfiles/fcitx-init.log              # 输入法初始化
```

日志里有：最终选了哪个 shell、入口是否存在、启动命令、
是否立即退出（含退出码）、是否触发回退、以及 qs 自己打出的 ERROR。

单独重跑启动逻辑（不改配置、不重启会话）：

```bash
bash ~/.config/hypr/hyprland/scripts/start_quickshell.sh
```

想临时换 shell，改 `~/.config/hypr/custom/variables.lua` 里 `hl.env("qsConfig", ...)`
的值（当前固定 `end4-pC`）后重启会话。

### 注意

* 上面那条「整个桌面卡死」的**输入法环境变量强制注入**依然是禁区：本修复只在
  Shell 启动脚本里保留 `QML2_IMPORT_PATH`，没有再引入 `QT_IM_MODULE` /
  `GTK_IM_MODULE` / `QT_WAYLAND_TEXT_INPUT_PROTOCOL`。
* 排队等待一定要有上限。同样的无界等待还留在 `niri/config.kdl` 的
  `spawn-sh-at-startup` 里（只挡输入法、不挡 Shell，所以不会黑屏），本次未改。

## Quickshell 报「Could not find 'end4-pC' config directory」

这不是路径不存在，而是 `~/.config/quickshell/end4-pC/` 下找不到可识别的入口
`shell.qml`。常见于把 `shell.qml` 改名为 `.off` 之后忘记改回。改回来即可。

## Quickshell 报「module "Caelestia.Config" is not installed」

完整错误链长这样，**最后一行才是根因**，上面几行都是被它牵连的：

```
ERROR: Failed to load configuration
ERROR: caused by @shell.qml[58:20]: Type IllogicalImpulseFamily unavailable
ERROR: caused by @panelFamilies/IllogicalImpulseFamily.qml[39:30]: Type Lock unavailable
ERROR: caused by @modules/ii/lock/Lock.qml[40:15]: Type CaelestiaLockSurface unavailable
ERROR: caused by @modules/ii/lock/caelestia/CaelestiaLockSurface.qml[5:1]:
    module "Caelestia.Config" is not installed
```

QML 的 `import <模块>` 是**硬依赖**：模块解析不到时，该文件里的类型全部
`unavailable`，错误一路往上抛到 `shell.qml`，`qs -c end4-PC` 直接
"Failed to load configuration"，桌面 Shell 起不来。

**原因**：`end4-pC` 的锁屏差异层（`modules/ii/lock/caelestia/**`，从
caelestia-dots/shell vendor 而来）有 **56 个文件**写着 `import Caelestia.Config`
—— 那是 caelestia-dots/shell 的 **C++ QML 插件**，QML 层 vendored 不了，
只能编译出来（install.sh `[4a/7]` 编到 `~/src/caelestia-build/qml`）。

**怎么查**：

```bash
ls ~/src/caelestia-build/qml/Caelestia/*.so   # 没有 = 插件没编译
echo $QML2_IMPORT_PATH                        # 会话内应为 ~/src/caelestia-build/qml
tail -20 ~/.local/state/dotfiles/quickshell-startup.log
```

启动日志里若出现「自检失败：… 依赖 Caelestia 插件，但 … 不存在」，
脚本已经定位好了，按它给的命令做即可。

import path 的注入有两个来源：会话自启走 `start_quickshell.sh`（自动注入）；
手动跑 `qs` 走 fish `config.fish`（开新终端即注入）。用其它 shell 手动跑需要
自己 `export QML2_IMPORT_PATH=~/src/caelestia-build/qml`。

**修复**（二选一）：

```bash
# 1) 重跑安装器（[4a/7] 会拉源码 + 编译）
cd ~/dotfiles && ./install.sh install

# 2) 手动编译（需要 libqalculate / aubio / libpipewire / libcava 等依赖）
sudo pacman -S --needed aubio libpipewire libqalculate lm_sensors fftw spirv-tools
paru -S --needed libcava qt6-m3shapes-git
# 源码在 ~/src/caelestia-plugin-src（**不是** ~/.config/quickshell/caelestia ——
# 那里是 quickshell 的配置命名空间，只该放真正要运行的 shell）
git clone --depth=1 https://github.com/caelestia-dots/shell.git ~/src/caelestia-plugin-src
cmake -S ~/src/caelestia-plugin-src -B ~/src/caelestia-build -G Ninja \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo -DENABLE_MODULES=plugin \
      -DVERSION=0.0.0 -DGIT_REVISION=unknown
cmake --build ~/src/caelestia-build
```

> `-DENABLE_MODULES=plugin` 不能省：上游根 CMakeLists 默认
> `ENABLE_MODULES="extras;plugin;shell"`，`shell` 会编译整个 caelestia 桌面 shell
> 应用 —— 我们只要 QML 模块（`Caelestia.Config` / `.Services` / `.Components` /
> `.Images` / `.Models` / `.Blobs` / `.I18n`），它们全在 `plugin/` 下。
> 省掉这一项会白编几分钟、还多一堆只有 shell 才需要的依赖。
>
> 另：如果之前用旧路径（`~/.config/quickshell/caelestia`）编过，
> `~/src/caelestia-build/CMakeCache.txt` 里记的还是老路径，直接复用会配置失败。
> `install.sh` 会自动检测并清空重配；手动编的话先 `rm -rf ~/src/caelestia-build`。

编译完重启会话，或单独重跑 `bash ~/.config/hypr/hyprland/scripts/start_quickshell.sh`。

**插件缺失时 shell 不再整体起不来**（2026-09-29 起）：面板族里只有「锁屏」与
「灵动岛」硬依赖 `import Caelestia.Config`，这两处已改成运行时创建
（`panelFamilies/CaelestiaPluginProbe.qml` 探针 + `PanelLoader { source: ... }`）。
所以 `qs -c end4-PC` 现在**能正常加载**，只少这两块，日志里会有：

```
WARN qml: [end4-pC] Caelestia QML 插件不可用（import Caelestia.Config 失败）：…
WARN qml: [end4-pC]   → 本次只跳过「锁屏」与「灵动岛」，其余面板不受影响。
```

想拿回锁屏与灵动岛，仍按上面的「修复」编译插件。

**不想用 Caelestia 风格锁屏**：把 `modules/ii/lock/Lock.qml` 里的
`lockSurface` 从 `CaelestiaLockSurface` 换回 `SerpantinumLockSurface`
（旧文件完整保留），就不需要这个插件了。

**别被 WARN 带偏**：日志里那一堆 `Ignoring unresolvable import`
（`..@command:components`、`shim`、`dashboard-caelestia/...` 之类）来自底盘
自带的 QML 扫描器，**无害**，和这个 ERROR 没有因果关系 —— 目录形式的
`import "..."` 解析不到只是警告，而 `import <模块>` 解析不到才致命。
先修 ERROR，WARN 不用管。

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
