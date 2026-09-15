# 锁屏

> **范围**：`dot_config/quickshell/end4-pC/modules/ii/lock/`
> **历史变更**：[CHANGELOG.md](../CHANGELOG.md)

锁屏采用 Caelestia 风格：模糊壁纸背景上，居中一个圆角方块，里面是旋转的锁图标；
点击或按键后方块展开成横条，露出三栏内容。认证复用 end4-pC 的 `LockContext`
（PAM + 指纹 + keyring）。quickshell 未运行时回退 hyprlock。

## 结构

~~~
modules/ii/lock/
├── Lock.qml                      入口，装配 LockSurface
├── SerpantinumLockSurface.qml    旧版锁屏（保留，可切回）
└── caelestia/                    Caelestia 风格锁屏
    ├── CaelestiaLockSurface.qml  外壳：背景 + 方块展开动画
    ├── components/               vendored 组件（Anim / StyledRect / MaterialIcon ...）
    ├── utils/                    Paths / Strings
    └── content/
        ├── Content.qml           三栏 RowLayout
        ├── Media.qml             媒体卡（接 MprisController）
        ├── LockLyrics.qml        歌词卡（接 LyricsService，本仓库独有）
        ├── Resources.qml         CPU / 内存 / 磁盘（接 ResourceUsage）
        └── center/
            ├── Center.qml        中栏布局
            ├── Clock.qml         分色大时钟（时 m3primary / 分 m3secondary）
            ├── ProfilePic.qml    ClamShell 形状头像
            ├── PasswordInput.qml 密码框 + 箭头形变按钮
            ├── InputField.qml    密码字符（15 种 Material 形状 morph）
            └── StateMessage.qml  密码错误提示
~~~

## 三栏内容

| 栏位 | 内容 |
|---|---|
| 左 | 媒体卡（封面 / 曲名 / 播放控制）、歌词卡 |
| 中 | 分色大时钟、日期、ClamShell 头像、密码框、错误提示 |
| 右 | CPU / 内存 / 磁盘资源卡 |

## 屏幕尺寸

屏幕高度取自 `CaelestiaLockSurface` 自身：

~~~qml
readonly property real screenHeight: root.height > 0 ? root.height : 1080
~~~

本组件由 `LockScreen.qml` 的 `Loader { anchors.fill: parent }` 拉伸至全屏，
所以 `root.height` 就是屏幕高度。**不要走 `parent.screen` 父链** ——
`WlSessionLockSurface` 的子项挂在它的 `contentItem` 下，`parent.parent` 拿到的
是 contentItem 而非 surface 本身，`screen` 会是 `null`，展开尺寸算成 0，
三栏布局会塌缩到屏幕右下角。

展开尺寸：

~~~qml
readonly property real expandedHeight: Math.max(360, screenHeight * 0.58)
readonly property real expandedWidth: expandedHeight * (16 / 9)
~~~

`0.58` 是相对 Caelestia 原版 `0.7` 的下调（1080p 下 756px → 626px），避免
在 1080p 屏上占比过大。

## 视觉细节

- **方块展开**：`lockContent` 从 `96×96` 的正方形动画到
  `expandedWidth × expandedHeight` 的横条，圆角从 `size/4` 变到
  `Appearance.rounding.verylarge`，锁图标旋转 360° 后淡出。
- **背景**：模糊后的桌面壁纸（`MultiEffect`，`blurMax: 64`）叠加 25%
  `m3scrim` 遮罩，保证文字可读。
- **形变动画**：由 `qt6-m3shapes-git` 提供（AUR）。密码字符每输入一位就从一个
  随机 Material 形状（Slanted / Arch / Fan / Gem / SoftBurst …）morph 成圆形；
  提交按钮从圆形 morph 成箭头。
- **配色 / 字体 / 圆角**：全部取自 `Appearance`（`m3colors` / `font` /
  `rounding`），随壁纸 matugen 联动，与 shell 其余部分一致。
- **资源卡对齐**：三个 `MaterialShape`（Pentagon / Slanted / Gem）视觉占比不同，
  统一取 `Math.min(width, height)` 作为形状尺寸并 `anchors.centerIn`，
  避免高低不齐。
- **文案**：所有面向用户的字符串走 `Translation.tr()`，词条在
  `translations/zh_CN.json` 与 `en_US.json`。

## 焦点

密码框创建后会主动获取键盘焦点，并响应 `LockContext.shouldReFocus()`，因此锁屏
唤醒后可以重新输入密码。

## 认证链

`PasswordInput` 直接读写 `LockContext.currentText`：

- 键盘输入 → 追加到 `currentText`
- 回车 / 点箭头 → `LockContext.tryUnlock()`
- 指纹由 `LockContext` 内部处理
- 失败 → `LockContext.showFailure` 置位，`StateMessage` 显示提示

解锁成功后 `LockContext.unlocked` 触发 `CaelestiaLockSurface` 的收起动画，
随后 `LockScreen` 关闭 session lock。

## 切回旧版

`Lock.qml` 里把 `lockSurface` 从 `CaelestiaLockSurface` 换回
`SerpantinumLockSurface` 即可，旧文件完整保留。

## 依赖

- `qt6-m3shapes-git`（AUR）—— Material 3 形状 morph
- Caelestia QML 插件（`QML2_IMPORT_PATH` 指向 `~/src/caelestia-shell/build/qml`）——
  提供 `Caelestia.Config`（`Tokens.anim.*` 与动画曲线）
