---
description: 重启 end4-pC Quickshell 实例并检查启动状态
allowed-tools: Bash(killall:*), Bash(qs -c end4-pC:*)
---

请在当前项目根目录执行以下操作：

1. 先结束已有的 `qs` 进程：`killall qs 2>/dev/null`。没有进程时不要当作失败。
2. 在后台启动 `end4-pC`：`qs -c end4-pC > /dev/null 2>&1 & disown`。
3. 不要使用 `timeout` 包裹 Quickshell，也不要因为启动命令会持续运行而等待它退出。
4. 返回启动命令是否成功；如果用户要求进一步诊断，再使用项目已有的 IPC 调用或 `hyprctl layers` 检查。
