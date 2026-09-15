# 外观：视频壁纸与视差

> **范围**：Quickshell `background` 模块、`switchwall.sh`、mpvpaper 后端
> **历史变更**：[CHANGELOG.md](../CHANGELOG.md)

## 视频壁纸后端

视频壁纸可以在「设置 → 背景 → 视频壁纸后端」中选择：

| 后端 | 适合场景 |
|---|---|
| **Mpvpaper** | 推荐，稳定可靠，逐显示器启动 |
| **Phonto** | 适合测试 GPU 视频播放和低占用表现 |
| **Wallr** | 功能更完整，但存在视频随机冻结的已知问题，见下 |

Mpvpaper 是默认后端。Wallr 和 Phonto 都是可选依赖；没有安装时，脚本会自动回退到 Mpvpaper，不会影响已有视频壁纸。

### Wallr 已知问题：视频随机冻结

Wallr 的壁纸会**突然定格不动**——视频解码线程可能仍在运行，但渲染循环停止更新，画面停在最后一帧。常见触发场景包括：

- 显示器 DPMS 休眠后唤醒
- 全屏不透明窗口完全遮挡背景层
- 显示器热插拔或分辨率 / 缩放变更

临时恢复方法是重启 daemon（`pkill wallr` 后重新 `wallr daemon`）。

由于该问题尚未在上游修复，默认后端保持为 Mpvpaper。如果仍想试用 Wallr，可在设置中手动切换，并留意上述场景。

开发者可直接编辑：

~~~json
{
  "background": {
    "videoBackend": "mpvpaper"
  }
}
~~~

可选值为 `mpvpaper`、`phonto`、`wallr`。切换后重新选择一次视频壁纸即可生效。脚本会先停止其他视频壁纸进程，确保不会同时运行多个后端。

> Mpvpaper 后端启动时会额外带上 `input-ipc-server=~/.cache/quickshell/mpvpaper/mpvpaper-<显示器名>.sock`，
> 供 Quickshell 实现视频壁纸视差（见下一节）。其他后端不带该 socket，视差会自动跳过。

## 壁纸视差

「设置 → 背景 → 壁纸视差」开启后，切换工作区 / 开合侧栏 / 移动鼠标时壁纸会做
轻微平移，产生景深感。静态壁纸和视频壁纸都支持，两者的位移量完全一致。

### 静态壁纸

- 壁纸在 Quickshell 内绘制：先按 `workspaceZoom`（默认 1.07）缩放，再平移，
  位移被 clamp 在缩放留出的余量内。
- **工作区映射覆盖全部工作区**：按工作区号线性映射到 `-1 ~ +1` 再乘可移动余量。
  工作区总数取「设置 → 工作区数量」、「已出现过的最大工作区号」、「概览网格列数」
  三者中的最大值，因此第 6~10 个工作区也有各自独立的视差位置
  （旧实现按概览列数取模，超过 5 个工作区位置就开始重复）。
- **光标跟随只作用于壁纸层**：开启后桌面部件不会跟着鼠标抖动。部件层只跟随
  侧栏开合做轻微景深位移（`widgetsFactor`），工作区切换时保持原位。
- **缩放余量自动补足**：开启侧栏平移时 `workspaceZoom` 会自动提升到
  「可移动余量 ≥ sidebarShift」，避免侧栏位移被 clamp 截断；否则壁纸在
  某些分辨率下会移不到位。
- **过渡动画用 `Easing.OutCubic`，时长默认 400ms**。
  - 时长：Hyprland 的 `workspaces` 是 `speed = 7` 即 700ms（`speed` 的单位是
    ds，1ds = 100ms），但滚轮连续切工作区时 700ms 太长、视差追不上切换，
    看起来就是卡，所以取 400ms。可用「工作区过渡时长」在 200~1400ms 之间调。
  - 曲线：**不要用 `Easing.BezierSpline` + 4 个值的 `bezierCurve`**。
    Qt 需要 3 个控制点（6 个值，末点必须是 `1, 1`），少写终点不会报错，
    而是**静默退化成匀速直线**——实测 400ms 的动画到 192ms 才走到 50%，
    壁纸就会匀速慢慢挪、比窗口滑动"慢半拍"。OutCubic 实测 52ms 走 39%、
    192ms 走 88%、352ms 收尾，前段跟手且尾巴很短。
- **不要在每个 Hyprland 事件上做全量刷新**：`services/HyprlandData.qml` 原来
  对每个事件都调 `updateAll()`，而一轮 `updateAll()` 要起 5 个 `hyprctl`
  子进程（实测每个 3~5ms CPU，合计约 20ms）；一次工作区切换会收到近十个事件，
  滚轮连切时成倍，主线程被进程创建拖住，壁纸视差就会掉帧、慢半拍。
  现在按事件类型只刷该刷的数据，并用 40ms 定时器把同一波事件合并成一次；
  `openlayer`/`closelayer` 直接跳过（quickshell 自己开关面板就会发这个事件，
  实测短时间内能来 6 个）。实测 10 个事件只触发 2 轮刷新。
- 壁纸按「显示尺寸 × 缩放」解码（`sourceSize`），8K 壁纸不会整幅载入内存，
  视差放大后也不会发虚。

### 视频壁纸

视频由 mpvpaper 在后景层绘制，Quickshell 碰不到它的图层，因此改为用
**mpv 的 JSON IPC** 驱动：

~~~
switchwall.sh 启动 mpvpaper 时加 input-ipc-server=<socket>
  └─ Quickshell 连上该 socket
       └─ set_property video-zoom / video-align-x / video-align-y
~~~

- socket 路径：`~/.cache/quickshell/mpvpaper/mpvpaper-<显示器名>.sock`
  （两端都基于 XDG 缓存目录，可用 `background.parallax.videoSocketDir` 覆盖）。
- `video-zoom` 传 log2 倍率（`log2(parallaxZoom)`），`video-align-x/y` 传归一化到
  `-1 ~ +1` 的偏移，与静态壁纸的位移等价。
  **注意 mpv 的 `align` 符号与 QML 的 `x/y` 相反**，代码里已取负号，
  两个后端的移动方向保持一致。
- 动画期间约 50Hz 推送、静止时按 `cursorPollInterval` 推送，且**只发送真正
  变化的属性**——否则动画期间每帧重发没变的 `video-zoom`，mpv 每帧都要重配
  视频链，画面会明显卡顿。推送频率也不要超过显示器刷新率：mpv 每收到一次
  `set_property` 就会让视频输出重绘一次，推得太快（试过 125Hz）在滚轮连续
  切工作区时会把 GPU 顶满。
- mpvpaper 比 Quickshell 起得晚时，每 2 秒重建一次连接重试（Quickshell 的
  `Socket` 一次连接失败后不会自己重连）。
- 仅 **mpvpaper** 后端支持；Wallr / Phonto 下视差自动跳过。

### 相关配置

~~~json
{
  "background": {
    "parallax": {
      "enable": true,
      "enableWorkspace": true,
      "workspaceCount": 10,
      "workspaceAnimationDuration": 400,
      "workspaceZoom": 1.07,
      "enableSidebar": true,
      "sidebarShift": 80,
      "widgetsFactor": 1.2,
      "enableCursor": false,
      "cursorSensitivity": 0.3,
      "cursorPollInterval": 50,
      "enableVideo": true,
      "videoSocketDir": ""
    }
  }
}
~~~

> - `workspaceZoom` 现在是**视差强度**（设置页已改名），位移量仍按
>   `屏宽 × (zoom - 1) / 2` 计算。1920 宽屏下：1.07 → 总位移 134px、
>   1.15 → 288px（每工作区 32px）。静态壁纸本体保持 1:1，不再因开启视差放大；
>   平移露出的边缘由后面同一张壁纸的模糊缓存层承接。视频壁纸受 mpvpaper 后端限制，
>   仍需 `video-zoom` 留出移动余量。
> - `workspaceAnimationDuration` 太大会在滚轮连续切工作区时追不上切换，
>   看起来发卡；400ms 左右比较跟手。
