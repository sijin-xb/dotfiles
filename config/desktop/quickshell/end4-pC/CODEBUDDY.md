# end4-pC 项目协作说明

## 项目定位

这是基于 illogical-impulse 的 Quickshell 桌面配置 fork。当前入口是 `shell.qml`，主要功能位于 `modules/ii/`，共享组件位于 `modules/common/`，后台服务位于 `services/`，辅助脚本位于 `scripts/`。

## 关键入口

- `shell.qml`：加载 `modules/common`、`modules/ii/desktopLyrics`、`modules/ii/dynamicIsland`、`services` 和 `panelFamilies`；同时挂载 `DesktopLyrics` 与 `DynamicIslandHost`。
- `modules/ii/dynamicIsland/`：灵动岛主体和活动源。涉及音乐、音量、录屏、通知、包管理、下载进度等功能时，先读这里。
- `modules/ii/settings/`：设置面板及各设置页。
- `services/`：MPRIS、网络、Hyprland、歌词、壁纸等共享服务。
- `translations/`：14 个语言 JSON；`en_US.json` 是键结构基准。
- `translations/tools/manage-translations.sh`：翻译提取、状态检查、更新、清理和同步工具。

## 修改工作流

1. 先读取目标 QML 和它直接依赖的同目录文件，再编辑；不要凭记忆猜模块结构。
2. 保持现有 4 空格缩进、中文注释和 QML 风格（规则见 `.qmlformat.ini`）。
3. 优先做最小改动；不要顺手重构未涉及的模块。
4. 修改后利用 Quickshell 热重载观察结果；不要用 `timeout` 反复启动 Quickshell。
5. 需要主动重启时，进程名是 `qs`，配置名是 `end4-pC`：`killall qs 2>/dev/null; qs -c end4-pC > /dev/null 2>&1 & disown`。
6. 调试 IPC 使用：`qs -c end4-pC ipc call <target> <function> [args...]`。灵动岛目标是 `island`，桌面歌词目标是 `desktoplyrics`。
7. 修改前后检查 `git diff`，保留用户已有的未提交改动；不要执行 `git reset --hard` 或覆盖无关文件。

## Quickshell 特别注意

- `qs` 才是进程名，`pgrep quickshell` 通常找不到目标进程。
- 同目录 QML 可以依赖隐式导入；跨目录单例（例如 `modules/common` 中的 `Persistent`）要显式导入对应模块。
- 灵动岛拖动使用全屏透明窗口配合 `mask: Region { ... }`，不要通过反复修改 layer-shell margins 拖动窗口，否则指针坐标系会跳变。
- IPC 调用和 QML 注释中已有可用示例，优先沿用现有命名和参数顺序。

## 验证

- QML 改动：确认热重载后无错误，并按需用 `hyprctl layers` 检查窗口尺寸/层级。
- 翻译改动：先运行 `translations/tools/manage-translations.sh status`，再按需要运行 `update` 或 `sync`；不要未经确认执行会删除键的 `clean`。
- 没有完整的自动化测试套件时，至少检查 `git diff --check`，并报告无法自动验证的部分。
