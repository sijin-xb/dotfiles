# 登录界面（SDDM + Catppuccin Mocha）

> 状态：2026-09-20 从 **plasmalogin** 切到 **SDDM**。
> 主题：**Catppuccin Mocha**；壁纸：`~/Pictures/Wallpapers/26421608.jpg`。

## 1. 为什么换

| | plasmalogin | SDDM |
|---|---|---|
| 出身 | KDE 新版 DM（从 SDDM fork） | 老牌，生态成熟 |
| 登录界面分辨率 | **已知问题**：改不动（[KDE 论坛](https://discuss.kde.org/t/plasma-login-manager-greeter-screen-resolution/44385)，SDDM 时代就有） | 有 Xsetup / kwinoutputconfig 等多种手段 |
| 主题 | 少 | 多（AUR 一大堆） |

## 2. 安装

```bash
sudo pacman -S sddm                      # 官方源
paru -S catppuccin-sddm-theme-mocha      # AUR，Qt6 主题
```

Catppuccin 主题的依赖（AUR 包会带入，Arch 下等价）：
`qt6-svg qt6-declarative qt5-quickcontrols2`

## 3. 配置

SDDM 的自定义配置放 `/etc/sddm.conf.d/*.conf`（**不要**改 `/usr/lib/sddm/sddm.conf.d/default.conf`）。

### 3.1 选主题

```ini
/etc/sddm.conf.d/10-theme.conf
```
```ini
[Theme]
Current=catppuccin-mocha-mauve
```

⚠ **主题目录名 ≠ AUR 包名**。上游命名规则是 `catppuccin-<flavour>-<accent>`
（如 `catppuccin-mocha-mauve`）。装完先确认：

```bash
ls -d /usr/share/sddm/themes/*mocha*
```

### 3.2 壁纸

Catppuccin 的可选项（写进主题的 `theme.conf.user`，**不覆盖**主题自带的 `theme.conf`）：

| 选项 | 作用 |
|---|---|
| `CustomBackground` | 为 `true` 时才读 `Background` |
| `Background` | 图片位置，**建议放主题自带的 `backgrounds/` 目录**（相对路径） |
| `LoginBackground` | 登录面板外是否加一层背景 |
| `UserIcon` | 是否显示用户头像 |
| `ClockEnabled` | 是否显示时钟 |
| `Font` / `FontSize` | 字体 |

```ini
/usr/share/sddm/themes/catppuccin-mocha-mauve/theme.conf.user
```
```ini
[General]
CustomBackground=true
Background=backgrounds/26421608.jpg
LoginBackground=true
UserIcon=true
ClockEnabled=true
Font=Source Han Sans CN
FontSize=10
```

**为什么拷贝到主题的 `backgrounds/` 而不是直接指向家目录**：
SDDM 的 greeter 以 `sddm` 用户运行，而 `~/` 通常是 `drwx--x---`（others 无权限），
`sddm` 根本进不去，直接指过去会读不到图（黑屏/回退默认背景）。
拷进主题目录一劳永逸，也不用给家目录开 ACL。

### 3.3 切换 DM（只改开机默认，不停当前会话）

```bash
sudo systemctl disable plasmalogin.service
sudo systemctl enable sddm.service
```

不带 `--now`，所以当前会话不受影响，**下次注销/重启**才切换。

## 4. ⚠ Catppuccin 需要 SDDM 跑 Wayland

上游 README 明确写着：

> Unfortunately, the theme does not work properly if SDDM is run on X11 and not Wayland.

而 SDDM 默认是 X11。若登录后界面异常，需按
[ArchWiki SDDM#Wayland](https://wiki.archlinux.org/title/SDDM#Wayland) 配置
`[Wayland] CompositorCommand=kwin_wayland ...`。

## 5. 预览与回退

预览（不用反复注销）：

```bash
sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/catppuccin-mocha-mauve
```

回退到 plasmalogin：

```bash
sudo systemctl disable sddm.service
sudo systemctl enable plasmalogin.service
```

若 SDDM 起不来进不去系统：grub 按 `e`，内核行末尾加
`systemd.unit=multi-user.target`，进 TTY 后执行上面的回退命令再 `reboot`。

## 6. 一键脚本

`/tmp/setup-sddm.sh`（临时脚本，未纳入 dotfiles）做完了上面 2–3.3 的全部步骤：

```bash
paru -S catppuccin-sddm-theme-mocha    # 先装主题（AUR 不能用 root）
sudo bash /tmp/setup-sddm.sh           # 再跑配置
```
