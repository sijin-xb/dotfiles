# 文档索引

本目录存放设计说明、实现笔记与排障文档。用法见仓库根目录的 [README.md](../README.md)，历史变更见 [CHANGELOG.md](../CHANGELOG.md)。

| 文档 | 内容 |
|---|---|
| [bar-and-dashboard.md](bar-and-dashboard.md) | 岛屿 + 仪表盘（生长动画、几何对齐、五页、栏上增删）、栏组件与居中时钟、统一歌词源、液态玻璃、动画令牌、悬停动效处理范围 |
| [backdrop-blur.md](backdrop-blur.md) | 限定范围的背景模糊：QML 自绘抓屏+模糊，与依赖合成器全局模糊的取舍（岛屿已改为不透明材质，目前无活跃消费者） |
| [compositor-effects.md](compositor-effects.md) | **合成器层**模糊与窗口透明度：niri ↔ Hyprland 参数对照表、以 niri 为准的移植、offset≠半径 / saturation 无对应项等坑、SUPER+A 的删除原因 |
| [github-page.md](github-page.md) | GitHub 项目页：用户名 → 仓库列表、状态处理、实现要点 |
| [i18n.md](i18n.md) | 国际化：机制、切换语言、扩展新语言、新增文案姿势、硬编码审计、已知欠账 |
| [dynamic-island.md](dynamic-island.md) | 灵动岛：文件职责、活动优先级、联动机制（场景门控 / 分组渲染 / 全局取色） |
| [appearance.md](appearance.md) | 视频壁纸后端（mpvpaper / wallr / phonto）与静态 / 视频壁纸视差实现 |
| [lockscreen.md](lockscreen.md) | Serpantinum 风格三栏锁屏：布局、认证链、配色来源 |
| [widgets-layout.md](widgets-layout.md) | 桌面小部件可视化布局编辑（右键拖动） |
| [integrations.md](integrations.md) | SPlayer WebSocket 歌词联动、fcitx5-rime × matugen 取色联动 |
| [keycap-display.md](keycap-display.md) | 键盘按键显示：evdev 读取守护、浮层、权限与测试 |
| [keybind-manager.md](keybind-manager.md) | 快捷键管理器（Super + /）：速查表、点行改键、写回策略与安全防护 |
| [troubleshooting.md](troubleshooting.md) | 排障索引：症状 → 根因 → 修复 |
