# 更新日志

> 本文件记录所有历史变更。用法说明见 [README.md](README.md)。

## 2026-09-26

### niri：合成器换成 niri-spicy-git，配置与 install.sh 同步

合成器从 AUR 的 `niri-shorin-fork-git` 换成 `niri-spicy-git`（losnoco/niri 的
`spicy-main` 分支，v26.04.r219.gd9131c3）。换完 `niri validate` 报一堆解析错——
spicy 的「spice」是 HDR（含 peak-luminance override）、per-output `allow-tearing`、
Vulkan 渲染器、color-management、窗口最小化、wp-fifo / commit-timing /
tearing-control 等协议，**不含** shorin-fork 的那几项。以下节点全部停用（保留注释
说明原因，换回 shorin-fork 时去掉注释即可）：

| 文件 | 改动 |
|---|---|
| `config.kdl` | 删 `cursor.shake-to-enlarge`；删顶层 `magnifier` / `grid-overview`；热角 `bottom-left { grid-overview; }` → 纯 `bottom-left`（spicy 的热角只是开关，动作固定 open overview） |
| `binds.kdl` | 停用 `adjust-magnifier-zoom` ×2 / `toggle-magnifier` |
| `binds-hyprland-migrated.kdl` | `Mod+Shift+Space` 的 `toggle-grid-overview` → **`toggle-overview`**；`Mod+Minus`/`Mod+Equal` 的 `adjust-magnifier-zoom` 停用 |
| `rule.kdl` | 停用带 `ignore-grid-overview` 的 window-rule |
| `animations.kdl` | 删 `grid-overview-open-close`（spicy 只有 `overview-open-close`） |
| `matugen/templates/niri-colors.kdl` | 删 `screen-cast-picker` 配色节点 |

⚠ `screen-cast-picker` 同时存在于模板和 matugen 产物
`~/.config/niri/matugen-colors.kdl`，**两边都要改**，否则下次换壁纸重新生成又会把
它写回来，配置再次加载失败。产物文件不在 chezmoi 纳管范围内（matugen 生成物）。

另外 spicy **不支持「单独一个 `Mod` 键」的绑定**（`invalid key: Mod`），所以
`dms/binds.kdl` 里「轻触 Super → 启动器」那条作废，启动器改走已有的 `Mod+Space`。
注意该文件会被 `dms setup binds` 重写，届时那条绑定会回来。

**install.sh**：`compositor_pkgs()` 里 niri 那支原本装官方仓库的 `niri`，现在只留
`xdg-desktop-portal-gnome`；niri 本体新开 `compositor_aur_pkgs()` 走 AUR 的
`niri-spicy-git`（它 `conflicts=('niri' 'niri-bin')`，装之前加了冲突检测提示）。
这同时解决了 2026-09-23 那条遗留——原本写着「先不改 install.sh，真要改就换成
`niri-shorin-fork-git`」，实际换成了 spicy，包名按当前分支写。

**README**：环境要求里的 niri 条目从「必须 SHORiN fork」改成 spicy 分支，列出它
多出来的能力，并写明本仓库配置**不含** shorin-fork 独有节点（换分支后先
`niri validate`）；安装步骤 [1/7] / [2/7] 的包名同步。

### niri 键位：三键顺移（同日）

按「轻触 Super 的功能 → Alt+Tab，Alt+Tab 的功能 → Super+Tab」顺移：

| 键位 | 改后 | 改前 |
|---|---|---|
| `Alt+Tab` | DMS 启动器（`dms ipc call launcher toggle`） | recent-windows 正向 `next-window` |
| `Super+Tab` | 总览 `toggle-overview` | recent-windows 正向（中间态） |
| `Alt+Shift+Tab` | **删除** | `previous-window` |
| `Super+Space` | 启动器（未动，备用入口） | 启动器 |

`recent-windows` 的触发键只剩 `Super+Shift+Tab`（反向）、`Super+grave` /
`Super+Shift+grave`（同应用内）—— 正向入口按需求不再保留。

**「轻触 Super」以前为什么能用**：靠两条 shorin-fork 专属配置**配合**，缺一不可——
`dms/binds.kdl` 的 `Mod repeat=false`（把单独一个修饰键当绑定）和 `config.kdl` 的
`grid-overview { default-mod-action false }`（关掉内建的「轻触 Mod = 开网格总览」，
否则会和启动器一起触发）。spicy 两条都不认，所以换分支后这个功能必然消失，
不是配置写错。它的落点改成 `Alt+Tab`，不依赖轻触 Super，也就不用换分支、
不用装 keyd。

真想要「轻触 Super」只剩两条路，两行备选都已在 `dms/binds.kdl` 顶部注释备好：
① 换回 `niri-shorin-fork-git`，取消 `Mod repeat=false` 的注释并恢复
`grid-overview { default-mod-action false }`；② 留在 spicy，用 keyd
（`leftmeta = overload(meta, f13)`）把轻触 Super 映射成 F13，再绑 F13 → 启动器。

⚠ `dms/binds.kdl` 会被 `dms setup binds` 重写，届时这里的键位改动会丢失。

## 2026-09-23

### caelestia shell 简体中文化

caelestia 自带 gettext i18n 框架（`Tr.tr()` → C++ `Translator` 读 `.mo`），但上游
`plugin/src/Caelestia/I18n/CMakeLists.txt` 的 `po_files` 是**空的** —— 框架搭好了、
一条翻译都没有，界面全英文。这次补齐。

- **`trs/zh_CN.po`**：用官方 `scripts/trs.fish raw`（xgettext）提取全部 **821 条**文案
  （187 条带 context、11 条复数）并翻译。系统 `LANG=zh_CN.UTF-8` 时
  `general.language` 留空即自动命中；也可在 nexus → 语言与地区 → UI 语言里选「中文」。
- **`CMakeLists.txt`**：`po_files` 加入 `trs/zh_CN.po`，`.mo` 经 `qml_module` 编入插件
  资源（`:/qt/qml/Caelestia/I18n/zh_CN.mo`）。复数条目按中文规则 `nplurals=1` 只保留
  `msgstr[0]`。

**install.sh**：caelestia 不走 chezmoi 部署，`[4/7]` 是「clone 到
`~/.config/quickshell/caelestia` + out-of-source 编译」，而差异层要到 `[5/7]` 才落地 ——
**晚于编译**。所以在 `install_caelestia_shell()` 里加了「编译前先应用
`dot_config/quickshell/caelestia/` 覆盖层」这一步，并用 `$build/.overlay-stamp` 记录
覆盖层 hash：变了才重编，没变就跳过。否则重装后 po 文件在、翻译却不生效（静默故障）。

**顺带修的 bug**：`dot_config/fish/executable_config.fish` 与
`dot_config/hypr/hyprland/execs.lua` 里的 `QML2_IMPORT_PATH` 还写着旧的
`~/src/caelestia-shell/build/qml`，而 install.sh 编译到 `~/src/caelestia-build` ——
工作树早改对了、差异层没同步，重装会**静默加载不到插件**（和字体漏装同类故障）。
两份文件已按工作树现状同步进差异层。

### Neovim：从「VS Code 手感」转向「边用边学 vim」

原配置已经做过一轮「非模态化」（`Ctrl+S/C/V/Z/...` 全映射）。但如果目标是**学 vim**，
这套改造是反作用：有 Ctrl 兜底，就永远不会被迫学会 `yy` / `p` / `u`。这次按
「**保留不是 vim 动词的键，把 vim 动词还给 vim**」重排。

**拆掉的键**（完整对照见 [docs/nvim-keymaps.md](docs/nvim-keymaps.md)）：

| 拆掉 | 改用 | 备注 |
|---|---|---|
| `Ctrl+A` | `ggVG` | 全选 |
| `Ctrl+C` / `Ctrl+X` / `Ctrl+V` | `y` / `d` / `p` | 已开 `clipboard=unnamedplus`，`y` 直接进系统剪贴板 |
| `Ctrl+Z` / `Ctrl+Y` | `u` / `Ctrl+r` | ⚠️ normal 模式下 `Ctrl+Z` 现在会**挂起** nvim（原生行为），`fg` 恢复 |

拆掉后回归的原生含义：`Ctrl+V` 块选择、`Ctrl+A` / `Ctrl+X` 数字加减。

**保留的 Ctrl 键**（都不是 vim 动词）：`Ctrl+S` 存盘、`Ctrl+P` 找文件、
`Ctrl+F` 搜当前文件、`Ctrl+B` 文件树、``Ctrl+` `` 终端、`Ctrl+/` 注释、
`Alt+j/k` 移行、`Ctrl+←/→` 跳词。它们和对应的 `<leader>` 键指向同一套工具。

**修好的坏键**：`Ctrl+B` / `Ctrl+P` / `Ctrl+F` 原来绑到 Neotree / Telescope，
但这三个插件根本没装，按下去直接报错。现在 extras 加了
`editor.telescope` + `editor.neo-tree`，snacks 的 picker / explorer 自动失能
（LazyVim 的 `get_defaults()` 按 `has_extra()` 决定默认项，不会重复注册 picker）。
终端维持 snacks 的，因为 LazyVim **没有** toggleterm 的 extra，手写会变成两套终端。

**顺带修的 bug**：`Ctrl+/` 原来映射成 `gcc` 且覆盖了插入模式——插入模式下 `gcc`
会被当成普通字符直接打进正文。改成插入模式走 `<C-o>gcc`。

**新增**：

- `hh-hg/fcitx.nvim`：离开插入模式自动切英文、进入自动恢复中文，按 buffer 记忆。
  前提是 fcitx5 输入法列表「英文第一、中文第二」（本机 `keyboard-us` / `rime` 已满足）。
  配套把插入模式 `Ctrl+C` 映射为 `Esc`——原生 `<C-c>` 退出插入模式
  **不触发 `InsertLeave`**，会导致输入法不切回英文。
- `guicursor`：normal 方块 / insert 竖线 / replace 下划线，解决「不知道自己在哪个模式」。
- 删掉 LazyVim 的 `j`/`k` → `gj`/`gk` 映射，还原原生的逻辑行移动。
- `dot_config/neovide/config.toml`：neovide GUI 前端，字体对齐 kitty
  （JetBrainsMono Nerd Font / 11.0）。
- `docs/nvim-keymaps.md`（速查表）、`docs/nvim-learning.md`（分阶段学习清单）。

**install.sh**：`PACMAN_PKGS` 补 `neovim ripgrep fd fzf lazygit tree-sitter-cli neovide`。
之前只跟踪了 `dot_config/nvim/` 却没跟踪包本体，新机器装完是「**有配置、没编辑器**」，
而且 install.sh 不会报任何错——和字体漏装是同一类静默故障。

**`~/.vimrc` 纳入仓库**（`dot_vimrc`）：它管 vim 的 fcitx5 自动切换与剪贴板降级。
nvim 不读它，纳管只为防重装丢。

### 字体方案：换成 MiSans + 按语言切换 CJK 地区字形

整体替换为 [emoeem/fontconfig](https://github.com/emoeem/fontconfig) 的方案（旧的
2026-09-20 那套已备份为 `~/.config/fontconfig/fonts.conf.bak.20260923-031328`）：

| 用途 | 旧方案 | 新方案 |
|---|---|---|
| UI / 正文 | 思源黑体 CN（只有 Chrome 用霞鹜文楷等宽） | **MiSans**（全局） |
| 阅读 / serif | 霞鹜文楷 | **霞鹜臻楷 GB** → 霞鹜文楷屏幕阅读版 |
| 代码 / monospace | JetBrains Maple Mono | **Maple Mono Normal NF CN** |
| 日文内容 | 不区分 | Noto Sans / Serif CJK **JP** |
| 韩文 / 繁中 | 不区分 | Noto Sans CJK **KR / TC / HK** |

**新增的核心能力：按语言切换地区字形。** 用 `<test name="lang" compare="contains">`
匹配 lang —— 浏览器按页面 `<html lang>`、GTK/Qt 按 `LC_*` 传入。日文网页的
「直、门、关」出日文字形，繁中网页出繁体字形。

⚠️ **规则顺序就是优先级**：fontconfig 按**规则执行顺序**排列 prepend 的值，
**先执行的规则排得越靠前**（与「prepend 插到最前」的直觉相反）。所以顺序必须是
`网页字体映射 → 语言地区规则 → 默认字体规则`：语言规则在前，JP/TC 字体才压得住
MiSans；默认规则在后，MiSans 仍排在发行版偏好之前。改配置别打乱。

**已知代价**（上游 README 也列了）：
- `Arial` / `Segoe UI` / `Liberation Sans` 被 `assign` 到 sans-serif，依赖 Arial
  度量的文档（如 LibreOffice 排版）会有偏移
- 旧的 `prgname=chrome` strong prepend 已删除，**Chrome 网页的楷体效果没有了**
- 分数缩放（125% / 150%）下 `rgba=rgb` 亚像素抗锯齿会出彩色边缘，改 `none` 即可

**字体来源**（install.sh 已同步）：
- AUR：`otf-misans`、`maplemononormal-nf-cn`、`ttf-lxgw-wenkai-tc`、
  `ttf-lxgw-wenkai-screen`
- 手动下载：霞鹜臻楷 GB —— AUR 没有对应包，install.sh 里新增了从
  `lxgw/LxgwZhenKai` Release 自动下载（已存在则跳过）

> 上游 README 有三处笔误，照抄会踩坑：`ttf-lxgw-zhenkai`（AUR 不存在）、
> `ttf-maplemononormal-nf-cn`（实际是 `maplemononormal-nf-cn`，无 `ttf-` 前缀）、
> 霞鹜臻楷仓库链接 `LxgwZhenKaiGB`（实际是 `LxgwZhenKai`）。

> 生效方式：`fc-cache -f` 之后**重启浏览器和已运行的应用** —— fontconfig 的新规则
> 对已启动的进程不生效。

### install.sh

- AUR 列表加 4 个字体包（`otf-misans` / `maplemononormal-nf-cn` /
  `ttf-lxgw-wenkai-tc` / `ttf-lxgw-wenkai-screen`）
- 新增霞鹜臻楷 GB 的 GitHub Release 下载（放在 fc-cache 之前，已存在则跳过）
- 思源黑体注释改写：不再是 fontconfig 别名的目标，保留是因为 GTK `settings.ini`
  与 fcitx5 `classicui.conf` 里硬编码了它

### 字体方案（续）：霞鹜文楷接管衬线族

上一节把 serif 定为「霞鹜臻楷 GB → 文楷屏幕阅读版」。这一节改成**文楷为主**，
并把整个衬线族搬进独立的 `conf.d` 片段。

**最终衬线链**（`dot_config/fontconfig/conf.d/50-lxgw-wenkai.conf`）：

| 请求 | 解析到 |
|---|---|
| `serif` / `lang=zh-cn` | `Noto Serif`（拉丁）→ **霞鹜文楷 Medium**（中文逐字回退） |
| `lang=zh-tw` / `zh-hk` | 霞鹜文楷 TC → Noto Serif CJK TC（与上一节一致，未变） |
| `lang=ja` / `ko` | Noto Serif CJK JP / KR（与上一节一致，未变） |
| `KaiTi` / `楷体` | 霞鹜文楷 Medium（新增别名映射） |
| `Georgia` / `Times` | `serif` → Noto Serif（新增映射） |
| `宋体` / `SimSun` / `Songti SC` | Noto Serif CJK SC（新增映射，真宋体，不并入文楷） |

**补上了衬线字体名的映射缺口。** 原配置的「网页字体映射」只处理无衬线的名字
（Arial / Segoe UI / Liberation Sans），衬线名字没人管，实测 `Georgia` / `Times` /
`宋体` / `SimSun` 全都落到**黑体**（文泉驿正黑或 MiSans）。网页上写这些名字的不少。

⚠️ 这些映射**只能写在片段里，不能写进 fonts.conf**：`<edit mode="assign">` 只影响
「之后」执行的规则，而片段先于 fonts.conf 加载——写在 fonts.conf 里的映射永远喂不到
片段的链规则。实测：把 `Georgia → serif` 放进 fonts.conf，`fc-match Georgia` 拿到的是
**兜底链的臻楷 GB**，不是真链的 Noto Serif。放进片段后 `fc-match Georgia` 才等于
`fc-match serif`（Firefox 里两者像素完全相同）。

- **拉丁用 `Noto Serif`**：它不含任何 CJK（`fc-list :family="Noto Serif" :charset=4e00`
  为空），所以能安全地排在链首——西文走正经衬线，中文逐字回退到文楷。
  代价是不做逐字回退的老程序中文会出豆腐块。
- **正文用 `LXGW WenKai Medium`**：家族名直接写 `Medium` 就能选中中等字重
  （`fc-match "LXGW WenKai Medium"` → `LXGWWenKai-Medium.ttf`），比屏幕阅读版厚，
  解决「文楷太细」。文楷全系没有 Bold / Italic，粗斜体由渲染器合成。
- **按字体调渲染没做**：实测文楷不含任何 TrueType 微调指令（无 `fpgm` 表、
  0 个字形带指令），`hinting=true` + `hintstyle=hintslight` 对它本来就是空转，
  没有可调的东西。

**关键发现：`conf.d` 的优先级高于 `fonts.conf`。**
`/etc/fonts/conf.d/50-user.conf` 先 include `fontconfig/conf.d`、再 include
`fontconfig/fonts.conf`，而 prepend 是「先执行的排得更前」，所以片段的规则必然压过
`fonts.conf`。实测：在片段里放一条无条件的 `serif` 规则，`fc-match serif:lang=zh-tw`
就从「文楷 TC」变成片段里的字体——**地区规则会被静默抢走**。

因此 `fonts.conf` 里原有的 4 条衬线地区规则 + 默认衬线规则**已整体搬进片段**，
原位置留了指针注释。现在职责是：`fonts.conf` 管无衬线（MiSans）与等宽（Maple Mono），
片段管衬线（文楷）。**片段是衬线族的唯一定义处**——删掉它不会回到旧方案，
而是让 serif 回落到发行版的「文泉驿正黑」（黑体），要弃用得先把默认链搬回去。

> 顺带踩的坑：fontconfig 手册写了 `compare="not_contains"`，但 **2.18.3 上对 `lang`
> 实测不生效**（`contains` 正常）。本想用它给 ja / ko / 繁中开豁免、做成纯加法片段，
> 结果所有语言都被命中，只好改为在片段里重述四条语言规则。

> **无需安装任何新字体**：`ttf-lxgw-wenkai`（1.522，含 Medium）/ `-screen`（1.520）/
> `-tc`（1.520）本机都已存在。后两个比上游低一个小版本，未升级。

> 生效方式：`fc-cache -f` 之后重启浏览器和已运行的应用（fontconfig 新规则对已启动的
> 进程不生效）。验证：`fc-match serif` / `fc-match "serif:charset=4e00"` /
> `fc-match KaiTi`。

### niri：外观数值收回自管 + 清遗留 + 启用 fork 独有功能

这一轮的目标是**加新外观/新功能**，顺带把摸出来的坑先清掉。改动集中在
`dot_config/niri/`、`dot_config/xdg-desktop-portal/`、光标相关的四个文件。

#### 1. 间距 / 边框 / 焦点环 / 圆角：新增自有覆盖层

`dms/layout.kdl` 是 DMS **自动生成**的（`gaps 4` / `border 2` / `focus-ring 2` /
圆角 18），而且在 `config.kdl` 里被 include 在很靠后的位置，是这几个数值的最终来源
——直接改它会被 DMS 覆写。

新增 `dot_config/niri/override-layout.kdl`，并在 `config.kdl` 末尾
`include "override-layout.kdl"`（必须排在 `dms/layout.kdl` 之后才拿得到话语权）。
最终取值 **间距 10 / 边框 4 / 焦点环 3 / 圆角 18**。

逐像素量过两套值的实际差别（都是同一场景、同一裁剪位置截屏后数像素）：

| | DMS 值 4/2/2/18 | 采用值 10/4/3/18 |
|---|---|---|
| 屏幕边→窗口（外间距） | 4px | 10px |
| 两窗之间的色带 | **4px**：2px 灰边 `#9f8c8e` + 2px 粉环 `#ffb2be`，**中间一点壁纸都不露** | 10px：7px 灰紫 + 3px 粉环 |
| 焦点环宽度 | 2px | 3px |
| 圆角弧线跨度 | ≈15px（配置 18） | 18px |

选 10/4/3 的理由就是第一行那 4px——DMS 的值下两个窗口之间被边框填满，太挤。
圆角保留 18：它和 DMS 面板/启动器/通知的圆角语言一致，用 niri 原本的 8 会显方正、
跟 DMS 观感打架。

#### 2. 光标：三处打架收敛到 DMS 单一来源

之前光标尺寸同时存在**三个值**：`environment` 里 34、`cursor{}` 块里 24
（`catppuccin-mocha-flamingo-cursors`）、DMS 生成的 `dms/cursor.kdl` 里 32。
实际生效的是最后一个（它 include 得更晚），另外两个既误导人、又会让
Qt/Electron/GTK 程序跟 Wayland 原生程序对不上。

现在唯一来源是 DMS 的 `settings.json → cursorSettings`（Matugen-Cursors / 32），
其余位置全部对齐或删除：

| 文件 | 改动 |
|---|---|
| `niri/config.kdl` `environment` | `XCURSOR_SIZE` 34 → **32** |
| `niri/config.kdl` `cursor{}` | **删掉** xcursor-theme / xcursor-size 副本，只留 `hide-after-inactive-ms` 与 `shake-to-enlarge` |
| `environment.d/cursor.conf` | catppuccin/24 → **Matugen-Cursors / 32**（原文件是 Hyprland 时代残留，注释还写着「Hyprland 会动态更新」） |
| `gtk-3.0/settings.ini`、`gtk-4.0/settings.ini` | `gtk-cursor-theme-size` 34 → **32** |
| `xsettingsd/xsettingsd.conf` | `Gtk/CursorThemeSize` 34 → **32** |
| `~/.icons/default/index.theme`（新增 `dot_icons/`） | `Inherits` 从 `catppuccin-mocha-**pink**-cursors` → **Matugen-Cursors** |

> ⚠️ 顺带发现：**`xsettingsd` 其实根本没在运行**。XSETTINGS 由 Xwayland 内建管理器
> 提供（`dump_xsettings` 只回 `Gdk/WindowScalingFactor` / `Xft/DPI` / `Gdk/UnscaledDPI`
> 三个键，没有任何光标项），所以 `xsettingsd.conf` 里的光标配置一直是空转的。
> XWayland 程序（LinuxQQ 等）实际是从 `~/.icons/default/index.theme` 取光标——
> 上面那一行改动才是真正生效的那处。

验证：`niri msg action spawn -- sh -c 'echo $XCURSOR_SIZE'` → `32`；
systemd user session 也用 `set-environment` 同步（`environment.d` 要重新登录才读）。

#### 3. 启用 fork 内置的录屏 / 截图 portal

`~/.config/xdg-desktop-portal/niri-portals.conf` 原来把 `ScreenCast` / `Screenshot`
指向 `gnome`，于是 fork 自带的 niri portal（DBus 名
`org.freedesktop.impl.portal.desktop.niri`，由 **niri 本体**持有）一直闲置，
走的其实是 GNOME 的实现。改为 `niri`。

同时补上 `Secret = gnome-keyring`：`gnome` 与 `gtk` 后端**都不提供**
`org.freedesktop.impl.portal.Secret`，只靠 `default = gnome;gtk` 兜不住，
密钥环相关的程序会拿不到 Secret portal。

验证方式（不是看配置文件，而是看总线上真实流向）：`dbus-monitor` 挂
`interface='org.freedesktop.impl.portal.ScreenCast'`，再通过前端发起
`CreateSession`。结果唯一收到的 destination 是 `:1.798`，即
`org.freedesktop.impl.portal.desktop.niri`（pid 574109 = `niri --session`）；
gnome 后端（`:1.825`）一次都没收到。测完 `niri msg casts` 无残留会话。

> `niri` 的 portal 后端由 fork 编译进 niri 本体，不需要额外装包。
> `xdg-desktop-portal-gnome` 仍然要留——`default = gnome;gtk` 兜的是
> Settings / Inhibit / Account 等没显式列出的接口。

#### 4. 显式写出热角

之前没有 `gestures` 块，热角处于 niri 默认（左上角 → overview、左下角 →
grid-overview）。现在显式写成：

```kdl
gestures {
    hot-corners {
        top-left
        bottom-left { grid-overview; }
    }
}
```

行为上等于空操作，价值在于自解释、且不受将来 niri 改默认值影响。
可用动作只有 `overview` 与 `grid-overview`。

#### 5. 补 3 个未配置动画 + 开光标 grow

| 动画 | 取值 | 说明 |
|---|---|---|
| `grid-overview-open-close` | `1.0 / 900 / 0.0001` | 对齐上面的 `overview-open-close`，两种总览手感一致 |
| `config-notification-open-close` | `0.6 / 1000 / 0.001` | niri 设计值（刻意欠阻尼、收尾轻微回弹） |
| `exit-confirmation-open-close` | `0.6 / 500 / 0.01` | 同上，niri 设计值 |

`cursor.shake-to-enlarge` 打开 `grow`：持续晃动时让光标逐步变大，
而不是直接跳到 `zoom-factor`（`grow-speed 0.01` 本来就是默认值，已在配置里）。

> ⚠️ 名字要小心：`grid-overview-open-close` 是 **fork 独有**的（上游 wiki 查不到），
> 本机 `niri validate` 接受。反过来，`recent-windows-open-close`（上游叫
> `recent-windows-close`）与 `vertical-view-movement` 实测**不存在**，写了会报错。

#### 6. 清掉的遗留项

- **`Mod+Tab`（recent-windows 里那条）是死代码，已删。** niri 文档明确写着
  「recent-windows 的 bind 优先级**低于**普通 bind」，而 `Mod+Tab` 在
  `dms/binds.kdl` 里已经绑成了总览（普通 bind），所以这条永远不触发。
  保留 `Mod+Shift+Tab` / `Mod+grave` / `Mod+Shift+grave`（实测无冲突、可用）。
- `spawn-at-startup` 三行：`niri-sidebar listen`（end4-pC 遗留，DMS 接管后不再需要）、
  `xhost +si:localuser:root`（放宽 X11 访问权限，非必要不开）、
  `flatpak run com.github.wwmm.easyeffects -w`（音频效果器不必开机自启）。
- `rule.kdl` 里给 niri-sidebar 用的浮动窗口最小尺寸规则。
  ⚠️ 副作用：它同时也给**所有**浮动窗口兜了个 100×100 下限，删掉之后若某个浮动
  小窗开得极小，把这条规则加回来即可。
- `config.kdl.backup*` × 3（9/19 的旧快照）。

#### 7. 验证

`niri validate` 全程通过；journal 无配置错误。fork 独有功能实测：网格总览可开可关
——打开时与正常状态差 **21% 像素**，关闭后只差 **0.067%**（时钟/光标噪声）。

#### 8. 收尾：死键位注释 + 文档索引修复 + README 双合成器定位

三件不在 niri 主线上、但同批处理的事。

**（1）wordlens 死键位与死规则注释掉**

`wl-wordlens` 这个可执行文件本机并不存在（flatpak / pacman / `.desktop` / 数据目录里
都没有），所以 `Mod+F11` 与 `Mod+Shift+T` 按下去只是 spawn 失败，什么都不发生。
已注释掉两处：`binds.kdl` 里那两条键位、`rule.kdl` 里配套的
`match app-id="com.wordlens.app"`（同属浮动窗口白名单）。注释里写了「将来装上
wordlens 后取消注释即可」，两处互相指向，不至于将来只改一半。

**（2）`docs/README.md` 索引补全**

原索引只列 3 个文档，实际有 **16 篇**（不含索引自身），而且其中
`dynamic-island-roadmap.md` 文件名是错的（实际是 `dynamic-island.md`），链接打不开。
重写为按 5 个主题分组——合成器与外观 / 栏·岛屿·仪表盘 / 键位与编辑器 /
集成与本地化 / 排障——16 篇全部收录，18 个相对链接（含指向根目录 `README.md`
与 `CHANGELOG.md` 的两条）逐一验证有效。

**（3）根 README 补上 niri 双合成器定位**

根 README 原来通篇按 Hyprland 写：开头只说 Hyprland，安装步骤、快捷键、目录结构
也都只提 hypr。现在改成**双合成器**表述——Hyprland（默认）与 niri（滚动平铺）
二选一，niri 走 `COMPOSITOR=niri ./install.sh install`。要点：

- niri 条目明确标出**依赖 SHORiN fork**，并列出 fork 独有功能
  （`magnifier` / `grid-overview` / `shake-to-enlarge` / 内置 screencast portal）；
- 安装步骤里把合成器包拆开：Hyprland → `hyprland hypridle hyprlock` +
  `xdg-desktop-portal-hyprland`；niri → `niri` + `xdg-desktop-portal-gnome`；
- 快捷键由「一份列表」改为**分合成器给路径**，并说明「niri 是纯滚动平铺，
  所以那个键位恒为切换窗口」；
- 目录结构补全 `niri/` 全部条目、`xdg-desktop-portal/niri-portals.conf`、
  `DankMaterialShell/plugins/`，以及光标相关的四个文件
  （`environment.d/cursor.conf`、`gtk-3.0/`、`gtk-4.0/`、`xsettingsd/`，
  注明唯一来源是 DMS 的 `cursorSettings`）；
- 「文档与更新日志」由 14 条内联列表简化为「索引链接 + 常用 4 篇」，避免
  每加一篇文档都要动 README。

#### 遗留（未处理）

- **`install.sh` 的 `COMPOSITOR=niri` 路径装的是上游 `niri`**，而本仓库的 niri 配置
  依赖 SHORiN fork 独有功能（`magnifier` / `grid-overview` / `shake-to-enlarge` /
  内置 screencast portal，见该包描述）。新机器按这条路径装完，niri 会因**未知配置项
  拒绝加载配置**，录屏 portal 也不存在——和字体漏装属于同一类静默故障。
  本轮选择**先不改 install.sh**，只在根 README 的 niri 条目里加了 ⚠️ 提示；
  真要改的话，把这条路径的包名换成 AUR 的 `niri-shorin-fork-git` 即可。
- 装了但没用到的 portal 后端：`xdg-desktop-portal-hyprland` / `-kde` / `-wlr`
  （都是 activatable、未运行，无害，只是噪音）。

### niri 壁纸：三层收敛成两层，overview 里也能看到视频

起因是「感觉有三层壁纸，但会被覆盖」。查下来 background 层确实挤了 4 个
surface，而其中一层从来没露过脸。

#### 诊断

`niri msg layers` 显示 background 层有四个：

| surface | 谁拉起来的 | 画什么 |
|---|---|---|
| `mpvpaper` | DMS 的 mpvpaper 插件 | `yeqi.mp4` 视频 |
| `quickshell` | DMS 本体（主壁纸） | `MXBpbZp.png` |
| `awww-daemonoverview` | niri 的 `spawn-at-startup` | `MXBpbZp.png`（开机时从 DMS 读一次） |
| `dms:plugins:wallpaperCarousel:precache` | 轮播插件 | 预缓存，不直接显示 |

判断「平时看到的是哪个」用取色：窗口下方 gap 是 `(96,84,101)` 的灰紫
（`R≈G<B`），与 `yeqi.mp4` 同位置的 `(77,74,93)` 同调；而 `MXBpbZp.png`
那个位置是 `(78,25,36)` 的暗红（`R>>G`）。**平时是视频盖在最上面。**

> ⚠ 取样点的坑：第一版取在屏幕左边缘，放大后发现那里是 kitty 窗口内容
> （`#1E1E1E`）不是壁纸，整轮结论作废。**取样点必须先用 `-crop` 放大
> 确认是壁纸再往下做。**

#### 定位 backdrop 的真实来源

`rule.kdl` 里有三条 `place-within-backdrop true`（`dms:blurwallpaper`、
`^quickshell$`、`awww-daemonoverview`），但不清楚总览里的背景是谁贡献的。

手法：**把 awww 画的图临时换成纯绿**，再开总览截图对比采样点。

结果：5 个采样点颜色**逐点相等**（只有一处差 1/255 的噪声）——
awww 对 backdrop **毫无影响**。真正的来源是 `^quickshell$` 命中的
DMS 主壁纸 surface。

于是 awww 的定性是：正常桌面被 mpvpaper 盖住、总览里又不参与 backdrop，
**两头都不露脸**。它还有个隐患 —— `config.kdl` 里那行同步脚本是个 8 次
重试的 for 循环，**只在开机时跑一次**，之后换壁纸不会跟随。

#### 改动

1. **给 mpvpaper 加 `place-within-backdrop true`**（`rule.kdl`）——
   目标是「桌面是视频，进总览也还是视频」。实测生效：总览 backdrop 的
   采样点从清一色 `R>>G` 的红变成蓝紫/亮色，截图里能看到视频画面。
2. **删掉 awww**：`config.kdl` 的 `spawn-at-startup "awww-daemon" "-n" "overview"`
   与配套同步脚本两行、`rule.kdl` 里 awww 的 layer-rule，并停掉运行中的进程。
3. **保留 `^quickshell$` 那条** —— 它是兜底：mpvpaper 插件停掉时
   DMS 的静态壁纸会自动接管 backdrop，不会开天窗。

结果：background 层从 4 个 surface 降到 3 个，壁纸链路变成
「mpvpaper 画 + DMS 主壁纸兜底」。因为 mpvpaper 是 DMS 插件，在 DMS 里
换视频它会自己跟随，不像原来那个只在开机同步一次的脚本。

#### 验证

- `niri validate` → `config is valid`
- background 层 surface：4 → 3
- 正常桌面 gap 取色：改前 `(95,83,99)` / 改后 `(94,82,98)`，未受影响
  （差值来自视频不同帧，非配置副作用）
- 总览 backdrop：视频画面（采样点 `(80,900)=(20,16,33)`，蓝紫系）

## 2026-09-20

### 岛屿：修「打开时背景闪一下」

元凶是 `surface` 上的 `opacity: root.open ? 1 : 0` —— 面板从 0 透明度淡入时，
头几帧是半透明的，透出来的是**它背后的 Bar 紫色胶囊 + 壁纸**，看着就是
「以紫色为主色的彩色闪一下」。背景必须**从第 0 帧起就不透明**。

此前两次误判（`targetColor` 紫→深渐变、glass/flat 两层互换）的修正本身是对的、
予以保留，但都不是主因。排查手法：**对比改动前的提交**（`git diff 80dd40c HEAD`），
看多出来的那一段是什么。

顺带把收起动画改成**纵向收拢**（高度→0、宽度保持 ≥800），这样任何时刻都不可能
呈现胶囊形状，幻影 bug 不会复现，同时保住了「往 Bar 里收回去」的动感。

> ⚠ 教训：切页签时宽度走 400ms 动画**是刻意保留的视觉**，不要为了「即时」改 0ms。

### 岛屿：修「所有页面底部被裁剪」

只有 `Process.qml` 声明了 `availableHeight` 并写 `implicitHeight: availableHeight`；
`Dash / Media / Performance / WeatherTab` 都用固有高度，超出 `viewWrapper`
可用高度的部分被 `ClippingRectangle` 硬裁。已给这 4 个页签各包一层容器
（贴合 `paneHeight` + 内容超出可纵向滚动）。

### 仪表盘：新增 GitHub 页签

数据层与页面早就存在（`services/GitHub.qml` + `custom-island/DashGitHub.qml`），
只是没接线。第一版直接复用 `DashGitHub` 是**错的** —— 它用岛屿自家的
`StatCard / Theme.*`，与仪表盘不是一套画风。重写为 `dashboard/GitHubTab.qml`，
对齐 `StyledRect / StyledText / MaterialIcon / Tokens / Colours`。

命名用 `GitHubTab` 而非 `GitHub`，避免与 `qs.services` 的同名单例撞名。

踩坑：`MaterialIcon` 继承 `StyledText`，但要设 **`fontStyle`** 不是 `font` ——
写 `font:` 会覆盖它算好的图标字体（含 Material Symbols 字族与 FILL/GRADE 变体轴），
结果图标不渲染、退化成字面文本（`star` / `fork_right` 直接显示成英文）。

### niri ↔ Hyprland：合成器层模糊与透明度对齐

以 niri 的数值为准移植到 Hyprland，新增 [docs/compositor-effects.md](docs/compositor-effects.md)
记录参数对照与三个坑：

1. niri 的 `offset` 是 dual kawase 的**每 pass 偏移乘数**，不是模糊半径
2. niri 的 `saturation` 在 Hyprland **没有对应项**（`vibrancy` 是渗透量，非饱和度倍率）
3. niri **无 active/inactive 之分**（全局 0.97），Hyprland 两侧都设 0.97 才等价

另外 `decoration.blur.size` / `active_opacity` 等在 `shellOverrides/main.lua`
（DMS 生成、加载顺序最后）里，`custom/general.lua` 覆盖不掉。

### 移除 SUPER + A

原绑定在 0.65 ↔ 1.0 之间切换 `active_opacity`，会直接破坏刚对齐的 0.97。
相邻的 `SUPER+ALT+A`、`SUPER+SHIFT+A` 未误删。

### 字体方案：思源黑体 + 霞鹜文楷 + Maple Mono

1080p 下选定（并用实际字号渲染对比图确认）：

| 用途 | 字体 |
|---|---|
| UI / 正文 | 思源黑体（Source Han Sans CN） |
| Latin | Google Sans（无中文字形，中文靠回退链） |
| 阅读 / 文档 | 霞鹜文楷（走 serif 别名） |
| 代码 | JetBrains Maple Mono + **霞鹜文楷等宽** |

两处实测校正：
- 原配的 `Noto Sans Mono CJK SC` **不含中文字形**（`fc-list ":charset=6c38"` 查不到），
  带中文的等宽只有霞鹜文楷等宽和文泉驿等宽正黑 —— 否则代码里的中文是豆腐块
- `/etc/fonts/conf.d/65-wqy-zenhei.conf`（编号 65，晚于用户配置的 50-user.conf）
  会把文泉驿/DejaVu 顶到 serif/sans/mono 最前面，压制用户配置

### install.sh

- **`COMPOSITOR=niri|hyprland` 环境变量选合成器**（默认 `hyprland`）。
  一键安装仍是纯 Hyprland，不会破坏这套「名义上是 Hyprland 配置」的定位
- 字体依赖：`adobe-source-han-sans-cn-fonts`（pacman）、`ttf-lxgw-wenkai`（AUR）
- `ffmpeg`：mpvpaper 视频壁纸插件要用它生成缩略图和动态取色
- SNAP_PATHS 新增 `.config/DankMaterialShell/plugins`（仅 plugins，不含
  机型相关的 `settings.json`）
- fc-cache 之后移除劫持字体的 `65-wqy-zenhei.conf`

### 登录界面：plasmalogin → SDDM + Catppuccin Mocha

本机 DM 其实是 **plasmalogin**（KDE 新版，SDDM 的 fork），改登录分辨率是已知问题。
改用 SDDM + Catppuccin Mocha，见 [docs/login-screen.md](docs/login-screen.md)。

⚠️ **自定义壁纸没成功**（折腾三轮后按用户要求回退默认）。留下的两条经验：
1. 主题目录名 ≠ AUR 包名（规则 `catppuccin-<flavour>-<accent>`）
2. **给主题写配置前，先读它自带的 `theme.conf`** —— 值的格式（是否带引号）照抄它。
   照抄 README 的语义描述写裸值 `true`，而 QML 判断是 `== "true"`，永远不成立

### DMS 插件

- **wallpaperCarousel**：静态壁纸轮播挑选器，`Ctrl+Alt+T` 打开，
  `Ctrl+Alt+←/→` 切换（在 `dms/binds.kdl`；README 推荐的 `Mod+W` 已被「浏览器」占用）
- **mpvpaper**：视频壁纸（v1.2.0，需 DMS ≥ 1.5.0，本机 1.6.2；依赖 mpvpaper + ffmpeg
  已装）。⚠️ 与 carousel 是**两个独立插件**，carousel 只列图片，
  视频必须在 mpvpaper 自己的设置页选；且它没有 IPC 接口，只能走界面或 DankBar 组件

### 家目录清理

131 → 90 个顶层条目。清掉 30 个 `.Xresources.backup<时间戳>`（换色工具残留）
和 11 个空目录。用 `gio trash`（可还原）、分批处理、每批校验。
XDG 目录（`Music` / `Public`）会被 `xdg-user-dirs-update` 重建，
要禁需改 `~/.config/user-dirs.dirs`。

### 仓库卫生

新增 `.gitignore` + `.chezmoiignore` 规则，排除 DMS 插件自带的 `dot_git`
（插件商店 clone 的元数据，会让插件目录变嵌套 git 仓库并带入远端 URL）。

## 2026-09-19

### 新增：快捷键管理器（Super + /）

底部面板列出配置里**真实存在**的快捷键（来自 `scripts/hyprland/get_keybinds.py`
解析 `hyprland/keybinds.lua` + `custom/keybinds.lua`），支持搜索、**点行改键**。

**这个入口此前一直是坏的**，两个前提都不成立：

- `hl.bind("SUPER + Slash", hl.dsp.global("quickshell:cheatsheetToggle"))` 早就写
  在官方 `hyprland/keybinds.lua` 里，但 qs 侧**从未注册过**这个全局快捷键 ——
  `hyprctl globalshortcuts` 里查不到 `cheatsheetToggle`，绑定指向不存在的处理器，
  按下去毫无反应。现在由面板根上的 `CompositorGlobalShortcut` 注册
  `cheatsheetToggle` / `Open` / `Close`（必须注册在常驻的 `Scope` 根上，写进面板
  的话面板一收起注册就没了）。
- `custom/keybinds.lua` 又拿同一键位覆盖了 quick terminal。现在删掉这条覆盖 ——
  **不要**在 custom 里补一条同样的绑定，同键位两条会同时触发，速查表会
  「开一次又关一次」，看起来像没反应。

**改键**采用「原地改源码那一行」，而不是往 custom 追加覆盖：
`hyprctl binds -j` 对这类绑定只给 `dispatcher = "__lua"` + `arg = "<序号>"`，
还原不出可写回的 Lua 表达式；配置里大量绑定是内联 `function`，重建必然失真。
`scripts/hyprland/rebind_keybind.py` 只替换 `hl.bind(` 之后第一个引号字符串，带
`--expect` 过期校验、自动备份、写回复核、失败回滚。

**改键流程是两步**：按下组合键只产生预览，`Enter` 才写盘。早期是「按下即写」，
误进入改键态后下一个杂散按键就直接改了 `keybinds.lua`（实测踩过两次，把 `Print`
和 `SUPER + V` 改坏了，均已从 git 还原）。

其它修复：

- 键名映射补齐 **PrtSc / ScrollLock / Pause** 与 Shift 组合符号（`!@#$…`）。
  这几个键原先未映射，`keyName()` 返回空串被当成未识别直接忽略 —— 报的
  「PrtSc / Scroll / Pause 改不了」就是这个原因。
- 冲突检测比较前先归一化：`comboText()` 产出 `Super + V`（展示形式），待写入的是
  `SUPER + V`，直接比永远不相等，冲突从来没提示过。
- 鼠标键显示成人话：`mouse:272/273/274/275/276` → 左键 / 右键 / 中键 / 后退侧键 /
  前进侧键。
- **关键修复**：改键的状态、函数与 `Process` 全部移到**面板组件内部**。QML 的 id
  作用域是单向的，外层 `Scope` 看不到 `Loader` 内层 `PanelWindow` 的 id
  （`searchField` / `card` / `rebindProc`），放外层一调用就抛 `ReferenceError` ——
  症状却是「点了行、按了键什么都没发生」，排查成本很高。

`Super + E/T/S/C` 改过去「没效果」不是 bug 而是冲突：这 4 个键本来就分别被
文件管理器 / 终端召唤 / 暂存区 / 代码编辑器占用，Hyprland 对同键位的多条绑定会
全部触发。现在会检测并提示占用者。

### 新增：仪表盘「进程」页

岛屿第 4 个页签（页签现在共 5 个：仪表盘 / 媒体 / Performance / 进程 / 天气）。

- 后端 `scripts/processes/process_sampler.py`：**长驻单进程**直读 `/proc` 做增量
  差值，取代每轮 spawn 一次 `ps`。per-process GPU 取自 `/proc/<pid>/fdinfo` 的
  `drm-engine-*`（只扫 CPU 前 40 个 pid —— 全量扫 620 个进程的 9000+ 条 fdinfo
  要 ~100ms）。限流后单轮 JSON ~33KB，开销 ~1.2% 单核，**且只在页面可见时运行**。
- `services/ProcessList.qml` 重写但**保留旧 API**（`bar/ClockDashboard.qml` 在用）；
  排序挪到 QML 侧，切排序键不用重启脚本。

### 修复：岛屿歌词与桌面歌词没打通

`modules/ii/dashboard-caelestia/` 里，`Caelestia.Services` 导出的 **C++ 单例也叫
`Lyrics`**，会盖掉 `shim/Lyrics.qml` 的同名 QML 单例 —— 媒体页读的是 Caelestia
自己的取词后端，跟 `LyricsService` 完全是两回事。更糟的是 `CUtils.enumToString()`
**带默认参数（= 多重载）**，把 QML 单例喂进去会在
`QV4::QObjectMethod::resolveOverloaded` 踩空 → **段错误，切到 Media 页必崩**。

去掉 `LyricList.qml` / `LyricsInfo.qml` 的 `import Caelestia.Services`，改用 shim
新增的 `Lyrics.sourceName`；媒体页歌词现在与桌面歌词浮层同源，并显示翻译 / 音译
副标题。

### 修复：页签高度写死导致底栏被裁

进程页原先写死 `implicitHeight: 460`，比真实可用高度大几像素，超出的部分被外层
`ClippingRectangle` 切掉 —— 表现为底栏「N processes」只剩上半截字。改为由宿主
（`Content.paneHeight`）注入可视高度。

列表同时改为**按可用高度自适应行高**（先算能放几行，再平分行高），避免两种极端：
直接裁会切掉最后一行；把余量留白又会在底栏上方留一条和行等高的空带。

### i18n

`translations/zh_CN.json` 补充：速查表自身文案、**65 条快捷键说明**、小节名。
补充方式是追加到文件末尾 —— 该文件不是全序的，全量重写会把上千个键重排。

### 已知欠账

- `modules/ii/dashboard-caelestia/` 是 vendor 目录，此前在 chezmoi 与 end4-PC 两个
  仓库里都未跟踪；本次只纳入**被改过的 12 个文件**，不是整目录。
- `custom-island/` 下的 `DashHome` / `DashStats` / `DashWeather` / `DashGitHub` /
  `TabSwitcher` 已不再挂载（岛屿现在用 Caelestia 的 `Content`），文件保留待清理。
  文档已标注，改岛屿时不要照着它们改。

## 2026-09-18

### 性能：把几处无条件轮询门控到「看得见的时候」

背景是实测 `qs` 常驻 CPU 40% 上下。逐项排除后确认大头不在岛屿（见下），但顺手
修掉了三处「组件不可见时仍在后台干活」的地方：

- **`custom-island/QuickSettings.qml`** —— 所有轮询（亮度每秒一次
  `brightnessctl`、每 5 秒 `nmcli`×2 + `bluetoothctl`×2，外加若干一次性探测）
  统一门控到 `IslandState.open && IslandState.page === "home"`。上游 Brain_Shell
  的 notch 是常驻组件所以无条件开跑，移植成面板后这些值在面板关着时**没有任何
  消费者**。重新打开时会立刻补刷一次（`onPollingChanged`），不会看到过期状态。
- **`custom-island/IslandHost.qml`** —— 给 `DashStats` 显式传
  `visible: IslandState.page === "stats"`。它的 `ProcessPanel` 是用
  `active: root.visible` 判断要不要轮询的，而 `root` 指 `DashStats` 自己，外层
  `Item` 的 `visible` 管不到 —— 不传的话它恒为 `true`，停在首页也每 3 秒跑一次
  `ps aux` 解析 200 个进程。
- **`modules/ii/background/widgets/visualizer/VisualizerWidget.qml`** —— 采样
  Timer 从 `running: true` 改为 `running: root.visible &&
  GlobalStates.visualizerPoints.length > 0`。没有播放器时 cava 根本不跑，
  `visualizerPoints` 恒为空数组，原来那趟 33ms 一次的拷贝会连带触发两趟 JS
  重采样，纯属空转。

> **卡顿归因结论**（对照实验，非这三处）：`qs` 约 40% 的基线里，**约 16 个百分点**
> 来自 `background.widgets.visualizer.enable` + `desktopLyricsEnabled`，
> **约 8 个百分点**来自灵动岛，剩下 **约 41% 是 end4-pC 原生基线**（完全移除岛屿后
> 仍测得 40.9%）。上面三处门控实测收益在噪声范围内（33.3% vs 32.3%），属于正确的
> 工程实践而非特效药。想进一步降 CPU，优先动桌面可视化。

### 录屏：设置项进 Quickshell 设置应用，并修好捕获条上两个死按钮

**新增设置**（设置 → 服务 → 屏幕录制）

- **录制目标**：屏幕 / 区域 / 窗口 → `screenRecord.captureTarget`
- **音频来源**：无 / 系统声 / 麦克风 → `screenRecord.audioSystem` / `.audioMic`
- **画质**：低 / 适中 / 高 → `screenRecord.quality`

三项都写在 `config.json` 的 `screenRecord` 下（字段定义见
`modules/common/Config.qml`），而 `scripts/videos/record.sh` 用 jq 读**同一份配置** ——
所以改完不必重启 quickshell，下一次录制就生效。

**修复：捕获条上「捕获目标」「音频」两个按钮是死的**

上游 Brain_Shell 给这两个按钮挂的是 hover 展开的下拉弹层（`openStrip` +
`popupTargetX/popupTargetWidth`），移植时弹层没有实现，于是悬停只会变个色、
点下去什么都不发生 —— `captureTarget` / `audioMic` / `audioSystem` 三项因此在界面上
**完全没有入口**。现在改成点击循环切换（`ScreenRecService.cycleCaptureTarget()` /
`cycleAudio()` / `cycleQuality()`），和设置面板共享同一份状态，改哪边都算数。

**修复：`ScreenRecService.qml` 少了一行 import**

```qml
import qs.services   // ← Translation 住在这里，不在 qs.modules.common
```

少了它，`Translation.tr()` 会抛 `ReferenceError: Translation is not defined`。
因为发生在**属性初始化阶段**，报错之后值会静默变成空字符串 —— 界面上只表现为
「捕获条里只剩图标和 ▾，文字整段消失」，既不崩、也不弹错误框，只能从启动日志里
看到那条 WARN。顺带把几个 label 从属性改成函数：`Translation.tr()` 读的是单例的
`translations` 属性，放在函数体里同样能被依赖追踪覆盖，语言热切换时会跟着刷新。

**record.sh**

- 新增 `--mic`（录 `pactl get-default-source`，即麦克风）。`--sound` 仍是系统声
  （默认 sink 的 `.monitor`）。两者同时开启时系统声优先 —— wf-recorder 只接受一个
  `--audio`，想混音得先建虚拟 sink，不在本次范围内。
- 画质映射到 libx264 参数：low `crf=28 preset=veryfast`、medium `crf=20
  preset=superfast`（即原先的默认值）、high `crf=16 preset=fast`。数值只在 record.sh
  一处定义，`ScreenRecService` 只负责显示「低 / 适中 / 高」，避免两处漂移。
- 去掉原命令里无效的 `-t`（wf-recorder 启动时报 `invalid option -- 't'`，一直是被
  忽略的，去掉后行为不变）。

### 字体：改用已安装的 Google Sans

`appearance.fonts` 的 `main` / `numbers` / `title` 从 `Google Sans Flex` 改为
`Google Sans`（静态版）。

原先那三个令牌指向的 `Google Sans Flex` **本机没有安装**，`fc-match` 一直回退到
`Noto Sans CJK SC` —— 也就是说界面上显示的根本不是配置里写的字体。AUR 里只有静态版
（`ttf-google-sans`，已装）和 `Google Sans Code`，没有 Flex（Flex 是 Google 在
2025-11 才开源到 Google Fonts 的可变版本，AUR 尚未打包）。

> 想用 Flex 的话：从 fonts.google.com 下载 `Google Sans Flex`，解压到
> `~/.local/share/fonts/` 后 `fc-cache -f`，再把这三个令牌改回去。注意 Flex 不含
> 中文字形，中文仍会回退到 Noto Sans CJK SC。

### 岛屿收起态时钟：字体改用界面主字体

收起态时钟从 `appearance.fonts.numbers` 换成 `appearance.fonts.main`
（`custom-island/Theme.qml` 新增 `mainFontFamily` 令牌，`numbersFontFamily` 保留但
暂无消费者）。

依据是同仓库 `StyledText` 的规则：

```qml
property bool shouldUseNumberFont: /^\d+$/.test(root.text)
property var defaultFont: shouldUseNumberFont ? ...numbers : ...main
```

**只有整串都是数字**时才切到 numbers，否则用 main。Bar 上的网络速度文本是
`"1.2 MB/s"`，所以走的是 main。收起态时钟在加了日期之后已经是混合文本
（`2026年9月18日 11:19:06`），按同一条规则就该用 main。

> 本机 `appearance.fonts.main` 与 `.numbers` 的值**相同**（都是 `Google Sans Flex`，
> 而该字体未安装、`fc-match` 回退到 `Noto Sans CJK SC`），所以这次改动**像素级无
> 变化** —— 实测文字宽度改前改后都是 156px。改的是语义：以后两者分开配置时，
> 时钟会跟 Bar 上其它组件走同一套。

### 岛屿：收起态换成主题紫底 + 时间左边加日期

两处外观调整，都落在收起态那颗胶囊上。

**底色改成 `colPrimaryContainer`**（`custom-island/IslandHost.qml`）

Bar 右侧那几颗 material 胶囊（网络速度、工具按钮…）走的是
`BarContent.getMaterialPillColor()` 的默认分支 —— `Appearance.colors.colPrimaryContainer`，
当前壁纸下是 `#513c73`。岛屿收起态改用**同一颗 token**，于是：

- 颜色与邻居完全一致（实测两者逐像素都是 `#513c73`）；
- 随壁纸主色自动变，不是写死的紫；
- 展开后仍回到 `colLayer1Base` —— 面板里是十几张卡片，紫底会跟卡片抢视线。
  底色用 `ColorAnimation` 跟着生长动画一起过渡。

为了真的「看不出是两套实现」，还改了三处画法：

- **收起态不走 `LiquidGlass`，改用纯色 `Rectangle`**。BarGroup 的背景就是一个
  `bgColor` 的 Rectangle，无渐变无描边；LiquidGlass 在收起态会多出一层顶部渐亮
  （实测 y=10 是 `#5c487c`，邻居同位置是 `#513c73`），并排就露馅。
- **收起态去掉描边**（`border.width: root.open ? 1 : 0`）：展开成面板时才需要一圈
  边界把面板和背后的窗口分开。
- hover 叠加色从 `colPrimary` 换成 `colOnPrimaryContainer`。底色已经是
  primaryContainer，再叠 primary（同色系、亮度也接近）hover 几乎看不出变化。

**时间左边加日期**（`custom-island/CenterContent.qml`）

收起态时钟从 `HH:MM:SS` 变成 `2026年9月18日  11:19:06`。日期取秒级 `SystemClock`
的 `date`，跨零点自动跳到新的一天；格式串写 `"yyyy年M月d日"` —— 汉字不在 Qt 的格式
字符集（`y/M/d/H…`）里，直接写在格式串中会原样输出，不需要单引号转义。

### 岛屿 + 仪表盘：移植 Brain_Shell 的顶部交互岛，取代居中时钟仪表盘

栏中央的「时钟 + 点击弹仪表盘」换成 Brain_Shell 那颗**会生长的岛**：收起时是一颗
胶囊，点一下从 Bar 中间往下长成面板，再点缩回去。旧的 `ClockDashboard` 不再挂载
（`panelFamilies/IllogicalImpulseFamily.qml` 里 `PanelLoader` 注释保留，一行可切回）。

新增 `custom-island/`（39 个 QML，独立于 `modules/`）：视觉与动效照搬 Brain_Shell，
数据源换成 end4-pC 自己的服务（`MprisController` / `LyricsService` / `ProcessList` /
`Weather` / `GitHub`）。详见 [docs/bar-and-dashboard.md](docs/bar-and-dashboard.md)。

**架构：Bar 里只有一段透明槽位，真身是独立浮层**

Brain_Shell 的「从 Bar 里长出来」是两件事合成的：TopBar 的 `centerNotch` 宽度从 300
动画到 900（`SeamlessBarShape` 重绘整条 Bar 让中间无缝变宽），外加一个独立的
`Dashboard.qml` 面板窗口。end4-pC 的 Bar 是普通 `Rectangle`、没法只重绘中间一段，
所以这里把两件事合并进同一个窗口（`custom-island/IslandHost.qml`）：**胶囊和面板是
同一个 Item，宽高一起动画** —— 视觉结果一致，且完全不碰 Bar 的绘制代码。

- `modules/ii/bar/Island.qml` 是 Bar 里那段等宽（300px）纯透明占位，
  `implicitHeight` 取 `Appearance.sizes.baseBarHeight`；
- 真身 `IslandHost.qml` 是 `WlrLayer.Overlay` 的 `PanelWindow`：收起时 mask 只覆盖
  胶囊（其余位置穿透给 Bar），展开时 mask 铺满全屏用来捕获「点面板外关闭」；
- **几何对齐**：收起态距屏幕边 `capsuleOffset = 9px`（Bar 窗口的 5px 外边距 +
  `BarGroup` 背景上下各内缩 4px），高度 32px = 邻居胶囊的可见高度，所以岛和左右
  两组胶囊在同一条水平线上；
- 展开 930×590（`panelWidth = dashboardWidth(900) + notchRadius*2`，
  `panelHeight = dashboardHeight(520) + 70`），生长动画 320ms `InOutCubic`，与上游同参。

**Bar 材质胶囊黑名单**：`BarContent.shouldPaintMaterialPill()` 与
`VerticalBarContent` 的同名函数把 `"island"` 加进黑名单。岛自己画表面（它要长到 Bar
外面去），Bar 再画一层材质胶囊会叠成双层、还多出 5px padding。

**进 Bar 组件列表**：`BarConfig.qml` 的 `allWidgets` 加
`{ id: "island", name: "Island", icon: "smart_display" }`，可在设置里自由增删；
从中间区删掉 `island` 后整座岛（胶囊 + 面板）一起隐藏，并自动收掉展开态
（否则加回来时是个敞着的面板）。

**四页**（上游是 5 页，去掉「通知」页 —— 通知在侧边栏和灵动岛已各有入口）：

| 页 | 内容 | 数据源 |
|---|---|---|
| Home | 头像 / 主机 / 运行时间 · 时钟卡片（时钟·计时器·闹钟·秒表）· 月历 · 音乐卡（封面 + 5 行歌词 + 可拖动进度）· 亮度 + 快速设置开关网格 | `ClockState` · `LyricsService` · `MprisController` · `ScreenRecService` |
| System | CPU / 内存 / 磁盘 / 网络 / 温度 / 风扇 · 进程列表（搜索 + 排序 + kill） | `CpuService` 等 · `ProcessList` |
| Weather | 当前天气 + 湿度/风/降水/能见度/气压/云量 + 日出日落/紫外线/更新时间 | `Weather` |
| GitHub | 用户名 → 仓库卡片 | `services/GitHub.qml` |

**IPC**（target 用 `islanddashboard`，避开灵动岛的 `island`）：

```bash
qs -c end4-pC ipc call islanddashboard toggle
qs -c end4-pC ipc call islanddashboard page home   # home / stats / weather / github
qs -c end4-pC ipc call islanddashboard openPanel
qs -c end4-pC ipc call islanddashboard closePanel
qs -c end4-pC ipc call islanddashboard status
```

> `openPanel` / `closePanel` 不能叫 `show` / `hide` —— 会和 `qs ipc` CLI 的保留字
> 冲突（`ClockDashboard` 踩过的同一个坑）。

**踩坑**

- **Bar 中间区是 `anchors.centerIn`**（`BarContent.qml` 的 `absoluteCenter`），
  中间组件变宽不推动左右两组 —— 这是「岛撑开时左右胶囊纹丝不动」的原因，不是 bug。
- **Nerd Font 私有区字形（U+E000–F8FF）必须显式写 `font.family`**：end4-pC 主字体
  不含这些码位，漏写就渲染成豆腐块。移植时给每个用图标的 `Text` 都补了
  `Theme.nerdFontFamily`（= `appearance.fonts.iconNerd`）。
- 顶部条带 `header` 的 `z` 要高于展开内容（上游 notch 由更上层的 layer surface 绘制），
  但它自身透明且无 handler，只有中间 300px 的 `CenterContent`（自带 `TapHandler`）
  吃事件 —— 否则会把下面页签的点击一起吞掉。

### 收起态时钟：去掉窗口标题与日期图标、精确到秒、换数字字体

Bar 中间那段 notch 的收起态内容（`custom-island/CenterContent.qml`，Brain_Shell 原版
的可滚轮轮播：clock / music / timer / stopwatch / recording）做了四件事：

- **默认项 `title`（窗口标题）→ `clock`**，并删掉配套的 `hyprctl` 标题抓取 `Process`
  与 Hyprland `RawEvent` 监听。窗口标题占着一个轮播位却几乎不看，还常驻一个子进程。
- **时间不带图标、不带日期**，就是纯 `HH:MM:SS`。
- **精确到秒**：`DateTime.clock` 的 precision 由 `Config.options.time.secondPrecision`
  决定，没开时是分钟级 —— 直接拿它取秒会得到一个**静止不动**的数字。这里自起一个
  秒级 `SystemClock` 专供收起态，既保证秒一定在走，又不必为一个胶囊去打开全局秒精度
  开关（那会连带 Bar / 侧栏的时钟一起变秒级）。
- **字体从等宽换成主题的数字字体**：`monospace` 是给计时器/表格那种需要严格对齐的
  场景准备的，单颗时钟用等宽字体会显得又瘦又硬。新增 `Theme.numbersFontFamily`
  （= `appearance.fonts.numbers`）并保留 `font.features: { "tnum": 1 }`，
  秒数跳动时数字宽度不抖。

### i18n：补齐岛屿相关文案

`custom-island/` 的 Home 页此前**整页硬编码英文**（`QuickSettings.qml` /
`ClockCard.qml` / `CalendarCard.qml` 里 `Translation.tr` 出现次数为 0），中文界面下会
漏出 `QUICK SETTINGS` / `Night Light` / `SEP 2026` / `Su Mo Tu We` 等一整屏英文。

- `QuickSettings.qml` 15 处、`ClockCard.qml` 9 处包上 `Translation.tr`；
- `CalendarCard.qml` 的月份 / 星期名从**硬编码英文数组**改为走 `Qt.locale()`
  （`Qt.locale().toString(date, "MMMM"/"ddd")`），中文环境下自然是「九月」「周日」，
  换任何语言都不用再维护数组；
- 翻译表新增 30 条 en / 23 条 zh_CN（`Quick Settings` / `Airplane Mode` / `Hotspot` /
  `Caffeine` / `Focus Mode` / `Do Not Disturb` / `Screen Capture` / `Recording` /
  `Filter` / `Shader` / `Off` / `Alarm(s)` / `remaining` / `Stop` / `No alarms set…`
  以及天气页的 `Low`~`Extreme` 五档、`UV Index` / `Updated` / `Processes` /
  `Filter processes…` / `No matching process` / `No process` / `Name`）。
- **翻译热重载的坑**：`Translation.qml` 的 `TranslationReader` 是 `FileView` 但没开
  `watchChanges`，只在 `languageCode` 变化时 `reread()` —— 改完翻译文件**不会自动
  生效**。手动触发办法：把 `config.json` 的 `language.ui` 从 `"auto"` 改成 `"en_US"`，
  隔一秒再改回 `"auto"`（`Config` 开了 `watchChanges`，两次改动都会触发 reread）。
  注意「改成 `zh_CN`」不算变化 —— `auto` 下算出来本来就是 `zh_CN`。

### 差异层：补齐岛屿全套改动

上面这些改动**一开始一个文件都没进差异层** —— `custom-island/`（39 个 QML）、
`modules/ii/bar/Island.qml`、`modules/ii/verticalBar/VerticalBarContent.qml` 全部只存在于
本机工作树，chezmoi 未跟踪；`config.json` 的 `bar.layouts.middleLayout` 也还是
`["clockWidget", "visualizer"]`。

**后果是 install.sh 装完岛根本不会出现**，而且不会有任何报错（同 09-16 那次审计的
问题）。已全部补入 `dot_config/`：

| 补入 | 说明 |
|---|---|
| `dot_config/quickshell/end4-pC/custom-island/` | 39 个 QML（新增目录） |
| `modules/ii/bar/Island.qml` | Bar 里的透明占位 |
| `modules/ii/verticalBar/VerticalBarContent.qml` | 竖栏的材质胶囊黑名单 |
| `modules/ii/bar/BarContent.qml` | 横栏的材质胶囊黑名单（更新） |
| `modules/ii/settings/pages/BarConfig.qml` | `allWidgets` 注册 island（更新） |
| `panelFamilies/IllogicalImpulseFamily.qml` | `import "../custom-island"` + `IslandHost` 替换 `ClockDashboard`（更新） |
| `translations/{en_US,zh_CN}.json` | 新增词条（更新） |
| `dot_config/illogical-impulse/config.json` | `middleLayout` → `["island"]` |

> `config.json` 其余 84 处与本机的差异（壁纸路径、widget 坐标、dock pinned apps、
> GitHub 用户名等）属于本机运行状态，**未**纳入同步。

### 文件夹图标：恢复 matugen 自动着色（撤销 Papirus）

之前把图标主题切到 Papirus-Dark，失去了文件夹跟随壁纸主色的效果。本轮恢复，
并找到「自动化配色不生效」的真正原因。

- **matugen 接上 recolor.sh**。config.toml 里从来没有 [templates.gtk-folder] 段，
  recolor.sh 只是个孤立脚本，从未被自动触发——这就是不生效的根因。现在补上
  input_path / output_path / post_hook 三项，每次换壁纸自动重新着色文件夹。
- **recolor.sh 补齐静态配置文件同步**。原脚本只写 gsettings，Qt（qt5ct/qt6ct）、
  fuzzel、xsettingsd、GTK2 仍读旧值，表现为「文件夹变了但 fuzzel 图标没变」。
  新增尾部逻辑：重着色后同步写这 6 个文件，并 pkill -HUP xsettingsd。
- **撤销 Papirus**。移除 install.sh 里的 papirus-icon-theme / papirus-folders 依赖，
  以及 [6/7] 段的图标主题切换逻辑；改为触发一次 switchwall.sh --noswitch，
  让新机器装完就有 Adwaita-Matugen 主题。
- **5 处配置回滚**：gtk-3.0/settings.ini、gtk-4.0/settings.ini、qt5ct/qt5ct.conf、
  qt6ct/qt6ct.conf、fuzzel/fuzzel.ini 里 Papirus-Dark → Adwaita-Matugen-A。
- **差异层新增** dot_config/matugen/templates/gtk-folder/（含 recolor.sh 与
  Adwaita-Matugen 模板 SVG），之前只在 live 里存在、chezmoi 未跟踪。

### 图标主题：WhiteSur-dark → Papirus-Dark（已撤销）

原来的 `WhiteSur-dark` 是 macOS 图标移植，很多 Linux 原生应用（包括本仓库的
quickshell 组件）没有专属图标，会 fallback 到通用图形——表现为「很多图标不
匹配 / 缺图标」。换成 **Papirus-Dark**（Arch `extra` 仓库），覆盖率是 Linux
图标主题里最全的一档，Material 扁平风格与桌面 M3 配色协调。

- 新增依赖：`papirus-icon-theme`（extra）+ `papirus-folders`（AUR，可选，用于
  改文件夹颜色）。
- 5 处配置同步改名：`gtk-3.0/settings.ini`、`gtk-4.0/settings.ini`、`qt5ct/qt5ct.conf`、
  `qt6ct/qt6ct.conf`、`fuzzel/fuzzel.ini`。
- 切换通过已有的 `scripts/theming/set-icon-theme.sh` 完成（gsettings + gtk2/3/4 +
  xsettingsd + rofi 一把写全）。
- 文件夹颜色：跑一次 `papirus-folders -C violet -t Papirus-Dark` 把默认蓝换成
  紫（当前壁纸主色 `#d4bbfc` 最接近 `violet` 预设）。该命令改 `/usr/share/icons/`，
  需要 sudo，故未纳入自动流程。

### 时钟：默认关闭日历图标

栏上居中时钟左侧的 `calendar_month` 图标默认关掉（`bar.clock.showIcon` 默认值
`true → false`）。运行时通过 `~/.config/illogical-impulse/config.json` 关闭，
`Config.qml` 的默认值同步改为 `false`，新机器装完不会再多一个日历符号。
需要时可以到 设置 → 栏 → Clock 里打开「Show icon」。

### 系统更新检查：`pacman -Qu` 替代 `checkupdates`，2.8 倍提速

`services/Updates.qml` 用于栏上的更新计数器。旧实现用 `checkupdates`（来自
pacman-contrib）：它每次会拷贝一份临时库并重新 sync（访问网络镜像），实测 **2.15s**
都花在这里，其中绝大部分是白等。改用 `pacman -Qu` 直接读本地 sync db，不发起网络
请求（前提：用户自己 `pacman -Sy` 过；`pacman -Syu` 自会更新 db，所以 db 一更新，
下次检查就是新结果）。

- **方案对比**：旧 `checkupdates + paru -Qua` **6.13s** → 新 `pacman -Qu + paru -Qua`
  **2.21s**，约 2.8 倍。AUR 侧的 `paru -Qua`（AUR RPC + 本地缓存，~2s）无法省，
  但由新加的 15 分钟缓存节流，绝大多数检查走缓存瞬时返回。
- **缓存带时间戳**：旧实现只存纯数字，命中锁文件分支后永远读旧值 —— 磁盘上留着
  `39` 这个脏值，实际只有 `3`。现在缓存拆成 `updates-count` + `updates-count.ts`，
  TTL 900s，过期自动重查。
- **`refresh(force)` 参数**：默认走缓存；手动点「检查更新」/ 右键刷新 / 装包结束
  传 `true` 绕过缓存，立刻拿准确值。旧签名 `refresh()` 仍然兼容。
- **去掉 `checkupdates` 硬依赖**：可用性探测从 `which checkupdates` 改为
  `which pacman`，不再要求 pacman-contrib。
- 保留 db.lck 分支（pacman 装包时直接用缓存，不抢锁）。

### 仪表盘：概览页改版 · 媒体页增强 · 系统页加进程列表

居中时钟仪表盘本轮做了一次较大的内容调整，并补齐了交互与动效。

**概览页：去掉番茄钟 / 待办，改为最近通知**（`modules/ii/bar/ClockDashboard.qml`）

番茄钟与待办对多数场景是低频功能，占据概览页右列的空间不划算。改成显示
最近 4 条通知：

- 通知图标复用全局 `NotificationAppIcon` 组件（与弹出通知 / 动态岛 / 锁屏同一套
  降级逻辑：`image` > `appIcon` > 按 summary 猜 Material 图标），不再统一显示铃铛。
- 标题行右侧加「一键清空」按钮（`delete_sweep`），调用
  `Notifications.discardAllNotifications()`；每条通知行尾加单条删除按钮
  （`X`），调用 `Notifications.discardNotification(id)`。两者都会同步落盘并
  dismiss notification server 里的 tracked 通知。

**媒体页：圆形封面 · 多行歌词 · 可拖动进度条**

- 封面改成正圆。`Rectangle` 的 `clip` 只裁外接矩形不裁圆角，所以封面 `Image`
  走 `layer.enabled` + `Qt5Compat.GraphicalEffects` 的 `OpacityMask`，用同尺寸圆
  形遮罩裁形。
- 歌词从「单行当前句」升级成 **5 行窗口**（上 2 + 当前 + 下 2），当前行
  `large` + `Bold` + 主色，其余行按距离衰减透明度；每行独立带翻译行。数据取
  `LyricsService.lyricLines` + `currentLineIndex`，换歌时自动重算。
- 进度条支持**点击跳转与拖动 seek**：`MouseArea` 加 `preventStealing: true`
  阻止 `SwipeView` 底层 Flickable 抢事件；拖动期间置 `root.progressDragging`
  并把 `pager.interactive` 关掉（双保险），松手调 `player.seek(target - current)`，
  保留预览 400ms 等 D-Bus position 追上，避免视觉回跳。
- 播放/暂停键改用 `anchors.fill` + 双向 `Text.Align*` 居中，绕开 `Text` 隐式行高
  （含 descent）导致的字形整体下偏。

**新增：卡片左侧音频可视化**

播放时从仪表盘卡片左侧滑出一条水平条堆叠的音频可视化，卡片暂停时收起（宽度
归零，不占位）：

- 40 条水平短横条，用 `Column` 上下锚定撑满卡片高度（`anchors.top` + `anchors.bottom`
  + 16px 呼吸位），条高 `(cardHeight - 32) / barCount` 自动均分；
- 数据取 `GlobalStates.visualizerPoints`（与桌面背景 VisualizerWidget、媒体控件
  同一份 cava 输出），33ms 采样避免每帧跑 JS；
- 加了 `gain: 2.5` 增益：cava 原始输出 0~1000，实际音乐通常只走到 200~500，
  直接 `v / 1000` 会显得「不敏感」，乘 2.5 后把常用区推满。

**系统页：新增进程列表**（新服务 `services/ProcessList.qml`）

- 数据源：单次 `ps -eo pid,user,comm,pcpu,pmem,rss,args --sort=<flag>`；排序键
  CPU / 内存 / 名称，分别映射 `-pcpu` / `-pmem` / `comm`（名称无 `-` 前缀，升序）。
- 交互：搜索框（按 pid / 用户名 / 命令名 / 完整命令行做不敏感子串匹配）；
  CPU / MEM / Name 三个排序 pill；手动刷新按钮；hover 行显示 kill 按钮（发 SIGTERM）。
- 内核线程过滤：`args` 整段被方括号包裹（`[kworker/0:1]`）的条目默认隐藏，
  列表更干净、delegate 池更小。`hideKernelThreads` 可关。
- **性能**：列表用 `ListView { reuseItems: true; cacheBuffer: 400 }` 而非
  `Repeater`。`Repeater` 每次模型变化会销毁重建全部 delegate，后台轮询 + 搜索
  输入都会触发全量重建；`ListView` 复用 item，只更新可见的约 15 行。
- 轮询只在「仪表盘打开且停留在系统页」时开启（`ProcessList.autoRefresh`），
  切页/关面板即停。
- 已知 bug 修复：`StdioCollector` 未加 `id` 却在回调里访问 `stdoutCollector.text`，
  导致解析回调抛 `ReferenceError`、`list` 永远为空、列表一直「加载中」。已补 `id`。

**仪表盘动画**（曲线取 `Appearance.animation.*`，与 caelestia `Tokens.anim` 对齐）

- 世界时钟卡片错峰进入：每张卡延迟 `index * 60ms`，opacity 走 `elementMoveEnter`
  （emphasizedDecel），y 位移走 `elementMove`（expressiveDefaultSpatial，带过冲）。
  **踩坑**：`Behavior on y` 必须挂在 `Translate` 的 `y` 上 —— `Rectangle.y` 由 Layout
  控制、本身不变，挂父级动画不生效。
- 底部页指示按钮：当前页 `scale: 1.08` + `Behavior on scale` 走 `clickBounce`。
- 媒体页封面：`opacity: 0 → 1` + `scale: 0.85 → 1` 的并行进入动画。

**世界时钟 / 天气布局修正**

- 世界时钟卡片高度 72 → 84、内边距 12 → 10、`spacing` 4 → 3、加 `clip: true`：
  原高度装不下「图标 + 城市名 + 时间」三行，时间从卡片下边顶出，`elide` 只截横向
  帮不上。
- 天气页左列限 `Layout.maximumWidth: parent.width * 0.5`，温度 / 描述 / 城市 /
  体感全部 `Layout.fillWidth` + `elide`，超大字号温度不再横向撑破分隔线。

**i18n**

- 补齐本轮新增文案：`Recent notifications` / `Notification`（单数）/
  `No recent notifications` / `Processes` / `Filter processes…` /
  `No matching process` / `No process` / `Name`。

**其它**

- 仪表盘各页顶层 Layout 补 `Layout.fillWidth: true` + `Layout.fillHeight: true`，
  避免个别 Quickshell/Qt 版本下顶层容器按 implicitWidth 居中导致的整体偏移。

## 2026-09-17（深夜）

### 仪表盘改成多页 + 背景模糊改为 QML 自绘

居中时钟的仪表盘从「一个页面」扩成「固定状态栏 + 5 页」，并把背景模糊从
「交给 Hyprland」改成「自己抓屏自己糊」，不再依赖合成器的全局模糊设置。

**多页仪表盘**（`modules/ii/bar/ClockDashboard.qml`）

- 固定状态栏（切页不变）：工作区胶囊（当前高亮）· 日期/星期 + 大号 时:分 ·
  音量 / 亮度 / 电量。台式机没有电池时电量行整行隐藏；亮度取不到时显示 `--` 而不是 `NaN%`。
- 5 页，`SwipeView` 左右滑动切换，也支持滚轮 / `←` `→` / 点页签：

  | 页 | 内容 |
  |---|---|
  | 概览 | 月历 · 世界时钟 · 番茄钟 · 待办 |
  | 媒体 | 封面 · 曲目 · 进度 · 上一首/播放/下一首 · 当前歌词 |
  | 系统 | CPU / 内存 / 交换 / 磁盘进度条 · 用户名/发行版 · 运行时间 |
  | 天气 | 当前天气 + 湿度/风/降水/能见度/气压/云量 + 刷新 |
  | GitHub | 用户名输入 + 仓库卡片列表 |

- 新增 IPC：`page <n>` / `nextPage` / `previousPage`。
- 修掉两处只有肉眼能发现的布局问题：页高不够导致月历最后一行被 `SwipeView` 裁掉；
  概览页第一列未显式顶对齐，`RowLayout` 默认垂直居中把月历往下推出可视区。

**背景模糊：QML 自绘，限定在面板范围内**（新组件 `modules/common/widgets/GlassBackdrop.qml`）

- 原理：`ScreencopyView`（wlr-screencopy）抓整个输出 → `MultiEffect` 高斯模糊 →
  按屏幕坐标对齐 → 面板自身的 `clip` + 圆角裁形。
  **模糊只发生在面板覆盖的那一块，屏幕其余部分完全不受影响。**
- 顺带解决合成器模糊的三个老问题：模糊范围覆盖整个图层（面板铺满整屏 → 整屏采样）、
  `ignore_alpha` 阈值高于玻璃 alpha 导致静默不糊、tooltip 配色要靠 `xray`/`ignore_alpha`
  双 hack。现在这些参数与该面板无关。
- `quickshell:clockDashboard` 的 `layerrule blur` 改为 `false`，避免两层模糊叠加。
- 两个必须处理的时序：抓帧时面板自己不能已画出来（否则自反馈），
  所以面板 `opacity` 挂在 `hasContent` 上；抓帧超时 300ms 兜底放行，
  保证 screencopy 不可用时仪表盘仍然打得开。
- 配置：`appearance.transparency.qmlBackdropBlur`（默认开）/ `qmlBackdropBlurRadius`（默认 56）。
  关掉即退回原来的合成器模糊路径。
- 详见 [docs/backdrop-blur.md](docs/backdrop-blur.md)（含技术路线、接口清单、
  规避清单、与全局模糊的取舍对照表）。

**GitHub 项目页**（`services/GitHub.qml` + `modules/common/widgets/GitHubRepoCard.qml`）

- 两个入口共用一份数据与逻辑：**仪表盘第 5 页**（日常查看）与 **设置 → GitHub**（完整配置项）。
- 填用户名 → 走 `gh api` 拉仓库列表 → 点卡片在浏览器打开。
  用 `gh` 而不是直连 api.github.com：不碰凭据、吃登录后的速率额度、能看到已授权的私有仓库。
- 卡片显示：名称（私有带锁）/ `fork`·`archived` 徽标 / 描述 / 语言色点 / Star / Fork /
  相对更新时间（today · yesterday · N days ago · …）。
- 状态行覆盖：加载中、用户不存在、网络失败、未登录 `gh`、无仓库、解析失败、
  输入已改待重拉。
- 踩坑：卡片一开始写成根对象内部的 inline component，Quickshell 报 `Syntax error`
  —— inline component 必须与根对象同级，改成独立文件。

**i18n**

- 审计全部 **696 个 .qml**：绕过 `Translation.tr` 的硬编码可见文本从 **2 处降到 0 处**
  （`GlobalStates.qml` 快捷键描述、`ImageConverterWidget.qml` 格式列表）。
- 本轮新增 **45 个 key**，补齐 **14 种语言共 630 条译文**；
  语言文件保持按 key 排序，diff 只有插入行。
- 实测：切到 `zh_CN` 后新页面文案全部正确（重新加载 / 打开主页 / 个仓库 / 今天 /
  拖动、滚轮或 ← → 切换页面）。
- 新增 [docs/i18n.md](docs/i18n.md)：机制、切换语言、扩展新语言、新增文案姿势、
  硬编码审计方法、已知欠账。

**其它**

- `install.sh`：按需求移除「液态玻璃 2.0」的宣传文案（版本号、splash 副标题、
  核心特性两条、FAQ 与目录说明的措辞），保留功能性说明。
- `docs/` 新增 [backdrop-blur.md](docs/backdrop-blur.md)、[github-page.md](docs/github-page.md)、
  [i18n.md](docs/i18n.md)；[bar-and-dashboard.md](docs/bar-and-dashboard.md) 补多页结构；
  [troubleshooting.md](docs/troubleshooting.md) 补「组件 unavailable 排查」
  与「玻璃糊不起来」两条。

### 关于悬停交互的范围修正

上一轮曾把整个 shell 的悬停交互动效一并移除，范围过大。现已全部恢复，
**只保留「栏上居中时钟」这一处的悬停移除**（不弹预览弹窗、不变色、不改指针形状），
其余组件（`UtilButton` 悬停变宽、`Workspaces` 悬停预览、各弹层悬停触发、
悬停 tooltip、设置页表单控件）一律回到原样。

## 2026-09-16（凌晨）

### 按键显示：新增「已输入文本」显示（原来的键帽模式读不出单词）

原来只显示键帽，打字时是「h 闪一下、e 闪一下」，**永远读不出打了什么** ——
键帽适合看快捷键，不适合看输入。现在两种需求分开满足：

| 显示 | 内容 | 用途 |
|---|---|---|
| 键帽 | 修饰键、`Ctrl+Alt+Del` 类组合键、方向键 / F 键 | 看快捷键 |
| 文本 | 打出来的可见字符累积成一行可读文本 | **看自己打了什么** |

- 可打印字符**只走文本、不进键帽**；按住 Ctrl/Alt/Super 时反过来一律当组合键走键帽
  （`Ctrl+A` 是快捷键，不是打了字母 a）。
- Backspace 删字、Esc 清空、Enter/空格 断词、Caps Lock 只影响大小写且本身不作为
  按住展示、自动重复不追加（按住不放不刷 aaaa）、松开字母**不回退**已输入字符
  （否则边打边消失，还是读不出单词）。
- 两个时长分开：键帽松开后停留 `timeout`（1600ms），文本停止输入 `textTimeout`
  （5000ms）后才清空 —— 文本是要读的，需要更长。都由守护掌握，界面不做第二套计时，
  否则会出现「界面清空了、下次按键又冒出旧文本」。
- 逐字符渲染，新字符弹入，打字有反馈。
- 新增设置开关「显示已输入的文本（可读）」，关掉即退化为纯键帽模式。
- 守护新增 `--no-text` / `--text-idle` / `--max-text` 三个参数。
- **字符映射按 US 布局写死**（`US_MAP`）：evdev 只给键码不给字符，还原「打了什么字」
  必须有一张布局表。本机 `kb_layout = us`，换布局时字符会不对，届时关掉文本模式即可。
  已写进 docs/keycap-display.md。
- 测试从 16 项扩到 **33 项**，新增覆盖文本累积、大小写、组合键分流、退格/Esc/Enter、
  长度上限、闲置超时、`--no-text` 退化模式、快照 JSON 格式。
- i18n：新开关补齐全部 14 个语言文件。

## 2026-09-16（深夜）

### 新增：歌词通杀（音频指纹兜底）

桌面歌词原本只认 MPRIS，浏览器网页播放器 / 游戏 / 视频播放器都不覆盖，逐个软件
适配是维护不完的。现在加了一条与「谁在放」无关的路径：听系统输出认歌。
详见 [docs/integrations.md](docs/integrations.md)。

- `services/AudioActivity.qml`：`pactl subscribe` 事件驱动判断「有没有音频在放」，
  零轮询；收到事件去抖 250ms 再查一次状态，空闲时没有任何定时器与子进程。
- `services/LyricsIdentifier.qml`：有声音且没有可信身份时跑一次
  `recognize-music.sh`（`songrec listen -d <默认输出>.monitor`），拿到歌名/艺人后
  复用原有 kugou 取词链路。带 60 秒冷却（Shazam 会限流）、15 分钟身份有效期、
  静默 10 秒后忘记身份（去抖，避免切歌/缓冲的短暂静音触发重复识别）。
- `DesktopLyrics.doFetch`：MPRIS 给不出可用元数据时改用指纹身份，并置
  `usingFingerprint`。进度沿用原有的 100ms 本地插值定时器，无需另造时钟。

**PipeWire 的坑**：`pactl -f json list sink-inputs` 在 PipeWire 后端**没有 `state`
字段**（那是原生 PulseAudio 才有的），只有 `corked`。只看 `state` 会永远判定为
「没在播」。已用真实输出验证（Chromium 流：`state=None, corked=False` → 在播），
并对两种后端各跑了边界用例。

**同步精度的实话**：指纹只能认出「是哪首歌」，给不出歌内位置 —— 这是 Shazam 类服务
的固有限制。所以指纹路径的进度从识别成功那一刻记 0 自己走表，起点天然偏后一段，
用歌词偏移对齐一次即可；要完全免对齐就用支持 MPRIS 的播放器。

### 按键显示：修裁切与浅色对比度、加打字反馈、i18n 全语言

- 距屏幕边缘的间距从子项的 anchors 边距改成窗口自己的 `margins`。窗口高度自适应
  子项，子项再带 `topMargin` 会把自己顶出窗口 —— 这是「上方边框被截断」的根因。
  照 OSD 的写法重写（`anchors` + `margins` + `implicitWidth/Height`）。
- 底色改用**不透明**的 M3 token（`surfaceContainerHighest` / `primaryContainer`）。
  原来的 `colLayer*` 在开启透明度后是半透明的，铺在浅色壁纸上文字看不清。
- 键帽新出现时用 `OutBack` 弹一下（`Component.onCompleted` 触发），打字有了反馈；
  `Repeater` 按下标复用 delegate，所以一直按住的 Ctrl 不会反复弹。
- 键帽高度 46、窗口四周留 8px（描边不再贴边被切），停留时长默认 1200→1600ms。
- 守护改为输出稳定错误码（`ERROR:NO_INPUT_DEVICES`）+ `#` 开头的人类提示，文案由
  `KeycapDisplay.errorText` 按当前语言翻译，不再把中文 stderr 直接显示给用户。
- 按键显示相关 7 个 key 补齐到**全部 14 个语言文件**（+70 条），并清掉已不再引用的
  `Keycap reader unavailable`。

## 2026-09-16（夜）

### 新增：键盘按键显示

设置 → 桌面 → 按键显示（默认关闭）。在屏幕上实时显示按下的按键，组合键按顺序
排开，全部松开后延迟淡出。详见 [docs/keycap-display.md](docs/keycap-display.md)。

- `scripts/keyboard/keycap-reader.py`：常驻守护，单线程 `select` 多路复用读
  `/dev/input/event*`，逐行输出 `{"keys": ["Ctrl","A"]}`。
  **只读不 grab** —— 抓设备会让按键不再进到应用里，那是键盘重映射工具的活。
  空闲时进程完全睡着，每 5 秒重扫设备列表以支持热插拔。
- `services/KeycapDisplay.qml`：起守护、解析 JSON、维护「按住」与「显示」两层状态。
- `modules/ii/keycapDisplay/KeycapOverlay.qml`：layer-shell 浮层，只覆盖键帽本身、
  不吃输入；修饰键用主色描边区分。
- `scripts/keyboard/keynames.py` 从 `/usr/include/linux/input-event-codes.h`
  自动生成（387 键码 + 110 个 `BTN_*`），手写表很容易漏多媒体键与小键盘。
- 踩到的坑：**`BTN_*` 与 `KEY_*` 的码值区间是重叠的**（`BTN_TRIGGER_HAPPY` 在
  `0x2c0`，`KEY_*` 用到 `0x2ff`），所以「码值 ≥ 256 就是鼠标键」这种区间判断是错的，
  必须用从内核头文件生成的 `BTN_CODES` 集合精确排除。另外头文件里 `KEY_*` 是十进制
  而 `BTN_*` 是 `0x` 十六进制，正则只吃十进制会一个 `BTN_*` 都解析不出来。
- 解析逻辑抽成 `parse_buffer()` 并配了确定性测试（`test-keycap-reader.py`，
  16 项）：按键没法在测试里合成，但伪造 `input_event` 字节很容易。
- 需要用户在 `input` 组里（本机已满足）；install.sh 的收尾指引里加了这一步。

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
