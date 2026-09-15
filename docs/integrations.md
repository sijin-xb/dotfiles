# 外部集成

> **历史变更**：[CHANGELOG.md](../CHANGELOG.md)

## SPlayer 歌词联动

桌面歌词默认走 MPRIS + 酷狗抓词。如果播放器是 **SPlayer**，可以在它的
「设置 → WebSocket 服务」里打开服务（默认端口 **25885**），歌词会直接由
SPlayer 推送，省掉抓取、也不用等网络。

~~~
SPlayer --WebSocket(25885)--> scripts/desktopLyrics/splayer-ws.py
                                    │ 每行一个 JSON（stdout）
                                    ▼
                        Quickshell DesktopLyrics（Process + SplitParser）
~~~

协议（从 SPlayer 的 app.asar 里确认，WS 为单向广播）：

| 消息 | data |
|---|---|
| `welcome` | 连接成功 |
| `song-change` | `title` / `name` / `artist` / `album` / `duration` |
| `lyric-change` | `lrcData` / `yrcData`（**行数组**，每行含 `startTime`/`endTime`/`words[].word`/`translatedLyric`，时间单位 ms） |
| `progress-change` | `currentTime` / `duration`（ms，约每 0.5s） |
| `status-change` | `status`（播放/暂停） |

实现要点：

- `scripts/desktopLyrics/splayer-ws.py` 是纯标准库的极简 WebSocket 客户端，
  把上述消息归一成 `{"type":"lyric","lines":[...]}` 等 JSON 行写 stdout，
  断开后每 3s 自动重连（SPlayer 重启无需干预）。
- QML 侧把数据喂给现有的 `lyricLines` / `currentTime` / `isPlaying`，
  下游（歌词视图、锁屏、桌面宠物）无需改动。
- **只有真的收到 WS 歌词才接管**（`splayerHasLyrics`）：SPlayer 只在换歌时
  推 `lyric-change`，刚连上时可能还没有歌词，此时保留 MPRIS + 酷狗流程兜底。
- 接管后 `doFetch()` 直接返回、MPRIS 精同步定时器停摆，避免两边互相覆盖。
- 关闭：`background.desktopLyricsSplayerEnable = false`（或改端口
  `desktopLyricsSplayerPort`）。

## fcitx5-rime × matugen 取色联动

fcitx5-rime 的候选框外观由 fcitx5 的 Classic UI 主题控制，matugen 每次换壁纸后
自动重新生成该主题文件，实现输入法配色与壁纸同步。

### 工作原理

~~~
壁纸换色（switchwall.sh）
  └─ matugen 取色
       └─ [templates.fcitx5] → ~/.local/share/fcitx5/themes/Matugen/theme.conf
                                  ↑ 由 dot_config/matugen/templates/fcitx5-theme.conf 渲染
~~~

`fcitx5-theme.conf` 模板使用 Material You 语义颜色：

| 模板变量 | 含义 | 用途 |
|---|---|---|
| `colors.surface_container` | 表面容器色 | 候选框背景 |
| `colors.primary` | 主色 | 预编辑高亮背景 |
| `colors.secondary_container` | 次级容器色 | 选中候选背景 |
| `colors.on_surface` | 表面前景色 | 普通文字 |
| `colors.on_primary` | 主色前景 | 预编辑高亮文字 |
| `colors.on_secondary_container` | 次级前景 | 选中候选文字 |
| `colors.outline` | 轮廓色 | 边框 |

### 相关文件

| 文件 | 说明 |
|---|---|
| `dot_config/matugen/templates/fcitx5-theme.conf` | matugen 模板，每次换壁纸重新渲染 |
| `dot_config/matugen/config.toml` → `[templates.fcitx5]` | 模板注册条目 |
| `dot_config/fcitx5/conf/classicui.conf` | `Theme=Matugen`（启用生成的主题） |
| `dot_local/share/fcitx5/rime/default.custom.yaml` | 全局按键 / 翻页定制 |
| `dot_local/share/fcitx5/rime/rime_ice.custom.yaml` | 雾凇拼音语法权重调整 + `/` 符号候选框 |

> **注**：fcitx5-rime 在 Linux 下无独立的皮肤系统（squirrel.yaml / weasel.yaml
> 是 macOS / Windows 专用），候选框样式完全由 fcitx5 Classic UI 主题决定，因此
> 接入 matugen 只需配置该主题即可，无需额外处理 rime 侧的配色。

### 中文模式下 `/` 弹出符号候选框

中文模式下按 `/` 会弹出常用符号候选框，用 `,` / `.` 翻页
（`default.custom.yaml` 里已把它们映射为 Page_Up / Page_Down）。

**权重就是列表顺序**：librime 的 `PunctTranslator` 用 `FifoTranslation`，
列表第 N 项就是第 N 个候选，`punctuator` 的定义没有独立 weight 字段。
所以按使用频率排了 49 项，`page_size = 9` 下第一页即为
`/ ， 。 、 ？ ！ ： ； “` —— 日常写中文不用翻页。半角 `/` 固定在首位，
打 `/` 后按空格就能上屏字面量斜杠。要调权重直接改
`rime_ice.custom.yaml` 里的顺序再重新部署即可。

实现方式是把 `half_shape` 里的 `/` 由单值 `'/'` 改成多值列表。
原理见 librime `src/rime/gear/punctuator.cc`：取到标点定义并把按键推入输入串后，
只有**单值映射**才会立即上屏（`ConfirmUniquePunct`），列表型映射只列出候选，
交给用户选择。

改这个配置有两个坑：

1. 必须写成扁平路径 `punctuator/half_shape/+`（映射追加）的形式。
   写成嵌套结构 `punctuator: { half_shape: ... }` 会把整个 `punctuator` 节点
   替换掉，v 模式符号表和全角标点会一起消失。
2. 键名 `/` 不能出现在路径里（会被当成路径分隔符），只能放在值里。

改完需要重新部署才会生效：

~~~bash
rime_deployer --build ~/.local/share/fcitx5/rime /usr/share/rime-data
fcitx5-remote -r      # 让 fcitx5 重新加载
~~~

部署后可用 `build/rime_ice.schema.yaml` 校验合并结果
（`punctuator.half_shape` 应保留全部 32 个键，`/` 是多值列表，
`punctuator.symbols` 应仍有 266 项）。
