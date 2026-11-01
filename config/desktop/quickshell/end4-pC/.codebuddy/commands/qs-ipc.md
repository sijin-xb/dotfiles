---
description: 调用 end4-pC 的 Quickshell IPC 接口并报告返回值
argument-hint: "<target> <function> [args...]"
allowed-tools: Bash(qs -c end4-pC ipc call:*)
---

在当前项目根目录执行：

```bash
qs -c end4-pC ipc call $ARGUMENTS
```

解析并报告 IPC 返回值。不要擅自重启 `qs`；如果目标或函数缺少，请先向用户确认。常用示例：

- `/qs-ipc island reset_position`
- `/qs-ipc island silent_toggle`
- `/qs-ipc desktoplyrics toggle`
- `/qs-ipc desktoplyrics get_offset`
