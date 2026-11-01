---
description: 检查或更新 end4-pC 的多语言键
argument-hint: "[status|update|sync] [语言代码]"
allowed-tools: Bash(./translations/tools/manage-translations.sh:*)
---

根据用户参数在当前项目根目录运行翻译工具：

- 没有参数或参数为 `status`：运行 `./translations/tools/manage-translations.sh status`，只读检查各语言键数量。
- 参数为 `update`：运行 `./translations/tools/manage-translations.sh update`；如果提供语言代码，使用 `-l <语言代码>`。
- 参数为 `sync`：运行 `./translations/tools/manage-translations.sh sync`。

先说明将执行的操作。不要在用户没有明确要求时运行 `clean`，因为它可能删除额外键。执行后报告缺失键、额外键和工具输出中的错误。
