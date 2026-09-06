# 🐧 sijin-xb's Dotfiles

这是我的个人 Linux 配置文件托管仓库。主要运行在 **CachyOS (Arch Linux)** 上，追求极致的响应速度与现代化工作流。

## 🛠️ 核心工具栈

| 类别 | 工具 |
| :--- | :--- |
| **OS** | [CachyOS](https://cachyos.org/) (Arch Linux Based) |
| **WM** | [Hyprland](https://hyprland.org/)（shell 为 [end-4 illogical-impulse](https://github.com/end-4/dots-hyprland) Quickshell 配置的深度定制版） |
| **Shell** | [fish](https://fishshell.com/) (with Fisher & fzf) |
| **Terminal** | [kitty](https://sw.kovidgoyal.net/kitty/) + SUPER+T 终端召唤 |
| **部署** | 自研 `install.sh`（纯 bash，无 chezmoi 依赖） |

## 🚀 一键安装 (Installation)

仅支持 **Arch Linux 系**（CachyOS / Arch / EndeavourOS 等）。脚本会：

1. 通过 pacman 安装全部会话依赖（含系统升级，`--needed` 幂等）
2. AUR 包（matugen / mpvpaper）自动引导 yay 安装
3. **quickshell 三级回退**：二进制仓库 → AUR → 自动源码编译（无需手动编译）
4. 部署配置：自动拉取 [pctrade/end4-pC](https://github.com/pctrade/end4-pC) 作为 quickshell 底盘，再覆盖本仓库的差异层（`dot_config` → `~/.config`；覆盖有差异的旧文件前自动备份到 `~/.local/state/dotfiles-backup/`）
5. 创建启动器拼音搜索所需的 Python venv

```bash
git clone https://github.com/sijin-xb/dotfiles.git
cd dotfiles
./install.sh
```

然后注销重新登录，会话选择 **Hyprland** 即可。

### 键位速览

| 键位 | 功能 |
| :--- | :--- |
| `SUPER` | 启动器（支持中文拼音搜索） |
| `SUPER+T` | 终端召唤（居中浮动半透明，再按隐藏，状态保留） |
| `SUPER+S` | scratchpad |
| `SUPER+F1` | 重启 fcitx5 输入法 |

### 特色功能

- **Bongo Cat 桌宠**：跟随系统状态换心情（空闲打盹 / 高负载流汗 / 下载举箱 / 编译敲键盘 / 听歌戴耳机逐字唱 / 低电量焦虑 / 断网找网），可拎起来甩、带惯性反弹，落点持久化
- **桌面歌词**：MoeKoe Music 逐字卡拉OK，猫猫嘴型跟着唱
- **启动器悬浮信息卡**：窗口缩略图悬停显示实时 CPU / 内存 / 工作区，可直接聚焦或关闭
- 以上均可在 **设置 → 桌面 → 小部件** 中开关

## 🗑️ 卸载

配置文件是普通拷贝（非软链），删除对应路径即可；被覆盖的旧文件备份在 `~/.local/state/dotfiles-backup/`。本仓库涉及的路径清单见 `install.sh` 与 `dot_config/` 目录结构。

## 🙏 致谢 / Credits

- [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) — 本仓库 `dot_config/quickshell/end4-pC/` 与部分 Hyprland 配置基于其 illogical-impulse shell（经 pctrade/end4-pC 一路定制而来），遵循其 **GPL-3.0** 许可证
- [outfoxxed/quickshell](https://github.com/outfoxxed/quickshell) — 强大的 Wayland shell 工具箱
- [Hyprland](https://hyprland.org/) · [matugen](https://github.com/InioX/matugen) · [MoeKoe Music](https://github.com/iAJue/MoeKoeMusic) 及所有上游项目

## 📄 许可证 (License)

本项目遵循 **GPL-3.0**（见 [LICENSE](LICENSE)），与上游 end-4/dots-hyprland 保持一致。
其中 `dot_config/quickshell/end4-pC/` 及 Hyprland lua 配置为 end-4 illogical-impulse 的衍生作品；其余部分（宠物模块、悬浮信息卡、安装脚本等）由我编写，同样以 GPL-3.0 发布。
