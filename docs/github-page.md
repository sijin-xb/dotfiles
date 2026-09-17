# GitHub 项目页

两个入口，**共用同一份数据和逻辑**（`services/GitHub.qml`）：

| 入口 | 位置 | 用途 |
|---|---|---|
| **仪表盘第 5 页** | 栏中央时钟 → 左键开仪表盘 → 切到「GitHub」页（`modules/ii/bar/ClockDashboard.qml`） | 日常快速查看 |
| 设置页 | 设置 → **GitHub**（`modules/ii/settings/pages/GitHub.qml`） | 完整的配置项（fork / 归档 / 上限） |

填一个 GitHub 用户名，页面会列出该用户的公开仓库；点任意仓库在浏览器打开对应页面。

## 1. 使用方式

### 仪表盘第 5 页

1. 左键点栏中央的时钟 → 打开仪表盘
2. 底部切到 **GitHub**（或按 `←` `→` / 滚轮 / 左右滑动）
3. 在输入框里填用户名（例如 `torvalds`），**按回车提交**（避免每敲一个字母就发一次请求）
4. 卡片网格支持页内滚动

### 设置页

1. 打开设置面板（`SUPER + I`，或 `qs -c end4-pC ipc call settings toggle`）
2. 左侧选 **GitHub**
3. 在「GitHub username」里填用户名，输入停止 0.7 秒后自动拉取

### 卡片显示的信息

- 仓库名（私有仓库带锁图标）
- `fork` / `archived` 徽标
- 描述（最多 3 行，超出省略）
- 语言（带色点）、Star 数、Fork 数、最后更新时间（相对时间：today / N days ago / …）
- 点击卡片 → `xdg-open` 打开 `html_url`

页面上的其它控件：

| 控件 | 作用 |
|---|---|
| Include forks | 是否把 fork 的仓库也列出来（默认关） |
| Include archived | 是否把已归档的仓库也列出来（默认关） |
| Max repositories | 最多展示多少个（5~100，默认 30） |
| Reload | 手动重新拉取 |
| Open profile | 打开 `https://github.com/<用户名>` |

配置项在 `Config.options.github`（`username` / `repoLimit` / `includeForks` / `includeArchived`），
会随其它设置一起持久化到 `~/.config/illogical-impulse/config.json`。

## 2. 为什么走 `gh` CLI 而不是直接请求 api.github.com

拉取命令：

```bash
gh api "users/<用户名>/repos?per_page=100&sort=updated" \
  --jq '[.[] | {name, description, html_url, language, stargazers_count,
                forks_count, updated_at, private, fork, archived, homepage, topics}]'
```

- **不碰凭据**：`gh` 自己管理 token（`~/.config/gh/hosts.yml`），页面里没有任何 secret
- **速率额度**：匿名请求 60 次/小时，登录后 5000 次/小时
- **能看到私有仓库**：属于自己或已授权的私有仓库也会列出来（卡片上有锁图标）

因此**前提是本机装好并登录了 `gh`**：

```bash
gh auth login          # 一次性
gh auth status         # 确认
```

## 3. 状态与异常处理

页面用一句话状态行 + 空状态卡片覆盖所有情况：

| 情况 | 表现 |
|---|---|
| 还没填用户名 | 「Enter a username above to list repositories.」+ 空状态卡片 |
| 加载中 | 转圈指示 + 「Loading…」 |
| 用户不存在 / 名字打错 | 显示 `gh` 的 stderr（通常是 `HTTP 404: Not Found`） |
| 网络失败 | 显示 `gh` 的 stderr（`dial tcp ...` / 超时之类） |
| 没登录 `gh` | 「gh exited with code N. Did you run \`gh auth login\`?」 |
| 用户没有任何仓库 | 「This user has no public repositories.」 |
| 返回内容解析失败 | 「Failed to parse GitHub response.」，原始错误打到日志 |
| 输入改了但还没拉完 | 状态行右侧提示「(input changed, reloading…)」 |

## 4. 实现要点

- **列表用两列卡片网格**：外层 `Repeater` 按 `ceil(n/2)` 生成行，每行一个
  `RowLayout`，里面再放两个 `Item`（`Layout.fillWidth: true` + `Layout.preferredWidth: 0`
  均分宽度），`Item` 里才是 `RepoCard`。
  delegate **必须显式给 `implicitHeight`**（`RepoCard` 是 `anchors.fill` 到它的），
  否则 RowLayout 量不出高度、整行塌成 0。
- `RepoCard` 是**独立文件**（`pages/RepoCard.qml`），不是 inline component ——
  一开始写成 `component RepoCard: Rectangle {}` 放在根对象内部，Quickshell 报
  `Syntax error`（inline component 必须与根对象同级，放在文档顶层）。
- `Process` 改 `command` 前必须先 `running = false`，否则改不动。
- 相对时间在 `RepoCard.relativeDate()` 里算，`today / yesterday / N days ago /
  N months ago / N years ago`，都过 `Translation.tr()`。

## 5. 排障

**页面一直显示「Loading…」** → 看 `~/.config/quickshell/end4-pC` 的运行日志里
有没有 `[GitHub] parse failed`；再手动跑一遍第 2 节那条 `gh api` 命令确认它本身能出结果。

**`gh` 命令能跑但页面空** → 检查是不是全被过滤掉了：
默认 `includeForks = false`，如果该用户的仓库几乎都是 fork，就只剩很少几个。
状态行会显示 `已显示 / 总数`（例如 `1 / 3 repositories`）。

**设置页是懒加载的** → 改动 `pages/GitHub.qml` 后启动日志不会报它的错。
要验证语法，临时在 `shell.qml` 里挂一个 `Loader { source: "modules/ii/settings/pages/GitHub.qml" }`
跑一次，确认无 `Syntax error` / `unavailable` 后再删掉。
