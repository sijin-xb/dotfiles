---
name: end4-quickshell
description: end4-pC Quickshell/QML 定制专家。处理灵动岛、桌面歌词、设置页、服务、Hyprland 联动、IPC 调试或翻译同步时使用。
allowed-tools: Read, Edit, Write, Grep, Glob, Bash(git diff:*), Bash(git diff --check:*), Bash(qs -c end4-pC:*), Bash(killall:*), Bash(hyprctl layers:*)
---

# end4-pC 定制工作流

这是一个大型 Quickshell 配置 fork，约有数百个 QML 文件。不要从全项目盲目浏览开始；先根据任务定位入口，再读取目标文件和直接依赖。

## 定位规则

- 入口和组件挂载：`shell.qml`
- 灵动岛：`modules/ii/dynamicIsland/`
- 桌面歌词：`modules/ii/desktopLyrics/`
- 设置页：`modules/ii/settings/` 和 `modules/ii/settings/pages/`
- 共享单例/组件：`modules/common/`
- 后台服务：`services/`
- 翻译：`translations/`，基准语言是 `en_US.json`

## 每次修改前

1. 读取目标文件、同目录 `qmldir`（若存在）和直接依赖。
2. 检查 `git status --short` 或 `git diff`，避免覆盖用户未提交的修改。
3. 保持 4 空格缩进、现有中文注释和最小改动原则。
4. 跨目录引用单例时确认有显式模块导入；不要依赖偶然的隐式可见性。

## 灵动岛约束

- 活动源通常通过 `ActivityManager`、`*Source.qml` 和 `*Activity.qml` 协作。
- 拖动应使用全屏透明窗口加 `mask: Region { ... }`，移动 item 的增量坐标；不要通过改 layer-shell margins 实现拖动。
- 可用 IPC：`qs -c end4-pC ipc call island reset_position`、`silent_toggle`、`task_begin`、`task_progress`、`task_end`。具体参数以目标 QML 注释为准。

## 验证和运行

- QML 修改后优先依赖热重载；需要重启时使用 `killall qs 2>/dev/null` 后后台启动 `qs -c end4-pC`，不要用 `timeout` 启动长期运行的 Quickshell。
- IPC 调试使用 `qs -c end4-pC ipc call <target> <function> [args...]` 并记录返回值。
- 按需用 `hyprctl layers` 检查 layer-shell 窗口。
- 完成前运行 `git diff --check`，并检查最终 diff 是否只包含请求范围。
- 翻译任务先运行 `./translations/tools/manage-translations.sh status`；只有用户明确要求时才运行可能删除键的 `clean`。

## 输出要求

说明改动涉及的文件和验证结果。若无法启动或无法验证，明确报告阻塞原因，不要用静默重试掩盖问题。
