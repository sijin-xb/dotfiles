# sijin-xb's dotfiles

个人桌面配置：Arch 系（开发环境 CachyOS）+ Hyprland + Quickshell。
源码树使用 chezmoi 风格命名（`dot_`、`executable_` 前缀），但安装由自带
bash 脚本完成，不需要 chezmoi 二进制。

> **English (brief)**: Personal desktop configuration for Arch-based systems
> with Hyprland and Quickshell. Clone the repo and run `./install.sh` (TUI)
> or `./install.sh install`; the same script provides `rollback`, `restore`,
> `archive` and `uninstall`. Full documentation below is in Chinese.

## 包含内容

- Hyprland 配置（Lua）。`hyprland/` 为模板层，`custom/` 为个人覆盖层
  （同名文件在模板之后加载并覆盖模板）
- Quickshell（end4-pC fork）差异层：栏、侧边栏、启动器、总览、设置面板
- 锁屏：Quickshell LockSurface（时钟、媒体卡片：专辑封面 / 可拖拽进度条 /
  播放控制、密码输入、电源按钮）；quickshell 未运行时回退 hyprlock
- 桌面歌词：逐字计时（酷狗 KRC），适配任意 MPRIS 播放器
- 灵动岛：音乐 / 音量 / 录屏活动的顶部动态胶囊，详见下文「灵动岛」章节
- matugen 壁纸取色：kitty / alacritty / foot / fastfetch / fcitx5 / mako /
  Hyprland 联动配色
- fish（fzf 绑定、nvm）、nvim（LazyVim）、btop、fastfetch、fuzzel、mako 配置

## 环境要求

- Arch 系发行版（存在 `/etc/arch-release`）
- Hyprland（Wayland 会话）
- 普通用户运行，需要 sudo 权限（pacman 用）
- quickshell / matugen / mpvpaper 缺失时由脚本自动安装
  （pacman → AUR → 源码编译）

## 安装

```bash
git clone https://github.com/sijin-xb/dotfiles.git
cd dotfiles
./install.sh           # TUI 二级菜单
./install.sh install   # 直接执行完整安装
```

安装步骤：

1. pacman 基础依赖（hyprland、kitty、fish、fuzzel、fcitx5、cliphist、
   hypridle、hyprlock、xdg portals、qt6 工具链）
2. AUR 包（matugen、mpvpaper）；无 AUR helper 时自动安装 yay
3. quickshell 三级回退：已有二进制 → pacman → AUR → 源码编译
4. 部署 `dot_*` 条目到 `$HOME`；有差异的已存在文件先备份到
   `~/.local/state/dotfiles-backup/` 再覆盖
5. 首次运行克隆 quickshell 底盘（pctrade/end4-pC）
6. 创建 python venv（pypinyin、dbus-python），供启动器拼音搜索使用

重复运行幂等。

## 脚本命令

| 命令 | 功能 |
|---|---|
| `install` | 完整安装；开始前创建 pre-install 快照 |
| `rollback` | 还原到 pre-install 快照；开始前创建 pre-rollback 快照 |
| `restore` | 重新应用 pre-rollback 快照（撤销回档） |
| `archive [-o PATH] [--delete]` | 打包配置 / 状态 / 缓存为 tar.gz（含 MANIFEST.txt）；`--delete` 打包后清理源文件 |
| `uninstall` | 可选先存档，然后删除受管理路径 |
| 无参数 / `--tui` | 二级菜单 TUI |
| `-h` | 帮助 |

快照仅覆盖脚本内受管理路径清单（`SNAP_PATHS`），清单外的文件不会被改动。

## 快捷键（节选）

| 按键 | 功能 |
|---|---|
| Super | 启动器（拼音搜索） |
| Super+T | 终端召唤（quake 风格 kitty） |
| Super+S | 临时工作区 scratchpad |
| Super+L | 锁屏（quickshell 锁屏界面） |
| Super+Q | 关闭窗口 |
| Super+1..0、Super+方向键 | 切换工作区 / 焦点 |
| Super+Shift+方向键 | 移动窗口 |
| Super+Shift+S、Print | 区域截图 |
| Super+Shift+R | 区域录屏 |
| Super+Shift+P / N / B | 播放暂停 / 下一首 / 上一首 |
| Super+F1 | 重启 fcitx5 |
| Ctrl+Super+T | 壁纸选择器 |

完整列表：`~/.config/hypr/hyprland/keybinds.lua` 与
`~/.config/hypr/custom/keybinds.lua`。

## 目录结构

```
dot_config/
  hypr/
    hyprland.lua          配置入口
    hyprland/             模板层（keybinds、general、rules、env、execs、scripts）
    custom/               个人覆盖层（同名文件覆盖模板）
    hyprlock.conf         回退锁屏配置
    hyprlock/             配色与辅助脚本
  quickshell/end4-pC/     shell 差异层（modules、services、scripts）
  fish/  kitty/  foot/  alacritty/  nvim/  btop/  fastfetch/  fuzzel/  mako/  matugen/
install.sh                安装 / 卸载 / 回档 / 存档 / TUI
```

## 锁屏

`Super+L` 触发 `quickshell:lock`。锁屏界面显示模糊后的桌面壁纸（与桌面
背景同一源链，含 `lockWall` 覆盖与视频缩略图分支）、时钟与日期、媒体卡片
（专辑封面、歌名 / 艺术家、可拖拽进度条、上一首 / 播放暂停 / 下一首）、
密码输入框与电源按钮。hypridle 超时锁屏走同一入口；quickshell 未运行时
使用 hyprlock。

## 灵动岛

顶部居中的动态胶囊，按「当前活动」切换形态，同一时刻只显示优先级最高的
活动。数据源通过 `ActivityManager.set(type, payload, priority)` 注册，UI 订阅
`currentType` / `currentPayload`。

| 活动 | 优先级 | 触发条件 | 主岛内容 |
|---|---|---|---|
| `volume` | 30 | 音量 / 静音变化（2 秒后自动消失） | 音量条 |
| `music` | 10 | 任意 MPRIS 播放器有曲目 | 封面、频谱、标题 |
| `recording` | 5 | `states.json` 中 `record.enable` 为 true | 脉冲红点、计时 |

### 音乐

- **收起**：圆形封面 + 6 段实时频谱（cava）+ 歌名，宽度随内容自适应（200–340px）
- **展开**：两页，左右滑动或点击底部指示点切换
  - 控制页：封面、歌名 / 艺术家、可拖拽进度条、上一首 / 播放暂停 / 下一首
  - 歌词页：当前行前后共 5 行，当前行逐字高亮，附翻译行

### 歌词逐字高亮

歌词取自酷狗 KRC，逐字格式为 `[start,duration]<offset,duration,0>字`。字的偏移量
**相对行首**（首个字为 0），解析后累加行起始时间得到每个字的绝对时间。

渲染时每个字是独立的 `Text`，只切换颜色（已唱纯白 / 未唱 22% 白），避免
RichText 每帧重新解析造成的卡顿。

中英对照来自 KRC 的 `[language:]` 块（Base64 内嵌 JSON）：取第一个非罗马音
语义块作为翻译，按行号对齐；日语歌曲的罗马音转写块会被自动跳过。

### 录屏伴随指示器

录屏优先级低于音乐。两者并存时录屏不抢占主岛，而是以一个小胶囊贴在主岛
**左侧**：脉冲红点 + 计时，**点击它即可停止录屏**。

这样设计是为了演示 / 录屏场景：主岛可以继续展示音乐，录屏状态又始终可见且
可操作。录屏单独存在（无音乐）时，它仍正常占用主岛。伴随胶囊与主岛收起态
等高（37px）、同圆角（19px）、同字号，视觉上连为一体。

## 更新日志

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

## 说明

- 更换壁纸会触发重新取色；模板位于 `dot_config/matugen/templates/`
- 桌面歌词偏移微调：
  `qs -c end4-pC ipc call desktoplyrics offset_faster / offset_slower`
- 备份根目录：`~/.local/state/dotfiles-backup/`（`snapshots/`、`state/`）

## 致谢与上游

本项目的 Quickshell 桌面外壳并非从零编写，而是基于以下上游项目构建，特此声明并致谢。

### 直接上游

- **[pctrade/end4-pC](https://github.com/pctrade/end4-pC)** by [@pctrade](https://github.com/pctrade)
  - 本仓库的 Quickshell 差异层（`dot_config/quickshell/end4-pC/`）基于此项目修改而来。
  - 安装脚本在首次运行时克隆该仓库作为 Quickshell 底盘，本仓库仅维护差异层，不重复分发上游代码。

### 上游的上游

- **[end-4/dots-hyprland](https://github.com/end-4/dots-hyprland)** by [@end-4](https://github.com/end-4)
  - `end4-pC` 是该项目中 illogical-impulse shell 的个人 fork。
  - illogical-impulse 是这套 Quickshell 桌面外壳的原始实现。

### 其他致谢

- 天气组件所用的天气 API 集成来自 [@gh0stzk](https://github.com/gh0stzk)
- 部分 shader 过渡效果来自 [@simeulinuxkaliaiwr](https://github.com/simeulinuxkaliaiwr)

### 许可证继承

本项目采用 [GPL-3.0](LICENSE) 许可证，与上游项目一致。作为衍生作品，本仓库保留了上游的版权与致谢信息，并对个人修改部分负责。

## 许可证

本项目采用 [GPL-3.0](LICENSE) 许可证。
