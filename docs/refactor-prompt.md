# 重构提示词（可直接交给 AI 编程助手）

> 本文分两部分：**A. 项目体检结果**（重构要解决什么，含实测数据）
> 和 **B. 可直接复制的提示词**（整块交给 AI 用）。
> 配套阅读：[CODEBUDDY.md](../CODEBUDDY.md)（项目自己的协作规范）。

---

## A. 项目体检结果

### A.1 规模（实测）

| 项 | 数值 |
|---|---|
| QML 文件 | **697 个** |
| QML 总行数 | **92,804 行** |
| Python 脚本 | 26 个（`scripts/`） |
| Hyprland Lua 配置 | 20 个 |
| 翻译文件 | 14 个语言 JSON |
| 自动化测试 | **无** |

### A.2 最大的文件（超过 750 行，重构重点）

| 行数 | 文件 |
|---|---|
| 1568 | `modules/ii/settings/pages/BackgroundConfig.qml` |
| 1406 | `modules/ii/settings/pages/InterfaceConfig.qml` |
| 1402 | `modules/ii/bar/ClockDashboard.qml` |
| 1091 | `modules/ii/lock/SerpantinumLockSurface.qml` |
| 1050 | `modules/ii/background/Background.qml` |
| 931 | `modules/common/Config.qml` |
| 917 | `services/Ai.qml` |
| 914 | `modules/ii/background/widgets/media/MediaWidget.qml` |
| 874 | `modules/ii/settings/pages/Profile.qml` |
| 795 | `modules/ii/sidebarLeft/AiChat.qml` |
| 755 | `modules/ii/settings/pages/BarConfig.qml` |

### A.3 已确认的具体问题（都有代码位置）

1. **栏组件被重复实例化**（性能）
   `modules/ii/bar/BarContent.qml` 里 material 与 legacy 两套布局各自有一个
   `Repeater`，都遍历同一份布局模型 —— 同一批栏组件被创建两遍，
   只有一套可见。应改成只实例化当前样式需要的那一套。

2. **循环绑定 + 靠 `x < 0` 判可见**（脆弱）
   `modules/ii/bar/Resource.qml`：
   `implicitWidth` 依赖 `resourceRowLayout.x`，而 `x` 又依赖
   `resourceRowLayout.width`。展开/收起靠「x 是否为负」驱动，
   再加上 `Behavior on x` 的弹簧曲线会短暂过冲，边界情况不可预测。

3. **组件依赖缺失导入**（已在最近一次修掉 2 处，但模式仍存在）
   `Translation.tr(...)` 被使用但文件没 `import qs.services` →
   运行期 `ReferenceError: Translation is not defined`，
   而且**只有该组件被创建时才触发**（启动日志看不到）。
   同类风险：跨目录单例（`Persistent` / `ResourceUsage` / `DateTime` 等）漏导入。

4. **静默失效的 QML 写法**
   - 同一对象写两个 `Component.onCompleted` → `Property value set multiple times`
     → 组件变 `unavailable` → **继承它的所有组件连锁失效**，日志里只有一行 WARN。
   - inline component（`component X: Y {}`）写在根对象内部 → `Syntax error`
     （必须与根对象同级）。
   - 属性名写错（如 `Appearance.animation.x.easing` 而实际叫 `type`）
     只会产生一行 `Unable to assign [undefined]` 告警，动画静默失效。

5. **巨型单文件**
   上表 11 个文件占了大头。典型症状：一个文件里塞了数据获取、状态机、
   布局、样式、i18n 文案，改一处要通读上千行。

6. **死代码**
   - `scripts/lyrics/lyrics.py`：已被 `services/LyricsService.qml` 取代，无引用
   - `modules/ii/bar/ClockWidgetPopup.qml`：不再被实例化
   - `modules/ii/bar/WeatherBar.qml` 的 `property bool hovered`：声明后从未使用
   - `modules/ii/bar/UtilButton.qml` 的 `mouseArea` id：不再被引用

7. **i18n 历史欠账**（非本次引入）
   各语言相对 `en_US` 缺 32~522 条；缺失 key 回退显示英文，不报错。
   补法：`translations/tools/manage-translations.sh update -l <语言>`

8. **无自动化测试**
   697 个文件、无构建步骤、无测试，全靠人肉验证。
   这也是「静默失效」类问题反复出现、且难以及时发现的原因。

### A.4 验证手段现状（重构必须知道）

- 项目自带 `translations/tools/manage-translations.sh`（翻译状态/更新/同步）
- 启动期问题排查脚本（见 `docs/troubleshooting.md`）：
  必须同时 grep `unavailable` 与 `Property value set multiple times`，
  **只 grep `ERROR` 会漏掉最要命的那类问题**
- 视觉验证：`grim -o <输出> /tmp/s.png` 截图 + 裁剪看细节
- 注意 `CODEBUDDY.md` 里写了「不要用 `timeout` 反复启动 Quickshell」，
  但热重载观察抓不到 `unavailable` 类问题，实际排查时需要一次冷启动体检 ——
  两者的取舍请按当时情况决定

---

## B. 可直接复制的提示词

````text
# 任务：重构 Quickshell 桌面配置（end4-pC）的前端代码

## 1. 项目背景

这是一个基于 illogical-impulse 的 **Quickshell 桌面配置 fork**（Linux / Hyprland /
Wayland 的桌面外壳）。它没有构建步骤，QML 由 Quickshell 运行时直接加载；
Hyprland 自身配置用 Lua；另有 26 个 Python 辅助脚本。

- 项目根：`~/.config/quickshell/end4-pC`
- 规模：**697 个 QML 文件，约 92,800 行**；无自动化测试
- 入口：`shell.qml`（加载 `modules/common`、`services`、`panelFamilies`，
  并挂载 `DesktopLyrics` 与 `DynamicIslandHost`）
- 主要目录：
  - `modules/ii/` 功能模块（bar / sidebarLeft / sidebarRight / overview / launcher /
    settings / lock / dynamicIsland / desktopLyrics / wallpaperSelector …）
  - `modules/common/` 共享组件与 `Config`、`Appearance` 单例
  - `services/` 共享服务（MPRIS、音频、亮度、歌词、壁纸、GitHub…）
  - `translations/` 14 个语言 JSON（`en_US.json` 是键结构基准）
  - `scripts/` Python 辅助脚本
- 项目自带的协作规范在 `CODEBUDDY.md`，**先读它**；
  排障经验在 `docs/troubleshooting.md`；架构说明在 `docs/`。

## 2. 技术栈与运行环境

- Qt 6 / QML（`QtQuick`、`QtQuick.Layouts`、`QtQuick.Effects`、`QtQuick.Controls`）
- Quickshell（含 `Quickshell.Wayland`、`Quickshell.Hyprland`、`Quickshell.Services.*`、
  `Quickshell.Io`、`Quickshell.Wayland._Screencopy`）
- Hyprland（Lua 配置）+ Wayland
- Python 3（辅助脚本，含 PyQt/Pillow 等）
- 无构建、无打包、无 CI、**无测试套件**

## 3. 重构目标（按优先级）

### P0 —— 消除「静默失效」类问题（最高优先）
这类问题不报 ERROR，只让组件悄悄消失或动画失效，是最难查的：

1. 全项目排查**同一对象上出现多个 `Component.onCompleted`**，合并成一个。
2. 全项目排查**根对象内部的 inline component**（`component X: Y {}`），
   移到独立文件或文档顶层。
3. 全项目排查**用了跨目录单例却没导入**的文件。已知模式：
   `Translation.tr(...)` 但没有 `import qs.services`。
   注意：`services/` 目录内的文件属于同一模块，靠目录隐式导入即可，**不要**给它们加导入。
4. 排查**指向不存在属性的绑定**（如把 `animation.*.type` 写成 `.easing`），
   这类只会产生 `Unable to assign [undefined]` 告警。

### P1 —— 拆分巨型文件
把超过 750 行的文件按职责拆开（数据/状态机 → 布局 → 子组件 → 样式），
单文件目标 **≤ 400 行**。重点：

- `modules/ii/settings/pages/BackgroundConfig.qml`（1568）
- `modules/ii/settings/pages/InterfaceConfig.qml`（1406）
- `modules/ii/bar/ClockDashboard.qml`（1402）
- `modules/ii/lock/SerpantinumLockSurface.qml`（1091）
- `modules/ii/background/Background.qml`（1050）
- `modules/common/Config.qml`（931）—— 配置项分组抽成独立 JsonObject 文件
- `services/Ai.qml`（917）、`modules/ii/background/widgets/media/MediaWidget.qml`（914）
- `modules/ii/settings/pages/Profile.qml`（874）
- `modules/ii/sidebarLeft/AiChat.qml`（795）
- `modules/ii/settings/pages/BarConfig.qml`（755）

拆分时保持**行为完全不变**，并复用已有的公共组件（`modules/common/widgets/`）。

### P2 —— 修掉已确认的具体缺陷

1. **栏组件被重复实例化**：`modules/ii/bar/BarContent.qml` 里 material 与 legacy
   两套布局各有一个 `Repeater` 遍历同一份模型，同一批组件创建两遍（只有一套可见）。
   改成只实例化当前样式需要的那一套（用 `Loader` + `active` 或按样式选一个 Repeater）。
2. **循环绑定**：`modules/ii/bar/Resource.qml` 的 `implicitWidth` ↔
   `resourceRowLayout.x` 互相依赖，且用「x 是否为负」判可见。
   改成用显式的 `shown` / `expanded` 状态驱动宽度，去掉对坐标的依赖。
3. **清理死代码**（确认无引用后再删，并在提交信息里列出）：
   - `scripts/lyrics/lyrics.py`
   - `modules/ii/bar/ClockWidgetPopup.qml`
   - `modules/ii/bar/WeatherBar.qml` 的 `property bool hovered`
   - `modules/ii/bar/UtilButton.qml` 里不再被引用的 `mouseArea` id

### P3 —— 建立最小验证网（不引入重型框架）
- 写一个**启动期体检脚本**：冷启动一次 Quickshell，把日志按
  「加载失败/编译错误」「运行期 JS 错误」「其它 scene 告警」三类分别输出。
  **必须覆盖 `unavailable` 与 `Property value set multiple times` 两个关键字**
  （只 grep `ERROR` 会漏掉最要命的问题）。注意排除
  `WARN quickshell.colorquantizer: Failed to load image` 这类假阳性。
- 写一个**硬编码文案审计脚本**：扫描所有 `.qml`，
  找出直接写在 `text:` / `title:` / `placeholderText:` 等属性上的裸字符串
  （排除含 `Translation` / `qsTr` 的行、注释、纯符号/数字）。
  当前基线是 **0 处**，重构不得让这个数字变差。

## 4. 必须遵循的规范

1. **先读再改**：读目标文件及其同目录直接依赖，不要凭记忆猜模块结构。
2. **保持风格**：4 空格缩进、中文注释、`.qmlformat.ini` 的格式规则。
3. **最小改动**：不要顺手重构未涉及的模块。一次提交只做一件事。
4. **保留用户改动**：改前改后都看 `git diff`，**绝不**执行
   `git reset --hard`、**绝不**覆盖无关文件。
5. **注释写「为什么」**：踩过的坑、反直觉的写法、参数取值理由，
   都要留注释说明。项目现有代码的注释风格就是这样的，请沿用。
6. **i18n 全覆盖**：所有用户可见文本一律走
   `Translation.tr("English text")`，禁止裸字符串。
   新增文案要补进全部 14 个语言文件（`translations/*.json`），
   **文件必须按 key 的码点排序**，只做插入不要重排。
7. **跨目录单例必须显式导入**（同目录可依赖隐式导入）。
8. **禁止使用会被静默忽略的写法**：同一对象的重复属性赋值、
   指向不存在属性的绑定、根对象内部的 inline component。
9. **不要引入新依赖**（新 QML 模块 / Python 包 / 系统包），
   除非先说明理由并得到确认。

## 5. 期望产出

请按下面的顺序交付，**不要一次性大范围改完再汇报**：

### 第 1 步：体检报告（先给我看，不要动代码）
- P0 三类问题（重复 `onCompleted` / 非法 inline component / 缺失导入）
  的**完整清单**：文件路径 + 行号 + 问题说明
- 指向不存在属性的绑定清单
- 巨型文件拆分方案：每个文件拆成哪几个、各自职责、依赖关系
- 你打算怎么验证每一步（具体命令）

### 第 2 步：按 P0 → P1 → P2 → P3 分批实施
每批：
- 一次提交只做一类改动，提交信息说明「改了什么 / 为什么 / 怎么验证的」
- 每批改完立刻跑体检脚本，报告三类问题的数量变化
- 涉及界面布局的改动，用 `grim -o <输出> /tmp/x.png` 截图自证，
  并说明你看到的和预期是否一致

### 第 3 步：收尾
- 更新 `CHANGELOG.md`（追加当日条目，不要覆盖历史）
- 若新增/改动了文档结构，同步 `README.md` 与 `docs/README.md`
- 最后给一份「无法自动验证的部分」清单（哪些只能人肉看）

## 6. 验证方式（每批都要做）

```bash
# 1. 启动期体检（必须包含 unavailable 与 Property value set multiple times）
killall qs 2>/dev/null; sleep 1.5
timeout 16 qs -c end4-pC > /tmp/qs-check.log 2>&1
grep -nE "unavailable|Property value set multiple times|Failed to load|Syntax error" /tmp/qs-check.log | sort -u
grep -nE "ReferenceError|TypeError|Unable to assign|Cannot read" /tmp/qs-check.log | sort -u

# 2. 热重载观察（改单个文件时用，比冷启动快）
qs -c end4-pC log > /tmp/qs.log 2>&1

# 3. 界面验证
grim -o <输出名> /tmp/s.png        # 输出名用 hyprctl monitors 查
hyprctl layers | grep -oE "xywh: [0-9 ]+, a: [01], namespace: [a-zA-Z:]+"

# 4. 翻译改动后
translations/tools/manage-translations.sh status

# 5. 提交前
git diff --check
```

**验收标准（每批都必须满足）**：
- 体检脚本的三类计数**不增加**（目标：全为 0）
- 硬编码文案审计结果保持 **0 处**
- `git diff --check` 无空白错误
- 界面截图与改动前**视觉一致**（除非该批就是改视觉）

## 7. 禁止事项

- 不要改动 `~/.config/illogical-impulse/config.json`（用户的运行时配置）
- 不要改动 `translations/tools/` 下的工具脚本本身
- 不要执行 `manage-translations.sh clean`（会删 key）
- 不要执行 `git reset --hard` / `git push --force`
- 不要删除 `modules/ii/lock/caelestia/` 下移植自上游的文件结构
- 不要移除任何**用户可见功能**；重构是「等价变换」，
  功能变更必须单独提出并等我确认
- 不要引入构建步骤、打包器、测试框架等重型工具

## 8. 背景补充：这个项目最怕什么

历史教训（`docs/troubleshooting.md` 里有完整记录）：

1. **静默失效最难查**：组件编译失败变成 `unavailable` 后，继承它的组件会连锁失效，
   表现为「栏里某组组件凭空消失、后面的元素整体左移」，而日志里**没有 ERROR**。
2. **设置页是懒加载的**：改 `modules/ii/settings/pages/*.qml` 后，
   启动日志**不会**报它的语法错误。必须临时在 `shell.qml` 挂一个
   `Loader { source: "..." }` 强制实例化才能验证。
3. **QML 的错误经常只在组件被创建时出现**，不在启动时出现。
   所以「启动干净」不等于「没问题」——凡是新写/改动的组件，
   都要想办法让它真的被创建一次。
````

---

## C. 推荐的 AI 编程助手

### 首选：Claude Code（Anthropic）

| 维度 | 说明 |
|---|---|
| 为什么适合 | 本项目是「无测试、无构建、靠跑起来看日志」的形态，需要助手能**自己跑命令、读日志、看截图**并据此迭代 —— 这正是 agentic CLI 的强项 |
| 大上下文 | 697 文件 / 9.2 万行，需要能按需检索而不是一次性塞入；Claude Code 的文件检索 + 长上下文组合比较稳 |
| 多文件重构 | 拆分巨型文件要同时改十几个文件，agentic 模式比「逐行补全」高效得多 |
| 配套 | 项目里已有 `CODEBUDDY.md`（协作规范），把它改成 `CLAUDE.md` 即可被自动读取 |

### 备选

| 工具 | 适合场景 | 短板 |
|---|---|---|
| **Cursor**（Agent 模式） | 需要频繁在 IDE 里看 diff、逐段微调；QML 没有官方 LSP 补全，靠模型理解 | 大范围跨文件重构不如 CLI agent 顺 |
| **GitHub Copilot** | 你本机已登录 `gh`，`gh copilot` 可直接在终端里问命令；PR 审查（Copilot review）对 `dotfiles` 仓库的提交很有用 | 对 QML/Quickshell 这种小众生态的先验知识少，容易编 API |
| **Gemini CLI / Codex CLI** | 超长上下文（适合一次性读完一个大目录）、成本较低 | 对 Quickshell 专有 API 同样容易编，需要靠「读 qmltypes」纠正 |

### 针对本项目的特别建议

1. **让它读 `qmltypes` 而不是猜 API**。
   Quickshell 的专有类型声明在
   `/usr/lib/qt6/qml/Quickshell/**/quickshell-*.qmltypes`，
   Qt 的在 `/usr/lib/qt6/qml/QtQuick/Effects/plugins.qmltypes` 等。
   提示词里明确要求「不确定的 API 去 qmltypes 里查」，能大幅减少编造。
2. **给它装一个「体检脚本」当眼睛**。
   本项目没有测试，助手必须靠日志判断对错。
   `docs/troubleshooting.md` 里的启动期体检脚本就是它的眼睛 —— 先让它跑通这个，
   再谈重构。
3. **把「禁止事项」写死在提示词里**。
   这个项目是用户的**真实桌面配置**，误删/误改会直接破坏使用环境。
   上面第 7 节那份禁止清单建议原样保留。

---

## D. 「背景发脏」的成因与改进方向

### D.1 为什么会发脏

「脏」在设计上通常指**低饱和、低对比、灰蒙蒙**。这个界面上有四个成因叠加：

1. **高斯模糊把互补色混成灰泥**（最主要）
   模糊本质是邻域平均。背景里颜色差异越大、纹理越碎（终端文字、图标、
   高频壁纸图案），平均之后就越接近中性灰。这是数学结果，不是错觉。

2. **多层半透明叠加**
   栏药丸 + 面板底色 + 高光渐变 + tooltip，每层都是半透明。
   每次混合都在做「向灰色靠拢」的加权平均，层数越多越灰。

3. **底色用的是中性近黑**
   `colLayer1Base` 这类 M3 surface 色本身是低饱和的近黑/近白。
   用它们当玻璃底色，等于给画面蒙了一层灰膜 —— 而玻璃本该是**带色彩倾向**的。

4. **模糊半径过大**
   半径越大，采样范围越远，把画面里不相干的颜色也平均进来，
   局部色彩关系被破坏，看起来就「糊成一团脏」。

另外还有两个次级因素：
- **没有噪点**：大面积渐变 + 8bit 色深 → 色带（banding），视觉上也像脏
- **背景本身信息密度高**：截图中面板背后是终端文字，糊掉后是「文字的鬼影」，
  比纯色背景更容易读成脏

### D.2 已经做的改进（本次提交）

在 `GlassBackdrop` 的模糊层上加色彩校正，直接抵消第 1、3 条：

```qml
saturation: 0.18    // 提饱和，把被平均掉的色彩拉回来
brightness: 0.04    // 抬一点亮度，避免整体发闷
contrast: 0.06      // 加对比，让色块边界重新清晰
```

并把玻璃底色 alpha 从 `0.78` 压到 `0.55`（`LiquidGlass.minAlpha` 的下限），
让校正过的模糊层真正透出来 —— 之前底色太厚，糊了也白糊。

### D.3 还可以继续做的方向

| 方向 | 做法 | 预期效果 |
|---|---|---|
| 给玻璃加色彩倾向 | 用 matugen 从壁纸取的**主色**（而不是中性 `colLayer1Base`）当底色，压低 alpha | 玻璃带壁纸色调，不再是一层灰膜 |
| 降低模糊半径 | `qmlBackdropBlurRadius` 从 56 降到 36~44，配合提饱和 | 保留局部色彩关系，减少远距离混色 |
| 减少叠加层数 | 面板内的子元素不要再用半透明底，改用不透明 + 描边 | 少一次灰化 |
| 加噪点 | 叠一层极低透明度的噪点纹理（或 `MultiEffect` 后接一个 noise shader） | 破 banding，质感更像磨砂玻璃 |
| 提高边缘对比 | `LiquidGlass.edgeHighlight` 的外亮内暗再加强一点 | 轮廓清楚，观感不「糊」 |
| 换壁纸 | 选低对比、大面积色块的图，避开高频细节/文字截图 | 从源头减少混色 |
| 关掉部分面板的模糊 | 静态面板直接给不透明底色 | 该实的地方实，对比拉开 |

**一句话结论**：脏的主要来源是「模糊把颜色平均成灰」+「中性灰底色太厚」。
已经用「提饱和 + 减薄底色」对症处理；想再上一个档次，
下一步应该让玻璃底色**继承壁纸主色**，而不是继续用中性 surface 色。
