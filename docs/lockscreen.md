# 锁屏

> **范围**：`dot_config/quickshell/end4-pC/modules/ii/lock/`
> **历史变更**：[CHANGELOG.md](../CHANGELOG.md)

`Super+L` 触发 `quickshell:lock`。锁屏采用 Serpantinum 风格三栏布局：初始
只有居中大时钟（时:分、日期、分时段问候），点击任意处或按任意键展开，大
时钟缩小上移，三栏翼面板从下方浮现。

| 栏位 | 内容 |
|---|---|
| 左翼 | 系统监控四宫格：CPU / 内存 / 温度 / 磁盘，环形进度 + 居中数值 |
| 中翼 | 头像、用户名与状态、密码框、键盘布局与电池胶囊、电源按钮（休眠 / 重启 / 关机） |
| 右翼 | 歌词卡（当前行前后共 7 行）、通知列表、媒体卡（封面、曲名、进度、播放控制） |

`Esc` 收起并清空密码。头像加载链与桌面 `UserCardWidget` 一致：
`Config.options.profile.avatarPath` 优先，否则读 `~/.face`，失败回退 person
图标。歌词直接复用 `LyricsService`，与桌面歌词同一数据源。

认证复用 `LockContext`（PAM + 指纹 + keyring），配色、圆角、字体、动画
曲线全部取自 `Appearance`。背景是模糊后的桌面壁纸（与桌面同一源链，含
`lockWall` 覆盖与视频缩略图分支）。hypridle 超时锁屏走同一入口；
quickshell 未运行时使用 hyprlock。
