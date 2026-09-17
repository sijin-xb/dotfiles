import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.calendar

/**
 * 居中时钟的仪表盘弹窗。
 *
 * 定位对齐 caelestia 的 Dashboard：把和时间/系统状态相关的信息集中到一个从栏中央
 * 拉开的浮层里。参考 caelestia 的分页式 Dashboard，这里也做成**多页 + 左右滑动**：
 *
 *   页 0「概览」  月历 / 世界时钟 / 番茄钟 / 待办
 *   页 1「媒体」  封面 / 曲目 / 进度 / 控制 / 当前歌词
 *   页 2「系统」  CPU / 内存 / 交换 / 磁盘 / 运行时间
 *   页 3「天气」  当前天气 + 详细指标
 *
 * 顶部是**固定状态栏**：工作区 · 日期时间 · 音量/亮度/电量，切页时不变。
 *
 * 交互：左键栏中央时钟开合；点浮层外或按 Esc 关闭；
 *       左右滑动 / 滚轮 / ← → 键切页。
 *
 * 打开时把输入 mask 扩到整个窗口，垫一层透明捕获层实现「点空白关闭」。
 * 沿用 Overview 的做法，故意不用 HyprlandFocusGrab —— 它会打断 fcitx5
 * 的输入法桥接。
 */
PanelWindow {
    id: root

    // 不指定就用 Quickshell 的默认屏幕
    property var targetScreen: null
    screen: root.targetScreen

    readonly property bool opened: GlobalStates.clockDashboardOpen
    readonly property bool barAtBottom: Config.options.bar.bottom
    readonly property int cardWidth: 780
    readonly property int cardMaxHeight: 720
    // 概览页的月历 6 行固定占位较高，页高要留够，否则最后一行会被裁掉
    readonly property int pageHeight: 434
    // 同时受屏幕高度约束，避免在小屏上把底部内容裁掉
    readonly property real cardHeight: Math.min(contentColumn.implicitHeight + 32,
        Math.min(root.cardMaxHeight, root.height - Appearance.sizes.barHeight - 40))

    // 背景模糊抓帧的兜底：超过这个时间还没抓到就放弃模糊、直接显示面板，
    // 否则一旦 screencopy 不可用，整个仪表盘就打不开了
    property bool backdropGaveUp: false
    Timer {
        running: root.opened && !root.backdropGaveUp && !backdrop.ready
        interval: 300
        onTriggered: root.backdropGaveUp = true
    }

    onOpenedChanged: {
        if (root.opened) {
            root.backdropGaveUp = false;
            backdrop.refresh();
        }
    }

    // ── 状态栏用的数据 ──────────────────────────────────────────────────
    readonly property var player: MprisController.activePlayer
    readonly property var brightMonitor: Brightness.getMonitorForScreen(root.screen)
    readonly property real volumeValue: Audio.value ?? 0
    readonly property bool volumeMuted: Audio.sink?.audio?.muted ?? false
    // 亮度：取不到显示器（或值不是有限数）时给 -1，界面上显示 "--" 而不是 NaN%
    readonly property real brightnessValue: {
        const b = root.brightMonitor?.brightness;
        return (typeof b === "number" && isFinite(b)) ? b : -1;
    }
    readonly property real batteryValue: Battery.percentage ?? 0
    // 台式机没有电池：UPower 会报 0%，这种情况整行不显示
    readonly property bool hasBattery: root.batteryValue > 0 || Battery.isPluggedIn

    // 已存在的工作区号（升序），状态栏里显示成小胶囊
    readonly property var workspaceIds: {
        const ids = (Hyprland.workspaces?.values ?? []).map(w => w.id).filter(id => id > 0);
        ids.sort((a, b) => a - b);
        return ids;
    }
    readonly property int focusedWorkspaceId: Hyprland.focusedWorkspace?.id ?? -1

    // 概览页只展示真正有用的即时信息，不再放番茄钟和待办。
    readonly property var recentNotifications: Notifications.list.slice(0, 4)

    // 进度条拖动标志：拖动时置 true，SwipeView 停止滑动抢事件
    property bool progressDragging: false

    visible: root.opened
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    mask: Region {
        item: root.opened ? outsideArea : null
    }

    WlrLayershell.namespace: "quickshell:clockDashboard"
    WlrLayershell.layer: WlrLayer.Overlay
    // 需要真实键盘焦点，Esc 和左右键才收得到
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ── 小工具函数 ──────────────────────────────────────────────────────
    function pad(n) {
        return n < 10 ? "0" + n : "" + n;
    }

    function formatRate(bytesPerSecond) {
        const units = ["B/s", "KB/s", "MB/s", "GB/s"];
        let v = Math.max(0, Number(bytesPerSecond) || 0);
        let i = 0;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            i += 1;
        }
        return (i === 0 ? Math.round(v) : v.toFixed(1)) + " " + units[i];
    }

    function formatSeconds(totalSeconds) {
        const s = Math.max(0, Math.round(totalSeconds));
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        const sec = s % 60;
        return h > 0
            ? `${h}:${root.pad(m)}:${root.pad(sec)}`
            : `${m}:${root.pad(sec)}`;
    }

    Item {
        id: outsideArea
        anchors.fill: parent

        // 轻微压暗桌面，让仪表盘从复杂壁纸和终端内容里脱出来。
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colScrim
            opacity: 0.22
        }

        MouseArea {
            anchors.fill: parent
            onClicked: (event) => {
                const point = card.mapFromItem(outsideArea, event.x, event.y);
                const insideCard = point.x >= 0 && point.y >= 0
                    && point.x <= card.width && point.y <= card.height;
                if (!insideCard)
                    GlobalStates.clockDashboardOpen = false;
            }
        }

        StyledRectangularShadow {
            target: card
        }

        // 播放时从整个仪表盘卡片左侧出现的音频可视化，高度与卡片一致
        Item {
            id: leftVisualizer
            readonly property bool active: root.opened
                && (root.player?.isPlaying ?? false)
            // 贴在卡片左侧外：宽度动画期间 x 跟着走，像从卡片边滑出来
            x: card.x - width - 12
            y: card.y
            width: active ? 56 : 0
            height: card.height
            visible: active
            clip: true

            Behavior on width {
                NumberAnimation {
                    duration: 260
                    easing.type: Easing.OutCubic
                }
            }

            property var sampled: []
            readonly property int barCount: 40
            // cava 原始输出 0~1000，实际音乐通常只走到 200~500。
            // 直接 v/1000 会让柱条常年只有 20~50% 长，显得“不敏感”。
            // 用 2.5 倍增益把常用区推满，超出 1 再 clamp。
            readonly property real gain: 2.5
            // cava 是 ~60Hz 推送，重采样挂 33ms 采样属性上，避免每帧都跑 JS
            readonly property var bars: {
                const pts = sampled
                const n = barCount
                if (!pts || pts.length === 0)
                    return Array(n).fill(0)
                const out = []
                for (let i = 0; i < n; i++) {
                    const idx = Math.floor(i * pts.length / n)
                    out.push(pts[idx] ?? 0)
                }
                return out
            }

            Timer {
                interval: 33
                repeat: true
                running: leftVisualizer.visible
                onTriggered: leftVisualizer.sampled = GlobalStates.visualizerPoints
            }

            // 水平条堆叠：每条按音频强度横向伸缩，整体靠上下锚定撑满卡片高度，
            // 条与条的间距由条数均分，卡片高度变化时自动填满。
            Column {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.topMargin: 16
                anchors.bottomMargin: 16
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 0

                Repeater {
                    model: leftVisualizer.barCount

                    delegate: Item {
                        required property int index
                        readonly property real v: leftVisualizer.bars[index] ?? 0
                        width: leftVisualizer.width
                        height: (leftVisualizer.height - 32) / leftVisualizer.barCount

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: 3
                            width: Math.max(4, Math.min(1, (v * leftVisualizer.gain) / 1000) * (leftVisualizer.width - 10))
                            radius: height / 2
                            color: Appearance.colors.colPrimary
                            opacity: 0.85

                            Behavior on width {
                                NumberAnimation {
                                    duration: 90
                                    easing.type: Easing.OutQuad
                                }
                            }
                        }
                    }
                }
            }
        }

        LiquidGlass {
            id: card
            x: (parent.width - width) / 2
            y: root.barAtBottom
                ? parent.height - height - Appearance.sizes.barHeight - 12
                : Appearance.sizes.barHeight + 12

            width: root.cardWidth
            height: root.cardHeight
            // 面板本体只保留一层干净的磨砂底，避免高光带和背景内容互相抢视觉。
            radius: 16
            tint: Qt.rgba(Appearance.colors.colLayer1Base.r, Appearance.colors.colLayer1Base.g,
                Appearance.colors.colLayer1Base.b,
                1.0)
            specular: false
            edgeHighlight: true
            clip: true
            focus: true

            // ── 背景模糊：只发生在卡片自身范围内，不依赖 Hyprland 全局模糊 ──
            // 抓帧是异步的，而且必须在我们自己画出来之前完成，否则会抓到面板自己；
            // 所以卡片的 opacity 挂在 backdrop.ready 上。
            // 万一抓帧一直不来（协议不可用），由下面的 Timer 兜底放行，保证面板能用。
            GlassBackdrop {
                id: backdrop
                anchors.fill: parent
                z: -1
                screen: root.screen
                live: false
                // 仪表盘使用稳定的实体材质，避免终端文字和壁纸颜色穿透卡片。
                intensity: 0.0
                blurRadius: 64
                saturation: 0.12
                brightness: 0.02
                contrast: 0.04
            }

            // 只给面板上缘一点主题色空气感，不让壁纸颜色直接穿透内容。
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                z: 0
                opacity: 0.42
                color: "transparent"
                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: Qt.rgba(Appearance.colors.colPrimary.r,
                            Appearance.colors.colPrimary.g,
                            Appearance.colors.colPrimary.b, 0.10)
                    }
                    GradientStop {
                        position: 0.32
                        color: Qt.rgba(Appearance.colors.colPrimary.r,
                            Appearance.colors.colPrimary.g,
                            Appearance.colors.colPrimary.b, 0.02)
                    }
                    GradientStop {
                        position: 1.0
                        color: "transparent"
                    }
                }
            }

            // 抓帧没到位就先不画面板（避免自反馈）；超时则放弃模糊直接显示
            opacity: (root.opened && (backdrop.ready || root.backdropGaveUp)) ? 1 : 0
            scale: root.opened ? 1 : 0.96
            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animation.popout.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animation.popout.bezierCurve
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: Appearance.animation.popout.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animation.popout.bezierCurve
                }
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    GlobalStates.clockDashboardOpen = false;
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left) {
                    pager.decrementCurrentIndex();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right) {
                    pager.incrementCurrentIndex();
                    event.accepted = true;
                }
            }

            // 滚轮切页
            WheelHandler {
                onWheel: event => {
                    if (event.angleDelta.y < 0)
                        pager.incrementCurrentIndex();
                    else if (event.angleDelta.y > 0)
                        pager.decrementCurrentIndex();
                }
            }

            ColumnLayout {
                id: contentColumn
                z: 1
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 16
                }
                spacing: 12

                // ══ 固定状态栏 ══════════════════════════════════════════
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    // 工作区
                    RowLayout {
                        spacing: 3

                        Repeater {
                            model: root.workspaceIds.slice(0, 10)

                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool isFocused: modelData === root.focusedWorkspaceId

                                implicitWidth: Math.max(20, wsLabel.implicitWidth + 12)
                                implicitHeight: 20
                                radius: Appearance.rounding.full
                                color: isFocused
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colSurfaceContainerHigh

                                StyledText {
                                    id: wsLabel
                                    anchors.centerIn: parent
                                    text: `${modelData}`
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: isFocused ? Font.Bold : Font.Normal
                                    color: isFocused
                                        ? Appearance.colors.colOnPrimary
                                        : Appearance.colors.colOnSurfaceVariant
                                }
                            }
                        }

                        StyledText {
                            visible: root.workspaceIds.length === 0
                            text: Translation.tr("No workspace")
                            color: Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    // 日期 + 时间
                    RowLayout {
                        spacing: 8

                        ColumnLayout {
                            spacing: -2
                            Layout.alignment: Qt.AlignVCenter

                            StyledText {
                                Layout.alignment: Qt.AlignRight
                                text: Qt.locale().toString(DateTime.clock.date, "yyyy/MM/dd")
                                color: Appearance.colors.colOnSurfaceVariant
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignRight
                                text: Qt.locale().toString(DateTime.clock.date, "dddd")
                                color: Appearance.colors.colPrimary
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                            }
                        }

                        StyledText {
                            text: `${DateTime.hourStr}:${DateTime.minuteStr}`
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.huge
                            font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                            font.letterSpacing: -0.8
                        }
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 1
                        implicitHeight: 26
                        color: Appearance.colors.colOutlineVariant
                    }

                    // 音量 / 亮度 / 电量
                    ColumnLayout {
                        spacing: 3
                        Layout.alignment: Qt.AlignVCenter

                        RowLayout {
                            spacing: 5
                            MaterialSymbol {
                                text: root.volumeMuted ? "volume_off" : (root.volumeValue > 0.5 ? "volume_up" : "volume_down")
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText {
                                text: root.volumeMuted ? Translation.tr("Muted") : `${Math.round(root.volumeValue * 100)}%`
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.features: { "tnum": 1 }
                            }
                        }

                        RowLayout {
                            spacing: 5
                            MaterialSymbol {
                                text: "brightness_6"
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText {
                                text: root.brightnessValue < 0
                                    ? "--"
                                    : `${Math.round(root.brightnessValue * 100)}%`
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.features: { "tnum": 1 }
                            }
                        }

                        RowLayout {
                            visible: root.hasBattery
                            spacing: 5
                            MaterialSymbol {
                                text: Battery.isCharging ? "battery_charging_full" : "battery_full"
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText {
                                text: `${Math.round(root.batteryValue * 100)}%`
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.features: { "tnum": 1 }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Appearance.colors.colOutlineVariant
                }

                // ══ 分页区 ══════════════════════════════════════════════
                SwipeView {
                    id: pager
                    Layout.fillWidth: true
                    implicitHeight: root.pageHeight
                    clip: true
                    currentIndex: 0
                    // 进度条拖动期间禁用页面滑动，否则 SwipeView 底层的 Flickable
                    // 会在进度条 MouseArea 上抢事件，变成"拖进度条 = 翻页"
                    interactive: !root.progressDragging

                    // ── 页 0：概览 ────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 14

                        ColumnLayout {
                            // 必须显式顶对齐：默认垂直居中被撑高后，
                            // 月历会被往下推、最后一行超出页面被 SwipeView 裁掉
                            Layout.alignment: Qt.AlignTop
                            spacing: 6

                            StyledText {
                                text: Translation.tr("Calendar")
                                color: Appearance.colors.colOnSurfaceVariant
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                            }

                            CalendarWidget {
                                Layout.alignment: Qt.AlignTop | Qt.AlignHCenter
                            }
                        }

                        Rectangle {
                            Layout.fillHeight: true
                            implicitWidth: 1
                            color: Appearance.colors.colOutlineVariant
                        }

                        ColumnLayout {
                            Layout.alignment: Qt.AlignTop
                            Layout.fillWidth: true
                            spacing: 12

                            StyledText {
                                text: Translation.tr("World Clock")
                                color: Appearance.colors.colOnSurfaceVariant
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 16

                                Repeater {
                                    model: WorldClock.entries.slice(0, 4)
                                    delegate: Rectangle {
                                        id: worldClockCard
                                        required property var modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 0
                                        // 72 装不下 icon + name + time 三行（加上内边距必然溢出），
                                        // 抬到 84 并 clip 兜底，即使字体配置变化也不会画到卡片外。
                                        Layout.preferredHeight: 84
                                        radius: Appearance.rounding.verysmall
                                        color: Appearance.colors.colSurfaceContainerHigh
                                        border.width: 1
                                        border.color: Appearance.colors.colOutlineVariant
                                        clip: true
                                        // 错峰进入：每张卡延迟 index * 60ms 淡入 + 上移，
                                        // 曲线走 caelestia 的 elementMoveEnter（emphasizedDecel）。
                                        opacity: 0
                                        transform: Translate {
                                            id: worldClockTranslate
                                            y: 14
                                            // Behavior 必须挂在 Translate 自己的 y 上：
                                            // Rectangle 的 y 由 Layout 控制、这里不变，挂父级不生效。
                                            Behavior on y {
                                                NumberAnimation {
                                                    duration: Appearance.animation.elementMove.duration
                                                    easing.type: Appearance.animation.elementMove.type
                                                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                                                }
                                            }
                                        }
                                        Timer {
                                            interval: worldClockCard.index * 60
                                            running: true
                                            onTriggered: {
                                                worldClockCard.opacity = 1
                                                worldClockTranslate.y = 0
                                            }
                                        }
                                        Behavior on opacity {
                                            NumberAnimation {
                                                duration: Appearance.animation.elementMoveEnter.duration
                                                easing.type: Appearance.animation.elementMoveEnter.type
                                                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                                            }
                                        }

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            spacing: 3
                                            MaterialSymbol {
                                                text: modelData.isDay ? "light_mode" : "dark_mode"
                                                iconSize: 20
                                                color: Appearance.colors.colPrimary
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: modelData.name
                                                elide: Text.ElideRight
                                                color: Appearance.colors.colOnSurfaceVariant
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: modelData.time
                                                elide: Text.ElideRight
                                                color: Appearance.colors.colOnLayer1
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                font.features: { "tnum": 1 }
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: Appearance.colors.colOutlineVariant
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                StyledText {
                                    text: Translation.tr("Recent notifications")
                                    color: Appearance.colors.colOnSurfaceVariant
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                }
                                Item { Layout.fillWidth: true }
                                StyledText {
                                    text: `${Notifications.unread}`
                                    color: Appearance.colors.colPrimary
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.features: { "tnum": 1 }
                                }
                                RippleButton {
                                    visible: root.recentNotifications.length > 0
                                    implicitWidth: 22
                                    implicitHeight: 22
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: "transparent"
                                    colBackgroundHover: Appearance.colors.colLayer2Hover
                                    onClicked: Notifications.discardAllNotifications()
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "delete_sweep"
                                        iconSize: 14
                                        color: Appearance.colors.colOnSurfaceVariant
                                    }
                                }
                            }

                            Repeater {
                                model: root.recentNotifications
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 36
                                    radius: Appearance.rounding.unsharpenmore
                                    color: Appearance.colors.colSurfaceContainerHigh
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 8
                                        // 复用全局的 NotificationAppIcon：按 image > appIcon > material 猜图标
                                        // 依次降级，跟弹出通知 / 动态岛保持一致的显示逻辑
                                        NotificationAppIcon {
                                            Layout.alignment: Qt.AlignVCenter
                                            implicitSize: 26
                                            image: modelData.image ?? ""
                                            appIcon: modelData.appIcon ?? ""
                                            summary: modelData.summary ?? ""
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: modelData.summary || Translation.tr("Notification")
                                                elide: Text.ElideRight
                                                color: Appearance.colors.colOnLayer1
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: modelData.appName || modelData.body
                                                elide: Text.ElideRight
                                                color: Appearance.colors.colOnSurfaceVariant
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                            }
                                        }
                                        RippleButton {
                                            implicitWidth: 20
                                            implicitHeight: 20
                                            buttonRadius: Appearance.rounding.full
                                            colBackground: "transparent"
                                            colBackgroundHover: Appearance.colors.colLayer2Hover
                                            onClicked: Notifications.discardNotification(modelData.notificationId)
                                            contentItem: MaterialSymbol {
                                                anchors.centerIn: parent
                                                text: "close"
                                                iconSize: 12
                                                color: Appearance.colors.colOnSurfaceVariant
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 64
                                visible: root.recentNotifications.length === 0
                                radius: Appearance.rounding.unsharpenmore
                                color: Appearance.colors.colSurfaceContainerHigh
                                StyledText {
                                    anchors.centerIn: parent
                                    text: Translation.tr("No recent notifications")
                                    color: Appearance.colors.colOnSurfaceVariant
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                            }
                        }
                    }

                    // ── 页 1：媒体 ────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 16

                        // 封面（圆形）：Rectangle 的 clip 不裁圆角，所以封面图必须走 OpacityMask
                        Rectangle {
                            id: coverBox
                            Layout.alignment: Qt.AlignTop
                            implicitWidth: 176
                            implicitHeight: 176
                            radius: width / 2
                            color: Appearance.colors.colSurfaceContainerHigh
                            // 进入时轻微放大 + 淡入
                            opacity: 0
                            scale: 0.85
                            Component.onCompleted: coverEnter.restart()
                            ParallelAnimation {
                                id: coverEnter
                                NumberAnimation {
                                    target: coverBox
                                    property: "opacity"
                                    to: 1
                                    duration: Appearance.animation.elementMoveEnter.duration
                                    easing.type: Appearance.animation.elementMoveEnter.type
                                    easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                                }
                                NumberAnimation {
                                    target: coverBox
                                    property: "scale"
                                    to: 1
                                    duration: Appearance.animation.elementMove.duration
                                    easing.type: Appearance.animation.elementMove.type
                                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                                }
                            }

                            Image {
                                id: coverImage
                                anchors.fill: parent
                                source: root.player?.trackArtUrl ?? ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: status === Image.Ready
                                layer.enabled: true
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: coverImage.width
                                        height: coverImage.height
                                        radius: width / 2
                                    }
                                }
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: coverImage.status !== Image.Ready
                                text: "music_note"
                                iconSize: 56
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 8

                            StyledText {
                                Layout.fillWidth: true
                                text: root.player?.trackTitle ?? Translation.tr("No media")
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.large
                                font.weight: Font.DemiBold
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.player?.trackArtist ?? ""
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnSurfaceVariant
                                font.pixelSize: Appearance.font.pixelSize.small
                            }

                            // 进度
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                visible: (root.player?.length ?? 0) > 0

                                Rectangle {
                                    id: progressTrack
                                    Layout.fillWidth: true
                                    implicitHeight: 4
                                    radius: height / 2
                                    color: Appearance.colors.colSurfaceContainerHighest

                                    // 拖动时的本地预览位置（秒）；-1 表示没有拖动
                                    property real dragPosition: -1
                                    readonly property real totalLength: Math.max(1, root.player?.length ?? 1)
                                    readonly property real displayPosition: dragPosition >= 0
                                        ? dragPosition
                                        : (root.player?.position ?? 0)
                                    readonly property real progress: Math.max(0, Math.min(1,
                                        displayPosition / totalLength))

                                    Rectangle {
                                        width: parent.width * parent.progress
                                        height: parent.height
                                        radius: parent.radius
                                        color: Appearance.colors.colPrimary
                                    }

                                    // 进度圆点
                                    Rectangle {
                                        width: 10
                                        height: 10
                                        radius: 5
                                        color: Appearance.colors.colPrimary
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: parent.width * parent.progress - width / 2
                                    }

                                    Timer {
                                        id: seekClearTimer
                                        interval: 400
                                        onTriggered: progressTrack.dragPosition = -1
                                    }

                                    MouseArea {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width
                                        height: 20
                                        enabled: root.player !== null
                                        cursorShape: Qt.PointingHandCursor
                                        // 阻止父级 Flickable（SwipeView 底层）在按下时偷走事件，
                                        // 否则一拖就变成翻页而不是拖进度条
                                        preventStealing: true

                                        function posToSeconds(mx) {
                                            const ratio = Math.max(0, Math.min(1, mx / width))
                                            return ratio * progressTrack.totalLength
                                        }

                                        onPressed: (mouse) => {
                                            seekClearTimer.stop()
                                            root.progressDragging = true
                                            progressTrack.dragPosition = posToSeconds(mouse.x)
                                        }
                                        onPositionChanged: (mouse) => {
                                            if (pressed)
                                                progressTrack.dragPosition = posToSeconds(mouse.x)
                                        }
                                        onReleased: (mouse) => {
                                            const target = posToSeconds(mouse.x)
                                            const current = root.player?.position ?? 0
                                            if (root.player)
                                                root.player.seek(target - current)
                                            // 保住预览，等 D-Bus position 追上再放开，避免视觉回跳
                                            progressTrack.dragPosition = target
                                            seekClearTimer.restart()
                                            root.progressDragging = false
                                        }
                                        onCanceled: {
                                            progressTrack.dragPosition = -1
                                            root.progressDragging = false
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true

                                    StyledText {
                                        text: root.formatSeconds(root.player?.position ?? 0)
                                        color: Appearance.colors.colOnSurfaceVariant
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.features: { "tnum": 1 }
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                    }

                                    StyledText {
                                        text: root.formatSeconds(root.player?.length ?? 0)
                                        color: Appearance.colors.colOnSurfaceVariant
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.features: { "tnum": 1 }
                                    }
                                }
                            }

                            // 控制
                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 8

                                RippleButton {
                                    implicitWidth: 36
                                    implicitHeight: 36
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: Appearance.colors.colSurfaceContainerHigh
                                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
                                    enabled: root.player !== null
                                    onClicked: root.player?.previous()
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "skip_previous"
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: Appearance.colors.colOnLayer1
                                    }
                                }

                                RippleButton {
                                    implicitWidth: 44
                                    implicitHeight: 44
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: Appearance.colors.colPrimary
                                    colBackgroundHover: Appearance.colors.colPrimaryHover
                                    enabled: root.player !== null
                                    onClicked: root.player?.togglePlaying()
                                    contentItem: MaterialSymbol {
                                        // fill + 双向对齐居中：Text 的隐式行高（含 descent）
                                        // 会把字形整体往下压，只 anchors.centerIn 会看起来偏
                                        anchors.fill: parent
                                        text: (root.player?.isPlaying ?? false) ? "pause" : "play_arrow"
                                        iconSize: Appearance.font.pixelSize.huge
                                        color: Appearance.colors.colOnPrimary
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }

                                RippleButton {
                                    implicitWidth: 36
                                    implicitHeight: 36
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: Appearance.colors.colSurfaceContainerHigh
                                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
                                    enabled: root.player !== null
                                    onClicked: root.player?.next()
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "skip_next"
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: Appearance.colors.colOnLayer1
                                    }
                                }
                            }

                            // 多行歌词窗口（当前行居中，上下各两行）
                            // 视觉层级：
                            //   当前行：large + Bold + primary，最亮最重
                            //   相邻行：small + onSurface，opacity 随距离线性衰减
                            //   翻译行：small / smallest，secondary 色，跟随主行权重
                            ColumnLayout {
                                id: lyricsColumn
                                Layout.fillWidth: true
                                Layout.topMargin: 12
                                spacing: 14
                                visible: LyricsService.hasLyrics

                                readonly property int beforeLines: 2
                                readonly property int afterLines: 2
                                readonly property int windowSize: beforeLines + 1 + afterLines
                                readonly property int activeLine: LyricsService.currentLineIndex
                                readonly property var lineData: LyricsService.lyricLines

                                function lineAt(i) {
                                    const idx = activeLine - beforeLines + i
                                    if (idx < 0 || idx >= lineData.length)
                                        return null
                                    return lineData[idx]
                                }

                                Repeater {
                                    model: lyricsColumn.windowSize

                                    delegate: ColumnLayout {
                                        required property int index
                                        readonly property var line: lyricsColumn.lineAt(index)
                                        readonly property bool isActive: index === lyricsColumn.beforeLines
                                        readonly property int distance: Math.abs(index - lyricsColumn.beforeLines)

                                        Layout.fillWidth: true
                                        spacing: 3
                                        visible: line !== null

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: line?.text ?? ""
                                            horizontalAlignment: Text.AlignHCenter
                                            wrapMode: Text.WordWrap
                                            color: isActive
                                                ? Appearance.colors.colPrimary
                                                : Appearance.colors.colOnSurface
                                            opacity: isActive ? 1.0 : Math.max(0.18, 0.62 - distance * 0.22)
                                            font.pixelSize: isActive
                                                ? Appearance.font.pixelSize.large
                                                : Appearance.font.pixelSize.small
                                            font.weight: isActive ? Font.Bold : Font.Normal

                                            Behavior on opacity {
                                                NumberAnimation {
                                                    duration: 220
                                                    easing.type: Easing.OutCubic
                                                }
                                            }
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            visible: (line?.trans ?? "").length > 0
                                            text: line?.trans ?? ""
                                            horizontalAlignment: Text.AlignHCenter
                                            wrapMode: Text.WordWrap
                                            color: Appearance.colors.colSecondary
                                            opacity: isActive ? 0.9 : Math.max(0.15, 0.45 - distance * 0.15)
                                            font.pixelSize: isActive
                                                ? Appearance.font.pixelSize.small
                                                : Appearance.font.pixelSize.smallest
                                        }
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: root.player === null
                                text: Translation.tr("Nothing is playing")
                                horizontalAlignment: Text.AlignHCenter
                                color: Appearance.colors.colOnSurfaceVariant
                                font.pixelSize: Appearance.font.pixelSize.small
                            }

                            Item {
                                Layout.fillHeight: true
                            }
                        }
                    }

                    // ── 页 2：系统 ────────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10

                        // 资源条
                        Repeater {
                            model: [
                                { icon: "planner_review", label: Translation.tr("CPU"),  value: ResourceUsage.cpuUsage },
                                { icon: "memory",         label: Translation.tr("RAM"),  value: ResourceUsage.memoryUsedPercentage },
                                { icon: "swap_horiz",     label: Translation.tr("Swap"), value: ResourceUsage.swapUsedPercentage },
                                { icon: "hard_drive",     label: Translation.tr("Disk"), value: ResourceUsage.diskUsedPercentage }
                            ]

                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 3

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    MaterialSymbol {
                                        text: modelData.icon
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnSurfaceVariant
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.label
                                        color: Appearance.colors.colOnLayer1
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                    }

                                    StyledText {
                                        text: `${Math.round((modelData.value ?? 0) * 100)}%`
                                        color: Appearance.colors.colPrimary
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.features: { "tnum": 1 }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 6
                                    radius: height / 2
                                    color: Appearance.colors.colSurfaceContainerHighest

                                    Rectangle {
                                        width: parent.width * Math.max(0, Math.min(1, modelData.value ?? 0))
                                        height: parent.height
                                        radius: parent.radius
                                        color: (modelData.value ?? 0) > 0.9
                                            ? Appearance.colors.colError
                                            : Appearance.colors.colPrimary
                                        Behavior on width {
                                            NumberAnimation {
                                                duration: Appearance.animation.elementMove.duration
                                                easing.type: Appearance.animation.elementMove.type
                                                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: Appearance.colors.colOutlineVariant
                        }

                        // 主机信息
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            MaterialSymbol {
                                text: "person"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: SystemInfo.username
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }

                            MaterialSymbol {
                                text: "devices"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: SystemInfo.distroName
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            MaterialSymbol {
                                text: "timelapse"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("System Uptime")
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                            StyledText {
                                text: DateTime.uptime
                                color: Appearance.colors.colPrimary
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: Appearance.colors.colOutlineVariant
                        }

                        // ── 进程列表：搜索 + 排序 + 滚动 + kill ──────────
                        ColumnLayout {
                            id: processSection
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 6

                            // 只在仪表盘打开且停留在系统页时刷新，避免后台空转
                            readonly property bool active: root.opened && pager.currentIndex === 2
                            onActiveChanged: {
                                ProcessList.autoRefresh = active
                                if (active)
                                    ProcessList.requestRefresh()
                            }
                            property string query: ""
                            // 把函数结果缓存成属性：Repeater.model 每帧只读这一处
                            readonly property var visibleProcesses: ProcessList.filtered(query)

                            // 标题行 + 排序 + 刷新
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                StyledText {
                                    text: Translation.tr("Processes")
                                    color: Appearance.colors.colOnSurfaceVariant
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                }
                                StyledText {
                                    text: `${ProcessList.list.length}`
                                    color: Appearance.colors.colPrimary
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.features: { "tnum": 1 }
                                }

                                Item { Layout.fillWidth: true }

                                // CPU / 内存 / 名称 排序切换
                                Repeater {
                                    model: [
                                        { key: "cpu",  label: "CPU" },
                                        { key: "mem",  label: "MEM" },
                                        { key: "name", label: Translation.tr("Name") }
                                    ]
                                    delegate: RippleButton {
                                        required property var modelData
                                        readonly property bool isActive: ProcessList.sortKey === modelData.key
                                        implicitWidth: sortLabel.implicitWidth + 14
                                        implicitHeight: 22
                                        buttonRadius: Appearance.rounding.full
                                        colBackground: isActive
                                            ? Appearance.colors.colPrimaryContainer
                                            : "transparent"
                                        colBackgroundHover: isActive
                                            ? Appearance.colors.colPrimaryContainerHover
                                            : Appearance.colors.colLayer2Hover
                                        onClicked: ProcessList.setSortKey(modelData.key)
                                        contentItem: StyledText {
                                            id: sortLabel
                                            anchors.centerIn: parent
                                            text: modelData.label
                                            color: isActive
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colOnSurfaceVariant
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: isActive ? Font.DemiBold : Font.Normal
                                        }
                                    }
                                }

                                RippleButton {
                                    implicitWidth: 22
                                    implicitHeight: 22
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: "transparent"
                                    colBackgroundHover: Appearance.colors.colLayer2Hover
                                    onClicked: ProcessList.requestRefresh()
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "refresh"
                                        iconSize: 14
                                        color: Appearance.colors.colOnSurfaceVariant
                                    }
                                }
                            }

                            // 搜索框
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 30
                                radius: Appearance.rounding.full
                                color: Appearance.colors.colSurfaceContainerHigh
                                border.width: procSearch.activeFocus ? 2 : 1
                                border.color: procSearch.activeFocus
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colLayer0Border

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 6
                                    spacing: 6

                                    MaterialSymbol {
                                        text: "search"
                                        iconSize: 14
                                        color: Appearance.colors.colOnSurfaceVariant
                                    }
                                    TextField {
                                        id: procSearch
                                        Layout.fillWidth: true
                                        background: null
                                        text: processSection.query
                                        placeholderText: Translation.tr("Filter processes…")
                                        placeholderTextColor: Appearance.colors.colOnSurfaceVariant
                                        color: Appearance.colors.colOnLayer1
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        selectByMouse: true
                                        onTextChanged: processSection.query = text
                                    }
                                    RippleButton {
                                        visible: procSearch.text.length > 0
                                        implicitWidth: 18
                                        implicitHeight: 18
                                        buttonRadius: Appearance.rounding.full
                                        colBackground: "transparent"
                                        colBackgroundHover: Appearance.colors.colLayer2Hover
                                        onClicked: {
                                            procSearch.text = ""
                                            processSection.query = ""
                                        }
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "close"
                                            iconSize: 12
                                            color: Appearance.colors.colOnSurfaceVariant
                                        }
                                    }
                                }
                            }

                            // 进程列表（可滚动）
                            // 用 ListView + reuseItems 而不是 Repeater + Flickable：
                            // Repeater 每次模型变化会销毁重建全部 delegate（200 行），
                            // 后台 2.5s 刷一次、搜索每敲一字都重建 → 卡顿。
                            // ListView 复用 delegate item，只更新可见的 ~15 行。
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                ListView {
                                    id: procListView
                                    anchors.fill: parent
                                    clip: true
                                    spacing: 2
                                    model: processSection.visibleProcesses
                                    reuseItems: true
                                    // 上下各多缓存一屏，滚动时不出白
                                    cacheBuffer: 400
                                    boundsBehavior: Flickable.StopAtBounds
                                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                    delegate: Rectangle {
                                        id: procRow
                                        required property var modelData
                                        width: procListView.width
                                        height: 30
                                        radius: Appearance.rounding.unsharpenmore
                                        color: procRowHover.containsMouse
                                            ? Appearance.colors.colSurfaceContainerHighest
                                            : "transparent"

                                        MouseArea {
                                            id: procRowHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            // 只跟踪 hover，不吃点击事件，
                                            // 让后面的 kill 按钮能正常拿到点击
                                            acceptedButtons: Qt.NoButton
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 4
                                            spacing: 8

                                            StyledText {
                                                Layout.preferredWidth: 52
                                                text: `${modelData.pid}`
                                                elide: Text.ElideRight
                                                color: Appearance.colors.colOnSurfaceVariant
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                font.features: { "tnum": 1 }
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: modelData.name
                                                elide: Text.ElideRight
                                                color: Appearance.colors.colOnLayer1
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                            }
                                            StyledText {
                                                Layout.preferredWidth: 46
                                                horizontalAlignment: Text.AlignRight
                                                text: `${modelData.cpu.toFixed(1)}%`
                                                color: modelData.cpu > 20
                                                    ? Appearance.colors.colError
                                                    : Appearance.colors.colPrimary
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                font.features: { "tnum": 1 }
                                            }
                                            StyledText {
                                                Layout.preferredWidth: 46
                                                horizontalAlignment: Text.AlignRight
                                                text: `${modelData.mem.toFixed(1)}%`
                                                color: Appearance.colors.colOnSurfaceVariant
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                font.features: { "tnum": 1 }
                                            }
                                            RippleButton {
                                                visible: procRowHover.containsMouse
                                                implicitWidth: 22
                                                implicitHeight: 22
                                                buttonRadius: Appearance.rounding.full
                                                colBackground: "transparent"
                                                colBackgroundHover: Appearance.colors.colErrorContainer
                                                onClicked: ProcessList.killProcess(modelData.pid, "TERM")
                                                contentItem: MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    text: "close"
                                                    iconSize: 14
                                                    color: Appearance.colors.colError
                                                }
                                            }
                                        }
                                    }
                                }

                                // 空状态覆盖层（独立于 ListView，不参与 delegate 池）
                                Rectangle {
                                    anchors.fill: parent
                                    visible: processSection.visibleProcesses.length === 0
                                    radius: Appearance.rounding.unsharpenmore
                                    color: Appearance.colors.colSurfaceContainerHigh
                                    StyledText {
                                        anchors.centerIn: parent
                                        text: {
                                            if (!ProcessList.ready)
                                                return Translation.tr("Loading…")
                                            if (processSection.query.length > 0)
                                                return Translation.tr("No matching process")
                                            return Translation.tr("No process")
                                        }
                                        color: Appearance.colors.colOnSurfaceVariant
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                    }
                                }
                            }
                        }
                    }

                    // ── 页 3：天气 ────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 16

                        ColumnLayout {
                            Layout.alignment: Qt.AlignTop
                            // 卡住左列最大宽度，超大字号温度不会把分隔线挤到页面外
                            Layout.maximumWidth: parent.width * 0.5
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                spacing: 10

                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignTop
                                    text: Icons.getWeatherIcon(Weather.data.wCode) ?? "cloud"
                                    iconSize: 48
                                    color: Appearance.colors.colPrimary
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignTop
                                    spacing: -2

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Weather.data.temp ?? "--"
                                        elide: Text.ElideRight
                                        color: Appearance.colors.colOnLayer1
                                        font.pixelSize: Appearance.font.pixelSize.hugeass
                                        font.weight: Font.Bold
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Weather.data.description ?? ""
                                        elide: Text.ElideRight
                                        color: Appearance.colors.colOnSurfaceVariant
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Weather.data.city ?? ""
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnSurfaceVariant
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Feels like") + " " + (Weather.data.tempFeelsLike ?? "--")
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnSurfaceVariant
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }

                            RippleButton {
                                implicitWidth: 96
                                implicitHeight: 30
                                buttonRadius: Appearance.rounding.full
                                colBackground: Appearance.colors.colPrimaryContainer
                                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                                onClicked: Weather.getData()
                                contentItem: RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    MaterialSymbol {
                                        text: "refresh"
                                        iconSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnPrimaryContainer
                                    }
                                    StyledText {
                                        text: Translation.tr("Refresh")
                                        color: Appearance.colors.colOnPrimaryContainer
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillHeight: true
                            implicitWidth: 1
                            color: Appearance.colors.colOutlineVariant
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 6

                            Repeater {
                                model: [
                                    { icon: "water_drop",  label: Translation.tr("Humidity"),   value: Weather.data.humidity },
                                    { icon: "air",         label: Translation.tr("Wind"),       value: Weather.data.wind },
                                    { icon: "umbrella",    label: Translation.tr("Precipitation"), value: Weather.data.precip },
                                    { icon: "visibility",  label: Translation.tr("Visibility"), value: Weather.data.visib },
                                    { icon: "speed",       label: Translation.tr("Pressure"),   value: Weather.data.press },
                                    { icon: "cloud",       label: Translation.tr("Clouds"),     value: Weather.data.cr }
                                ]

                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 8

                                    MaterialSymbol {
                                        text: modelData.icon
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnSurfaceVariant
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.label
                                        color: Appearance.colors.colOnLayer1
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                    }

                                    StyledText {
                                        text: `${modelData.value ?? "--"}`
                                        color: Appearance.colors.colPrimary
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.features: { "tnum": 1 }
                                    }
                                }
                            }

                            Item {
                                Layout.fillHeight: true
                            }
                        }
                    }
                    // ── 页 4：GitHub ──────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10

                        // 用户名输入 + 操作
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 34
                                radius: Appearance.rounding.full
                                color: Appearance.colors.colSurfaceContainerHigh
                                border.width: ghInput.activeFocus ? 2 : 1
                                border.color: ghInput.activeFocus
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colLayer0Border

                                TextField {
                                    id: ghInput
                                    anchors {
                                        fill: parent
                                        leftMargin: 12
                                        rightMargin: 12
                                    }
                                    background: null
                                    text: Config.options.github.username
                                    placeholderText: Translation.tr("GitHub username")
                                    placeholderTextColor: Appearance.colors.colOnSurfaceVariant
                                    color: Appearance.colors.colOnLayer1
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    selectByMouse: true
                                    // 回车或失焦时提交（避免每敲一个字母就发一次请求）
                                    onEditingFinished: {
                                        GitHub.setUsername(ghInput.text);
                                        GitHub.fetch();
                                    }
                                }
                            }

                            RippleButtonWithIcon {
                                materialIcon: "refresh"
                                mainText: Translation.tr("Reload")
                                enabled: GitHub.username.length > 0 && !GitHub.loading
                                onClicked: GitHub.fetch()
                            }

                            RippleButtonWithIcon {
                                materialIcon: "open_in_new"
                                mainText: Translation.tr("Open profile")
                                enabled: GitHub.username.length > 0
                                onClicked: GitHub.openProfile()
                            }
                        }

                        // 状态行
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            MaterialLoadingIndicator {
                                visible: GitHub.loading
                                loading: GitHub.loading
                                implicitSize: 18
                                colBg: Appearance.colors.colPrimaryContainer
                                colShape: Appearance.colors.colOnPrimaryContainer
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: {
                                    if (GitHub.loading)
                                        return Translation.tr("Loading…");
                                    if (GitHub.errorText.length > 0)
                                        return GitHub.errorText;
                                    if (GitHub.username.length === 0)
                                        return Translation.tr("Type a GitHub username and press Enter.");
                                    return `${GitHub.visibleRepos.length} / ${GitHub.repos.length} ` + Translation.tr("repositories");
                                }
                                color: GitHub.errorText.length > 0
                                    ? Appearance.colors.colError
                                    : Appearance.colors.colOnSurfaceVariant
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                wrapMode: Text.WordWrap
                            }

                            StyledText {
                                visible: GitHub.dirty
                                text: Translation.tr("(reload to refresh)")
                                color: Appearance.colors.colOnSurfaceVariant
                                font.pixelSize: Appearance.font.pixelSize.smallest
                            }
                        }

                        // 仓库网格（页内滚动）
                        Flickable {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentHeight: ghGrid.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: ghGrid
                                width: parent.width
                                spacing: 10

                                Repeater {
                                    model: Math.ceil(GitHub.visibleRepos.length / 2)

                                    delegate: RowLayout {
                                        required property int index
                                        Layout.fillWidth: true
                                        spacing: 10

                                        Repeater {
                                            model: {
                                                const base = index * 2;
                                                const list = GitHub.visibleRepos;
                                                return [list[base] ?? null, list[base + 1] ?? null];
                                            }

                                            delegate: Item {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 0
                                                implicitHeight: modelData ? 118 : 0
                                                visible: modelData !== null

                                                GitHubRepoCard {
                                                    anchors.fill: parent
                                                    repo: parent.modelData ?? ({})
                                                    onActivated: url => GitHub.openRepo(url)
                                                }
                                            }
                                        }
                                    }
                                }

                                // 空状态
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 96
                                    visible: !GitHub.loading && GitHub.visibleRepos.length === 0
                                    radius: Appearance.rounding.normal
                                    color: Appearance.colors.colSurfaceContainerHigh

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 4

                                        MaterialSymbol {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "code"
                                            iconSize: 28
                                            color: Appearance.colors.colOnSurfaceVariant
                                        }
                                        StyledText {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: GitHub.username.length === 0
                                                ? Translation.tr("No username set")
                                                : Translation.tr("Nothing to show")
                                            color: Appearance.colors.colOnSurfaceVariant
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ══ 页指示 + 底部 ═══════════════════════════════════════
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [
                            { icon: "dashboard", label: Translation.tr("Overview") },
                            { icon: "music_note", label: Translation.tr("Media") },
                            { icon: "monitor_heart", label: Translation.tr("System") },
                            { icon: "cloud", label: Translation.tr("Weather") },
                            { icon: "code", label: Translation.tr("GitHub") }
                        ]

                        delegate: RippleButton {
                            required property var modelData
                            required property int index
                            readonly property bool isCurrent: pager.currentIndex === index

                            implicitWidth: pageTabRow.implicitWidth + 20
                            implicitHeight: 32
                            // 当前页切换时按钮轻微放大弹一下，"从别处弹到手上"的手感
                            scale: isCurrent ? 1.08 : 1.0
                            Behavior on scale {
                                NumberAnimation {
                                    duration: Appearance.animation.clickBounce.duration
                                    easing.type: Appearance.animation.clickBounce.type
                                    easing.bezierCurve: Appearance.animation.clickBounce.bezierCurve
                                }
                            }
                            buttonRadius: Appearance.rounding.full
                            colBackground: isCurrent
                                ? Appearance.colors.colPrimaryContainer
                                : "transparent"
                            colBackgroundHover: isCurrent
                                ? Appearance.colors.colPrimaryContainerHover
                                : Appearance.colors.colLayer2Hover
                            onClicked: pager.currentIndex = index

                            contentItem: RowLayout {
                                id: pageTabRow
                                anchors.centerIn: parent
                                spacing: 4
                                MaterialSymbol {
                                    text: modelData.icon
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: isCurrent
                                        ? Appearance.colors.colOnPrimaryContainer
                                        : Appearance.colors.colOnSurfaceVariant
                                }
                                StyledText {
                                    text: modelData.label
                                    color: isCurrent
                                        ? Appearance.colors.colOnPrimaryContainer
                                        : Appearance.colors.colOnSurfaceVariant
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: isCurrent ? Font.DemiBold : Font.Normal
                                }
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    StyledText {
                        text: Translation.tr("Drag, scroll or ← → to switch pages")
                        color: Appearance.colors.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        opacity: 0.7
                    }

                    RippleButton {
                        implicitWidth: 30
                        implicitHeight: 30
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: {
                            GlobalStates.clockDashboardOpen = false;
                            GlobalStates.sidebarRightOpen = true;
                        }
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "notifications"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnLayer1
                        }
                    }

                    RippleButton {
                        implicitWidth: 30
                        implicitHeight: 30
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: {
                            GlobalStates.clockDashboardOpen = false;
                            GlobalStates.wallpaperSelectorOpen = true;
                        }
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "wallpaper"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnLayer1
                        }
                    }

                    RippleButton {
                        implicitWidth: 30
                        implicitHeight: 30
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: GlobalStates.clockDashboardOpen = false
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "clockdashboard"

        function toggle(): void {
            GlobalStates.clockDashboardOpen = !GlobalStates.clockDashboardOpen;
        }

        function show(): void {
            GlobalStates.clockDashboardOpen = true;
        }

        function hide(): void {
            GlobalStates.clockDashboardOpen = false;
        }

        function page(index: int): void {
            pager.currentIndex = index;
        }

        function nextPage(): void {
            pager.incrementCurrentIndex();
        }

        function previousPage(): void {
            pager.decrementCurrentIndex();
        }
    }
}
