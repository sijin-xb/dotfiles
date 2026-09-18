# 快捷键管理器（速查表）

按 `Super + /` 弹出底部面板：列出配置里**真实存在**的快捷键，可搜索、可点行改键。

- 面板：`modules/ii/cheatsheet/Cheatsheet.qml`
- 改键脚本：`scripts/hyprland/rebind_keybind.py`
- 解析脚本：`scripts/hyprland/get_keybinds.py`
- IPC：`qs -c end4-pC ipc call cheatsheet toggle|open|close`

## 1. 它为什么之前一直是坏的

`~/.config/hypr/hyprland/keybinds.lua` 里**早就**有这一条：

```lua
hl.bind("SUPER + Slash", hl.dsp.global("quickshell:cheatsheetToggle"),
        { description = "Shell: Toggle cheatsheet" })
```

但两个前提都不成立：

1. **qs 侧从未注册过这个全局快捷键**。`hyprctl globalshortcuts` 里根本查不到
   `cheatsheetToggle` —— 绑定指向了一个不存在的处理器，按下去毫无反应。
   现在由面板根上的三个 `CompositorGlobalShortcut` 注册：
   `cheatsheetToggle` / `cheatsheetOpen` / `cheatsheetClose`。
   > 这三个必须注册在 `Scope` **根**上（常驻），不能放进面板内部 —— 面板是按需
   > 创建的，写进去的话面板一收起注册就没了。
2. **`Super + /` 被覆盖过**。`~/.config/hypr/custom/keybinds.lua` 原先拿同一键位
   绑了 quick terminal，把官方那条顶掉了。现在删掉这条覆盖。
   > 注意**不要**在 custom 里再补一条同样的绑定：同键位两条会同时触发，速查表
   > 会「开一次又关一次」，看起来像没反应。

## 2. 使用

| 操作 | 结果 |
|---|---|
| `Super + /` | 开关面板；打开后焦点自动落在搜索框 |
| 输入 | 跨全部小节过滤（匹配修饰键 / 按键 / 说明） |
| 点某一行 | 进入改键：该行高亮，等待新的组合键 |
| 按下组合键 | **只预览**，胶囊里显示待应用的组合 |
| `Enter` | 确认写入 |
| `Esc` | 取消（改键态下）/ 关闭面板（非改键态） |
| 点面板外 | 关闭 |

> **为什么必须 Enter 确认**：早期是「按下即写」，只要误进入改键态，下一个杂散
> 按键就直接改了 `keybinds.lua`（实测踩过两次，把 `Print` 和 `SUPER + V` 改坏了）。
> 两步确认下，误触只会产生预览，不会写盘。

不可改的条目：`--#/#` 注释型（循环生成的绑定，如「Focus in direction」）没有
单一源码行，点它会提示「This entry cannot be edited」。

## 3. 改键为什么是「原地改那一行」

不是往 `custom/keybinds.lua` 追加覆盖，原因是**写不回去**：

- `hyprctl binds -j` 对这类绑定只给 `dispatcher = "__lua"` + `arg = "<序号>"`，
  还原不出可写回的 Lua 表达式；
- 配置里大量绑定用的是内联 `function`（如
  `hl.bind("SUPER + V", function() hl.exec_cmd(...) end)`），重建必然失真。

所以只能从源码行里把 key 字符串换掉，其余一字不动，才能原样保住 dispatcher。

`scripts/hyprland/rebind_keybind.py` 的安全措施：

- 只替换 `hl.bind(` 之后**第一个**引号字符串；
- `--expect` 传入当前组合，对不上说明解析结果已过期 → 拒绝执行；
- 写回前自动留 `.bak-<时间戳>` 备份；写回后**再读一次校验**；
- 写入失败或校验失败自动回滚。

## 4. 键名映射

面板用 `Qt.Key_*` → Hyprland 键名。容易踩的几处：

- **鼠标键**在 Hyprland 里是 X11 按钮码，直接显示没人看得懂，映射成文字：
  `272` 左键 · `273` 右键 · `274` 中键 · `275` 后退侧键 · `276` 前进侧键。
- **PrtSc / ScrollLock / Pause** 曾漏掉，导致按下后 `keyName()` 返回空串、被当成
  「未识别的键」直接忽略 —— 表现就是「这几个键改不了」。
- **Shift 组合符号**（`!@#$%^&*()` 等）在 Qt 里是独立 key code，映射回基础键。
- Qt6 **没有**独立的小键盘键码（用 `Qt.KeypadModifier` 区分），所以不做 `KP_*`。

## 5. 冲突

改键时会检测目标组合是否已被其它绑定占用。比较前先归一化（`comboText()` 产出的
是 `Super + V` 这种展示形式，而待写入的是 `SUPER + V`，直接比永远不相等）。

命中冲突**只提示不阻止** —— 用户有权故意这么干，但必须知道。提示会带上占用者的
说明文字。

注意：Hyprland 对同一键位的多条绑定**会全部触发**，所以「改过去没效果」通常不是
没写进去，而是旧的那条还在。这种情况要么换键，要么先改掉占用者。

## 6. 数据源与 i18n

`get_keybinds.py` 解析两个 Lua 文件，每条绑定带出：

| 字段 | 用途 |
|---|---|
| `mods` / `key` | 展示组合 |
| `comment` | 说明文字（常见 `小节: 描述` 前缀，展示时去掉） |
| `file` / `line` | **改键定位**（1-based；多行 bind 取起始行） |
| `raw` | 文件里的原始组合字符串，用作 `--expect` 校验（比从 mods+key 重建可靠） |

说明文字与小节名都过 `Translation.tr()`，词条在
`translations/zh_CN.json`。查不到时 `tr` 原样返回，所以未翻译的条目不会显示成空。
新增词条直接追加到文件**末尾**（该文件不是全序的，全量重写会把上千个键重排）。
