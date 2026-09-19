# MpvPaper Plugin

[English](#mpvpaper-plugin) | [简体中文](#简体中文)

![MpvPaper settings](screenshot.png)

Video wallpaper plugin for [Dank Material Shell](https://github.com/AvengeMedia/DankMaterialShell). It uses `mpvpaper` for playback and includes both a settings interface and a DankBar wallpaper switcher.

## Features

- Smooth wallpaper switching without restarting `mpvpaper` for every video change
- Shared video library with independent wallpaper selection per monitor, or one wallpaper across all monitors
- DankBar widget for browsing and switching wallpapers
- Hardware decoding with `auto`, `nvdec`, `vaapi`, and `vdpau`, plus fill mode and volume controls
- Configurable lock-screen behavior: stop the player or pause and resume from the current position
- Configurable periodic `mpvpaper` restart for long-running sessions
- Dynamic DMS colors generated from the active video wallpaper
- English and Simplified Chinese settings

## Installation

MpvPaper Plugin is available in the DMS Plugin Directory.

1. Open **DMS Settings → Plugins → Browse**.
2. Search for **MpvPaper Plugin**.
3. Install and enable the plugin.

Install the required system packages first. On Arch Linux:

```bash
sudo pacman -S ffmpeg
yay -S mpvpaper
```

## Usage

1. Open the plugin settings and add video files or a folder.
2. Select a monitor and choose its wallpaper, or enable the same wallpaper for all monitors.
3. Configure playback, lock-screen behavior, and optional advanced MPV settings as needed.
4. Add **MpvPaper Plugin** to the DankBar layout if you want quick wallpaper switching from the bar.

The settings page and DankBar widget use the same video library. Changing a wallpaper only changes the current selection; adding videos does not automatically replace the active wallpaper.

## Requirements

- DMS 1.5.0 or later
- [`mpvpaper`](https://github.com/GhostNaN/mpvpaper)
- `ffmpeg` for thumbnails and dynamic color extraction

## License

MIT

---

## 简体中文

用于 [Dank Material Shell](https://github.com/AvengeMedia/DankMaterialShell) 的视频壁纸插件。插件使用 `mpvpaper` 播放视频壁纸，并提供完整的设置界面和 DankBar 壁纸切换组件。

### 功能

- 切换视频时复用现有 `mpvpaper` 播放进程，减少黑屏、闪烁和重新启动造成的卡顿
- 使用统一的视频库，可为每个显示器分别选择壁纸，也可让所有显示器使用同一壁纸
- 提供 DankBar 组件，可直接浏览和切换视频壁纸
- 支持 `auto`、`nvdec`、`vaapi`、`vdpau` 硬件解码，并提供画面填充和音量设置
- 锁屏时可选择关闭播放器，或暂停播放并在解锁后从当前位置继续
- 可设置定时重启 `mpvpaper`，用于长时间运行场景
- 根据当前视频壁纸生成 DMS 动态配色
- 设置界面支持 English 和简体中文

### 安装

MpvPaper Plugin 已收录在 DMS Plugin Directory 中。

1. 打开 **DMS 设置 → 插件 → 浏览**。
2. 搜索 **MpvPaper Plugin**。
3. 安装并启用插件。

请先安装系统依赖。Arch Linux：

```bash
sudo pacman -S ffmpeg
yay -S mpvpaper
```

### 使用

1. 打开插件设置，添加视频文件或整个视频文件夹。
2. 选择显示器并设置对应壁纸；也可以启用“所有显示器使用相同壁纸”。
3. 按需设置硬件解码、画面填充、音量、锁屏行为和高级 MPV 参数。
4. 如需从状态栏快速切换壁纸，可在 DankBar 布局中添加 **MpvPaper Plugin**。

设置页面和 DankBar 组件共用同一个视频库。添加视频只会加入视频库，不会自动替换当前正在播放的壁纸。

### 依赖

- DMS 1.5.0 或更高版本
- [`mpvpaper`](https://github.com/GhostNaN/mpvpaper)
- `ffmpeg`，用于生成视频缩略图和动态配色取帧

### 许可证

MIT
