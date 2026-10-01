# matugen 配置说明与启用指南

本文档描述 2026-10-02 这次整理后的 `~/.config/matugen/` 结构、需要手动完成的
步骤，以及回滚方式。

---

## 0. 先说 Steam 那个 bug

**结论：不是 Steam 的问题，是 niri 会话里根本没有 X server。**

### 根因

niri 26.04 自带 xwayland-satellite 集成：启动时它会尝试拉起 `xwayland-satellite`，
成功后由 niri 自己创建 X11 socket 并设置 `DISPLAY`，X11 客户端首次连接时再真正
拉起 XWayland 进程。

本次会话的 journal 里有决定性的一行：

```
06:15:31 niri[929]: WARN niri::utils::xwayland::satellite:
  error spawning xwayland-satellite at "xwayland-satellite",
  disabling integration: No such file or directory (os error 2)
06:19:23 sudo: xibie : COMMAND=/usr/bin/pacman -S ... xwayland-satellite
```

niri 在 **06:15:31** 启动，那一刻 `xwayland-satellite` 还没装，spawn 直接 ENOENT。
niri 的处理是**永久关闭本次会话的集成**（不重试、不重载），于是：

- `DISPLAY` 从未被设置（`printenv DISPLAY` 为空）
- `/tmp/.X11-unix/` 一直是空目录，没有任何 X socket

包在 **06:19:23** 才装上，晚了 4 分钟。Steam 的 bootstrap 与主界面都是纯 X11
程序，`XOpenDisplay()` 失败后直接 `Unable to open X11 display, exiting` —— 日志
里 06:17:26 / 06:17:55 / 06:19:13 / 06:19:29 / 06:19:45 五次启动，五次同样的错。

### 修复

**正式修复：重启 niri 会话（注销 → 重新登录）。** niri 会重新走一遍启动流程，
这次能找到 `xwayland-satellite`（0.8.3 已装，版本足够新）。

重启后验证：

```bash
printenv DISPLAY          # 期望输出 :0
ls /tmp/.X11-unix/        # 期望有 X0
steam                     # 应能正常出窗口
```

**临时绕过（不注销也能用）：** 手工起一个 satellite，然后带着 `DISPLAY` 启动：

```bash
xwayland-satellite :0 &
DISPLAY=:0 steam
```

本机已实测 `xwayland-satellite :9` 可以独立跑通（日志 `Connected to Xwayland on :9`）。

### 两个不要做的事

1. **不要 enable `xwayland-satellite.service`。**
   `/usr/lib/systemd/user/xwayland-satellite.service` 是给「没有内置集成的合成器」
   用的。niri 有自己的集成，两边同时跑会抢同一个 display number。
   当前状态是 `disabled`，保持不动。

2. **Hyprland 侧不用管。** Hyprland 自带 XWayland（`general.lua` 里只有
   `force_zero_scaling = true`，没关掉），那条路径本来就是好的。

---

## 1. 本次改动的文件

### 新增

| 文件 | 用途 |
|---|---|
| `hooks/post_hook.sh` | 统一收尾钩子：WM 重载 + 组件热重载 + 优雅降级提示 |
| `templates/hook-anchor.txt` | 钩子挂载点（matugen 没有全局 post_hook） |
| `templates/kvantum/MaterialAdw.kvconfig` | Qt5/Qt6 配色（23 个颜色键、59 处赋值全部参数化） |
| `templates/fish/matugen-colors.fish` | fish 语法高亮配色 |
| `templates/swaync/colors.css` | swaync 配色变量（预置，本机未装 swaync） |
| `templates/firefox/userChrome.css` | Firefox 浏览器外壳配色 |
| `templates/mpv/osc.conf` | mpv OSC 配色 |

### 修改

| 文件 | 改动 |
|---|---|
| `config.toml` | 重写。补 §1 配色方案、§4 Kvantum、§6 swaync、§7 fish、§8 Firefox/mpv、§10 钩子。原有条目与注释全部保留 |
| `templates/gtk-4.0/gtk.css` | 追加 libadwaita 的 CSS 自定义属性段（`--accent-bg-color` / `--window-bg-color` 等，明暗各一套） |
| `templates/fastfetch-config.jsonc` | 边框对齐修正（见 §4） |

### 备份

```
~/.config/matugen/config.toml.bak-20261002-0630   # 本次改动前的 config.toml
~/.config/matugen/config.toml.orig                # 更早的 Omarchy 原始版
```

---

## 2. 需要手动做的四件事

### 2.1 kitty 热重载（否则配色要重启 kitty 才生效）

`~/.config/kitty/kitty.conf` 里**没有** `allow_remote_control`，
`kitty @ set-colors` 会被拒绝。加一行：

```conf
allow_remote_control socket-only
```

`socket-only` 比 `yes` 安全：只允许通过 Unix socket 控制，不监听 TCP。
加完重启一次 kitty，之后换壁纸就是即时的。

### 2.2 fish 配色被 config.fish 覆盖

`~/.config/fish/config.fish` 第 33–35 行有硬编码的 `fish_color_*`：

```fish
    # Colors
    set -g fish_color_valid_path --underline '#d5bbff'
    set -g fish_color_param '#e7e0ea'
```

fish 的 source 顺序是：先按字母序读 `conf.d/*.fish`，**最后**才读 `config.fish`。
所以这三行会覆盖 `conf.d/matugen-colors.fish`。删掉它们即可。

### 2.3 Firefox userChrome

两个前置条件：

1. `about:config` 里设 `toolkit.legacyUserProfileCustomizations.stylesheets = true`
2. Firefox 至少启动过一次（本机 `~/.mozilla/firefox/` 还不存在）

matugen 只把内容生成到 `~/.config/matugen/generated/firefox-userChrome.css`，
`post_hook.sh` 会按当前 profile 复制到 `<profile>/chrome/userChrome.css`。
profile 名是随机串，所以**不能**把 output_path 写死成某个 profile 路径。

### 2.4 Kvantum 主题名确认

`~/.config/Kvantum/kvantum.kvconfig` 当前是 `theme=MaterialAdw`，与模板输出的
目录名一致，不用改。

---

## 3. 依赖包

### 已经装好，无需操作

```
matugen 4.2.0      kvantum 1.1.8      kvantum-qt5
xwayland-satellite 0.8.3              xorg-xwayland 24.1.13
mpv 0.41           firefox 157        kitty
```

### 本机缺、但**建议装**的

```bash
# swaync：通知中心。当前通知由 DMS 接管，装了才需要 §6 的 swaync 模板生效。
# 不装的话那条模板会往 ~/.config/swaync/ 写一个没人读的文件，无害。
sudo pacman -S swaync
```

### 明确**不需要**装的

- **`qt6ct` / `qt5ct`** —— 本机走的是 Kvantum 路线。`kvantum` 包提供 Qt6 style
  plugin，`kvantum-qt5` 提供 Qt5，一个主题同时覆盖两代 Qt。再引一套 ct 调色板
  只会多一个会漂移的颜色源。
- **`adw-gtk3`** —— 本机已有 `~/.local/share/themes/adw-gtk3-dark`
  （手工放置，不归任何 pacman 包管），`gtk-theme-name=adw-gtk3-dark` 已在用。
  注意它是手工装的，升级不会自动跟随，哪天 GTK 变了要自己换。
- **`waybar`** —— 本机没装（`~/.config/waybar/` 是残留）。`config.toml` 里的
  waybar 模板保持原样，装了就能用。

---

## 4. fastfetch 边框：两轮修正

宽度基准：底边 `└` + 38×`─` + `┘` = **40 列**。

### 第一轮：三条边框宽度错位

| 分区 | 修正前 | 修正后 | 处理 |
|---|---|---|---|
| Hardware | 41 | 40 | 右侧 `─` 14 → 13 |
| System | 40 | 40 | 本来就对 |
| Theme | 40 | 40 | 本来就对 |
| Times | 39 | 40 | 右侧 `─` 15 → 16 |
| Music | 39 | 40 | 右侧 `─` 15 → 16 |

### 第二轮：label 左右不对称

第一轮之后字符数已经全部是 40，但视觉上 `󰔎 Theme󰔎` 里那个空格只落在
**词左边**，右边是贴着图标的，看着像缺一块。改成左右各一个空格：

```
改前  ┌──────────────󰔎 Theme󰔎────────────────┐
改后  ┌──────────────󰔎 Theme 󰔎───────────────┐
```

右侧横线相应减 1（16 → 15），整条边框仍然是 40 列。五条一起改，避免只有
Theme 一种样式。

### 顺带排除的两个怀疑方向

- **字形宽度**：手写 TTF 解析读了 `/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf`
  的 `cmap` + `hmtx`。四个图标（U+F02CA / U+F0EE0 / U+F050E / U+F06AD）
  的 advance 全部是 **600**，与空格、`─` 完全一致，都是 1 cell。不存在
  「某个图标是双宽」的情况。
- **空格字符本身**：逐码点扫过五条边框，唯一的空格是索引 16 处的普通
  `U+0020`，没有 NBSP / 薄空格 / 全角空格混入。

结论：这类「看着短一截」的问题，先量字形宽度和码点，再动字符串。只数字符数
是不够的 —— 一个 2 cell 的图标就能让 40 字符渲染成 41 列。

### 验证命令

```bash
# 打印每条输出行的显示宽度（wcwidth 规则），确认信息栏与底边都是 40
python3 - <<'PY'
import subprocess, re, unicodedata
def w(s):
    return sum(0 if unicodedata.combining(c) else
               (2 if unicodedata.east_asian_width(c) in 'WF' else 1) for c in s)
for l in subprocess.run(['fastfetch','--logo','none'],capture_output=True,text=True).stdout.splitlines():
    c = re.sub(r'\x1b\[[0-9;]*m','',l)
    if c.strip(): print(w(c), '|'+c+'|')
PY
```

---

## 5. 验证

### 5.1 不碰真实文件的整体验证

```bash
# 用临时配置把 output_path 全部重定向，post_hook 全部剥离，跑一遍完整渲染
# 期望：exit 0，35 个文件全部生成，产物里没有残留的 {{ }}
```

本次已跑过：35/35 通过，零报错，零残留占位符。

### 5.2 钩子单独验证

```bash
MATUGEN_HOOK_VERBOSE=1 bash ~/.config/matugen/hooks/post_hook.sh
```

本次已跑过，输出：

```
[matugen:debug] 检测到 WM=niri
[matugen] niri: 配置已重载
[matugen:debug] post_hook 完成
```

### 5.3 真实换一次壁纸

```bash
~/.config/scripts/matugen-update.sh          # 按当前壁纸重新取色
```

然后看：kitty 是否即时换色（需先做 §2.1）、niri 焦点环是否变、Qt 程序重启后是否变。

---

## 6. 已知坑

### 6.1 `~/.local/bin/matugen` 包装脚本与现状不符

包装脚本的注释描述的是「config.toml = 安全版 / config.hyprland.toml = 完整版」
双配置方案，但：

- `config.hyprland.toml` **不存在**
- `config.toml` 里**含** `[templates.hyprland]`（即完整版内容）

脚本里有 `[ -f "$HYPR_CFG" ] || exec "$REAL" "$@"` 兜底，所以在 Hyprland 会话里
它会静默退回读 `config.toml`，行为上没问题。但注释和实际是脱节的。

两条路选一条：

```bash
# 路线 A：恢复双配置
cp ~/.config/matugen/config.toml ~/.config/matugen/config.hyprland.toml
# 再从 config.toml 里删掉 Hyprland 专有段落

# 路线 B：简化包装脚本，只保留「显式 -c 就透传」的行为
```

### 6.2 Kvantum 模板是「整文件快照」

`templates/kvantum/MaterialAdw.kvconfig` 是现有主题文件的 569 行完整副本，
只把颜色键换成了占位符。**如果你换掉 Kvantum 主题（比如重装 Colloid），
这个模板就过期了**，需要按新文件重新生成一次。

### 6.3 Kvantum 的 SVG 故意没有做模板

`MaterialAdw.svg` 里有一段 `<style id="current-color-scheme">`，定义
`.ColorScheme-Highlight` / `-Background` / `-ViewText` / `-ButtonBackground` 等类。
这是 Kvantum 的**自动替换**机制 —— 它在渲染时按当前配色方案覆写这些类。

给它做模板会做两件坏事：

1. 和 Kvantum 自己的替换打架，谁最后写谁赢，结果不可预测；
2. SVG 里 365 处 `#FFFFFF` 是 opacity 蒙版用的，替换成主题色会把控件直接画糊。

所以正确链路是：`Matugen.colors`（配色方案）→ Kvantum 自动替换 SVG 里的语义类；
再加 `MaterialAdw.kvconfig` 的 `[GeneralColors]` 覆盖几何色。

### 6.4 `niri msg action` 的动作名

不是 `reload-config`，是 **`load-config-file`**。写错的话 niri 会返回
`unknown action`，钩子里静默失败。

---

## 7. 接线审计（2026-10-02）

「模板生成了」和「程序读到了」是两件事。逐条核对每个 `output_path` 是否真的
被消费方引用，结果如下。

### 7.1 断裂点：生成了但没人读

| # | 位置 | 症状 | 证据 | 状态 |
|---|---|---|---|---|
| A1 | `~/.config/niri/hyprlock.conf:3` | source 一个不存在的文件 | `source = ~/.cache/matugen/hypr/colors.conf`，该路径无写入者 | **已修**（见下） |
| A2 | niri `environment` 段 | Kvantum 在 niri 会话不生效 | `QT_QPA_PLATFORMTHEME "gtk3"`，无 `QT_STYLE_OVERRIDE=kvantum` | **不改**，见下 |
| A3 | `~/.config/kdeglobals:136` | 用的是过期配色 | `ColorScheme=MaterialYouDark`（调色板 `#1c1d23`），当前 matugen 产出 `#171216` | **不改**，见下 |
| A4 | `~/.config/obs-studio/` | OBS 主题没被选中 | `themes/matugen.obt` 已生成，但配置里没有主题键 | **待你确认**，见下 |

#### A1 已修：新增了一份独立模板

路径对不上只是表象。真正的坑是**变量集完全不重叠**：

| 主配置 | 需要的变量 |
|---|---|
| `~/.config/hypr/hyprlock.conf` | `$text_color` `$entry_color` `$entry_border_color` `$entry_background_color` `$font_family` `$font_family_clock` `$background_image` |
| `~/.config/niri/hyprlock.conf` | `$primary` `$secondary` `$tertiary` `$error` `$surface` `$surface_container` `$on_surface` |

原来只有第一份的模板。所以只改路径仍然解析不到变量。现新增：

- 模板 `templates/hyprland/hyprlock-colors-niri.conf`
- 配置 `[templates.hyprlock_niri]` → `~/.cache/matugen/hypr/colors.conf`

消费方（niri 会话）：`binds.kdl:60`（Mod+Alt+L）、`scripts/powermenu:29`、`:38`，
都用 `hyprlock -c ~/.config/niri/hyprlock.conf`。

#### A2 不改：Qt 在 niri 下本来就有色

`/usr/lib/qt6/plugins/platformthemes/libqgtk3.so` 与 Qt5 的同名插件**都已安装**，
所以 `QT_QPA_PLATFORMTHEME=gtk3` 是有效的：Qt 程序走 GTK 平台主题，
颜色来自 GTK 主题（matugen 生成的 `gtk-3.0/gtk.css`）。**不是没色，是走另一条路。**

Kvantum 只在 Hyprland 会话生效（那边是 `QT_QPA_PLATFORMTHEME=kde` +
`kdeglobals widgetStyle=kvantum-dark`）。

要让 niri 也走 Kvantum，把 `~/.config/niri/config.kdl` 的 environment 段改成：

```kdl
QT_QPA_PLATFORMTHEME "kde"
QT_QPA_PLATFORMTHEME_QT6 "kde"
QT_STYLE_OVERRIDE "kvantum"
```

代价：Qt 程序的控件渲染从 GTK/Fusion 风格变成 Kvantum 的 MaterialAdw 风格，
观感会变。这是你的选择，没有替你改。

#### A3 不改：DMS 在管这条链

DMS 二进制里含 `DATA_DIR/kdeglobals` 和 `qt6ct.conf` 两个路径字符串 ——
**niri 会话下 DMS 会写 kdeglobals 与 qt6ct.conf**（它也写
`DankMatugen{,Dark,Light}.colors`）。跟它抢同一个文件只会互相覆盖。

所以 `Matugen.colors` 目前只在 Hyprland 会话有意义（那边没有进程更新 kdeglobals）。
`hooks/post_hook.sh` 里 §3.6 有一段注释好的同步代码，要用再解注释。

#### A4 待确认：OBS

OBS 的主题键是 `[Appearance] CurrentTheme3`（在 `~/.config/obs-studio/user.ini`，
该段已存在，含 `FontScale` / `Density`）。值应该填主题 id
`com.obsproject.matugen`（见 `themes/matugen.obt` 第 3 行）。

**没有替你改**：`~/.config/obs-studio/` 不在 dotfiles 仓库的跟踪范围内，
写错了也验证不了。最稳的是开 OBS → 设置 → 外观 → 主题，手动选一次 Matugen，
OBS 自己会把键写对。

A2 的对照：Hyprland 侧是 `hl.env("QT_QPA_PLATFORMTHEME", "kde")` +
`kdeglobals widgetStyle=kvantum-dark`，**Kvantum 在 Hyprland 会话是生效的**。
所以同一个 Kvantum 模板，两个会话一活一死。

### 7.2 已验证正常的消费链

| 程序 | 引用点 |
|---|---|
| niri | `config.kdl:108` `include "matugen-colors.kdl"` |
| hyprland | `hyprland.lua:45` `require("hyprland.colors")` |
| hyprlock (Hyprland) | `hyprlock.conf:1` `source=~/.config/hypr/hyprlock/colors.conf` |
| kitty | `kitty.conf:62` `include current-theme.conf` |
| foot | `foot.ini:3` `include=~/.config/foot/matugen.ini` |
| fuzzel | `fuzzel.ini:1` `include="~/.config/fuzzel/fuzzel_theme.ini"` |
| alacritty | `alacritty.toml:31` `import = ["~/.config/alacritty/matugen-theme.toml"]` |
| mako | `mako/config:1` `include=~/.config/mako/colors.conf` |
| btop | `btop.conf:5` `color_theme = "ii-auto"` |
| waybar | `style.css:1` `@import "colors.css"` |
| walker | `config.toml:9` `theme = "matugen"` |
| micro | `settings.json` `"colorscheme": "matugen"` |
| nvim | `lua/plugins/transparent.lua:22` `pcall(vim.cmd.colorscheme, "matugen")` |
| GTK3/4 | `settings.ini` `gtk-theme-name=adw-gtk3-dark` |

### 7.3 孤儿模板（存在于 `templates/`，`config.toml` 未引用）

**软件已装或格式现成，值得接线：**

- `qtct-colors.conf` —— qt5ct/qt6ct 调色板，21 色顺序完整。qt6ct 装上即可用
- `steam.css` —— 内容是 GTK4 的 `:root` 变量版，看名字给 Steam 客户端 CSS 用
- `niriswitcher-colors.css` —— niriswitcher 未装（niri 配置里有注释掉的自启行）

**重复或过期，建议删/归档：**

| 文件 | 取代者 |
|---|---|
| `gtk-colors.css` | `gtk-3.0/gtk.css` |
| `kitty-colors.conf` | `kitty/current-theme.conf` |
| `mako-colors.conf` | `mako/colors.conf` |
| `starship-colors.toml` | `starship.toml` |
| `swaync-colors.css` | `swaync/colors.css` |
| `fuzzel.ini` | 是主配置（含 include），放错位置 |
| `neovim/init.lua`、`neovim/template.lua` | 整个 nvim 配置的引导，不是配色模板 |
| `miyu-theme.css` | miyu 未装；注释引用的同目录 README.md 也不存在 |
| `kde/kde-material-you-colors-wrapper.sh` | DMS 接管后已不需要 |
| `style.css` | 用 `--bg-color`/`--urgency-color`，归属不明 |

**素材（不是模板，正常）：** `gtk-folder/Adwaita-Matugen/**` 是 `recolor.sh` 的输入。

### 7.4 配色方案文件冗余

`~/.local/share/color-schemes/` 现有 **12 个** `.colors`，三个写入者：

- matugen → `Matugen.colors`
- DMS → `DankMatugen.colors` / `DankMatugenDark.colors` / `DankMatugenLight.colors`
- 旧的 `MaterialYou*`（6 个）→ 残留，但 `kdeglobals` 偏偏指着其中一个

---

## 8. 回滚

```bash
cp ~/.config/matugen/config.toml.bak-20261002-0630 ~/.config/matugen/config.toml
rm -rf ~/.config/matugen/hooks
# 新增的模板文件删不删都行，不引用就不会被执行
```

`config.niri.toml` 是指向 `config.toml` 的软链，回滚后自动跟着回去。
