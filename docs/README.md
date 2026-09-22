# 文档索引

本目录存放设计说明与规划文档。用法见仓库根目录的 [README.md](../README.md)，
历史变更见 [CHANGELOG.md](../CHANGELOG.md)。

## 合成器与外观

| 文档 | 内容 |
|---|---|
| [compositor-effects.md](compositor-effects.md) | 合成器层模糊与窗口透明度：niri ↔ Hyprland 参数对照与移植（以 niri 数值为准） |
| [appearance.md](appearance.md) | 视频壁纸与视差：Quickshell `background` 模块、`switchwall.sh`、mpvpaper 后端 |
| [backdrop-blur.md](backdrop-blur.md) | 限定范围内的 QML 自绘背景模糊（`GlassBackdrop`），不依赖合成器全局模糊 |
| [login-screen.md](login-screen.md) | 登录界面：SDDM + Catppuccin Mocha 主题 |
| [lockscreen.md](lockscreen.md) | 锁屏：`modules/ii/lock/` |

## 栏 · 岛屿 · 仪表盘

| 文档 | 内容 |
|---|---|
| [dynamic-island.md](dynamic-island.md) | 灵动岛：`modules/ii/dynamicIsland/` 的架构与联动机制 |
| [bar-and-dashboard.md](bar-and-dashboard.md) | 栏组件、岛屿仪表盘、液态玻璃材质与过渡曲线 |
| [widgets-layout.md](widgets-layout.md) | 桌面小部件布局编辑 |
| [keycap-display.md](keycap-display.md) | 键盘按键显示：`scripts/keyboard/`、`services/KeycapDisplay.qml`、`modules/ii/keycapDisplay/` |
| [github-page.md](github-page.md) | GitHub 项目页（当前入口在「设置 → GitHub」，岛屿那一路已不再挂载） |

## 键位与编辑器

| 文档 | 内容 |
|---|---|
| [keybind-manager.md](keybind-manager.md) | 快捷键管理器（速查表）：改键流程与「必须 Enter 确认」的原因 |
| [nvim-keymaps.md](nvim-keymaps.md) | Neovim 快捷键速查表：保留的 Ctrl 键、拆掉的键的替代、leader 键、vim 原生动作 |
| [nvim-learning.md](nvim-learning.md) | Neovim 分阶段学习清单（4 周），含常见坑 |

## 集成与本地化

| 文档 | 内容 |
|---|---|
| [integrations.md](integrations.md) | 外部集成（含 fcitx5-rime 候选框接入 matugen 配色） |
| [i18n.md](i18n.md) | 国际化：`Translation.tr` 机制、文案提取脚本、硬编码检查 |

## 排障

| 文档 | 内容 |
|---|---|
| [troubleshooting.md](troubleshooting.md) | 排障与已知问题：「症状 → 根因 → 修复」索引，含通用教训 |
