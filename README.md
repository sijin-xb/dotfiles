# sijin-xb's dotfiles — Rice v2.0 液态玻璃版

> Arch Linux · Hyprland · Quickshell (end4-pC) · Material 3 动态取色

---

## 核心特性

| 特性 | 说明 |
|------|------|
| **液态玻璃毛玻璃** | 阴影代替边框，柔和光晕 + vibrancy 色彩染色，quickshell 面板 10px 模糊半径 |
| **Bongo Cat 桌宠** | 系统状态换心情、拎起甩动有惯性、落点跨重启持久化 |
| **桌面歌词逐字卡拉OK** | MoeKoe Music / Spotify / 浏览器适配，歌词偏移实时微调 |
| **拼音搜索启动器** | 中文拼音模糊搜索 + 窗口缩略图信息卡 + 悬浮预览 |
| **终端召唤** | SUPER+T 居中浮动 quake 风格终端（kitty），状态保留、再按隐藏 |
| **Material 3 取色** | matugen 壁纸→全局配色，11+ 应用（alacritty/kitty/hyprland/fcitx5/fastfetch...）联动 |
| **Quickshell 锁屏** | SUPER+L 触发 LockSurface：MPRIS 媒体控制 + 专辑封面 + 电源/重启/休眠按钮 |

## 适配环境

- **OS**: CachyOS / Arch Linux / EndeavourOS（需要 /etc/arch-release）
- **会话**: Wayland · Hyprland + Quickshell (end4-pC)
- **GPU 建议**: Intel UHD 620+ / AMD Vega 3+ / NVIDIA（需开启 modeset）
- **Shell**: fish（推荐设为默认）

## 快速安装

```bash
# 克隆仓库
git clone https://github.com/sijin-xb/dotfiles.git ~/dotfiles
cd ~/dotfiles

# TUI 交互模式（推荐）
./install.sh

# 或一键静默安装
./install.sh install

# 查看所有子命令
./install.sh --help
```

### 子命令一览

| 命令 | 功能 |
|------|------|
| `./install.sh` / `--tui` | 进入二级菜单 TUI（推荐新手） |
| `install` | 6 步全自动安装 |
| `rollback` | 回档到最近一次 install 之前的状态 |
| `restore` | 从 rollback 前快照恢复 |
| `archive [-o PATH] [--delete]` | 打包存档所有配置，可选清理源文件 |
| `uninstall` | 卸载 rice（可选先存档） |

## 锁屏媒体面板

**触发**: `SUPER+L`（dispatch quickshell:lock → LockSurface.qml）

Quickshell LockSurface 全屏锁屏，包含：

```
┌──────────────────────────────────────────────────────────┐
│  14:30              Beautiful World · 米津玄師            │
│  Saturday · 09月08日 · 2026        ⏮  ⏸  ⏭             │
│                    ● 锁屏中 · 键盘快捷键同样可用           │
└──────────────────────────────────────────────────────────┘
```

- MPRIS 集成：直接控制任意兼容播放器（Spotify/ncm/foorif...）
- 专辑封面显示 + 曲目进度条
- 电源按钮（关机/重启/休眠）可选密码保护
- 自动切换锁屏主题色（matugen --colors_lock）
- 锁屏时工作区隔离动画（切到空 workspace）
- 键盘布局指示 + fcitx5 输入法状态

## 快捷键速览

| 快捷键 | 功能 |
|--------|------|
| `SUPER` | 启动器（中文拼音搜索） |
| `SUPER+T` | 终端召唤（quake 风格） |
| `SUPER+S` | Scratchpad 临时工作区 |
| `SUPER+L` | 锁屏（带媒体面板） |
| `SUPER+F1` | 重启 fcitx5 输入法 |
| `SUPER+Q` | 关闭窗口 |
| `SUPER+方向键` | 切换窗口焦点 |
| `SUPER+数字` | 切换工作区 |
| `SUPER+SHIFT+方向键` | 移动窗口 |
| `SUPER+SHIFT+S` | 区域截图 |
| `SUPER+SHIFT+R` | 区域录屏 |
| `SUPER+SHIFT+P` | 播放/暂停媒体 |
| `SUPER+SHIFT+N` | 下一曲 |
| `SUPER+SHIFT+B` | 上一曲 |
| `XF86Audio*` | 音量/亮度/播放控制（锁屏下仍可用） |

## 目录结构

```
~/.config/
├── hypr/
│   ├── hyprland.lua              # Hyprland 配置入口
│   ├── hyprland/                 # 默认模板层（建议只读）
│   │   ├── keybinds.lua          # 默认快捷键
│   │   ├── general.lua           # 通用设置（圆角/边框/模糊）
│   │   ├── env.lua               # 环境变量
│   │   ├── execs.lua             # 开机自启
│   │   ├── rules.lua             # 窗口规则
│   │   ├── colors.lua            # 配色（由 matugen 生成）
│   │   └── scripts/              # Hyprland 辅助脚本
│   ├── custom/                   # 用户差异层（你的个性化配置）
│   │   ├── keybinds.lua          # 自定义快捷键（覆盖默认）
│   │   ├── general.lua           # 液态玻璃高级参数
│   │   ├── execs.lua             # 自定义自启
│   │   └── ...
│   ├── hyprlock.conf             # 锁屏配置（hyprlock 作为 quickshell 的 fallback）
│   └── hyprlock/
│       ├── colors.conf           # 锁屏配色（matugen 生成）
│       ├── scripts/
│       │   ├── media-info.sh            # 媒体信息输出脚本
│       │   ├── status.sh                # 系统状态（电池等）
│       │   └── check-capslock.sh        # Caps Lock 指示
├── quickshell/
│   └── end4-pC/                  # quickshell 底盘（差异层）
└── scripts/                      # 通用辅助脚本
```

## 回档 / 恢复 / 存档机制

### 回档 (Rollback)
```bash
./install.sh rollback
```
- 安装前自动创建 **pre-install 快照**
- 回档前自动创建 **pre-rollback 快照**（供 restore 用）
- 只覆盖快照内包含的文件，不删除其他用户文件

### 恢复 (Restore)
```bash
./install.sh restore
```
- 从 pre-rollback 快照还原配置
- 用于回档后反悔，回到回档前的 rice 状态

### 存档 (Archive)
```bash
./install.sh archive -o ~/backup.tar.gz --delete
```
- 打包所有 rice 配置 + 状态 + 缓存
- MANIFEST.txt 包含元数据（用户名/时间戳/路径清单）
- `--delete` 打包后自动清理源文件（卸载前的备份步骤）

## FAQ

**Q: 回档后想再换回 rice？**  
A: 执行 `./install.sh restore`（rollback 前自动保存了快照）

**Q: 液态玻璃效果太浓 / 太淡？**  
A: quickshell 设置 → 配置文件 → Hyprland：模糊半径 (10→8/12)，活动不透明度 (82→更高更清晰或更低更通透)。细项在 `~/.config/hypr/custom/general.lua`

**Q: 安装脚本冲突 / 幂等吗？**  
A: 完全幂等。重复运行仅安装缺失的包，覆盖有差异的文件前自动备份到 `~/.local/state/dotfiles-backup/`

**Q: 锁屏没有媒体控制？**  
A: 确认 quickshell 正在运行（`pidof quickshell`）。SUPER+L 触发的是 quickshell:lock dispatch，不是 hyprlock。hyprlock 仅在 quickshell 未运行时作为 fallback。

---

## License

MIT
