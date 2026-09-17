import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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

    // 待办：Todo 服务里还没做完的
    readonly property var pendingTodos: Todo.list.filter(t => !t.done)

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

        MouseArea {
            anchors.fill: parent
            onClicked: GlobalStates.clockDashboardOpen = false
        }

        StyledRectangularShadow {
            target: card
        }

        LiquidGlass {
            id: card
            x: (parent.width - width) / 2
            y: root.barAtBottom
                ? parent.height - height - Appearance.sizes.barHeight - 12
                : Appearance.sizes.barHeight + 12

            width: root.cardWidth
            height: root.cardHeight
            radius: Appearance.rounding.large
            // 液态玻璃底板：半透明基底（不低于 minAlpha）+ 透光 + 折射高光 + 双层描边
            // 背景模糊由 Hyprland 的 `layerrule = blur, quickshell:clockDashboard` 提供
            tint: Qt.rgba(Appearance.colors.colLayer1Base.r, Appearance.colors.colLayer1Base.g,
                Appearance.colors.colLayer1Base.b, 0.78)
            clip: true
            focus: true

            // 展开动画
            opacity: root.opened ? 1 : 0
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

                    // ── 页 0：概览 ────────────────────────────────────────
                    RowLayout {
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
                            Layout.preferredWidth: 210
                            spacing: 12

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                StyledText {
                                    text: Translation.tr("World Clock")
                                    color: Appearance.colors.colOnSurfaceVariant
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                }

                                Repeater {
                                    model: WorldClock.entries.slice(0, 4)

                                    delegate: RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 6

                                        MaterialSymbol {
                                            text: modelData.isDay ? "light_mode" : "dark_mode"
                                            iconSize: Appearance.font.pixelSize.small
                                            color: Appearance.colors.colOnSurfaceVariant
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.name
                                            elide: Text.ElideRight
                                            color: Appearance.colors.colOnLayer1
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                        }

                                        StyledText {
                                            text: modelData.time
                                            color: Appearance.colors.colPrimary
                                            font.pixelSize: Appearance.font.pixelSize.smaller
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

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                StyledText {
                                    text: Translation.tr("Pomodoro")
                                    color: Appearance.colors.colOnSurfaceVariant
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    MaterialSymbol {
                                        text: TimerService.pomodoroRunning ? "pause_circle" : "play_circle"
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: TimerService.pomodoroRunning
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colOnSurfaceVariant
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: TimerService.formatSeconds(
                                            TimerService.pomodoroRunning || TimerService.pomodoroSecondsLeft < TimerService.pomodoroLapDuration
                                                ? TimerService.pomodoroSecondsLeft
                                                : TimerService.pomodoroLapDuration)
                                        color: Appearance.colors.colOnLayer1
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.features: { "tnum": 1 }
                                    }

                                    StyledText {
                                        text: TimerService.pomodoroLongBreak
                                            ? Translation.tr("Long break")
                                            : TimerService.pomodoroBreak
                                                ? Translation.tr("Break")
                                                : Translation.tr("Focus")
                                        color: Appearance.colors.colOnSurfaceVariant
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                    }
                                }

                                RowLayout {
                                    spacing: 4

                                    RippleButton {
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        buttonRadius: Appearance.rounding.full
                                        colBackground: Appearance.colors.colPrimaryContainer
                                        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                                        onClicked: TimerService.togglePomodoro()
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: TimerService.pomodoroRunning ? "pause" : "play_arrow"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: Appearance.colors.colOnPrimaryContainer
                                        }
                                    }

                                    RippleButton {
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        buttonRadius: Appearance.rounding.full
                                        colBackground: Appearance.colors.colSecondaryContainer
                                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                                        onClicked: TimerService.resetPomodoro()
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "restart_alt"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: Appearance.colors.colOnSecondaryContainer
                                        }
                                    }

                                    Item {
                                        Layout.fillWidth: true
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
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredWidth: 220
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true

                                StyledText {
                                    text: Translation.tr("To-do")
                                    color: Appearance.colors.colOnSurfaceVariant
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                StyledText {
                                    text: `${root.pendingTodos.length}`
                                    color: Appearance.colors.colPrimary
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                            }

                            Repeater {
                                model: root.pendingTodos.slice(0, 6)

                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 30
                                    radius: Appearance.rounding.unsharpenmore
                                    color: Appearance.colors.colSurfaceContainerHigh

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 6

                                        MaterialSymbol {
                                            text: "check_box_outline_blank"
                                            iconSize: Appearance.font.pixelSize.small
                                            color: Appearance.colors.colOnSurfaceVariant
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.content
                                            elide: Text.ElideRight
                                            color: Appearance.colors.colOnLayer1
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 64
                                visible: root.pendingTodos.length === 0
                                radius: Appearance.rounding.unsharpenmore
                                color: Appearance.colors.colSurfaceContainerHigh

                                StyledText {
                                    anchors.centerIn: parent
                                    text: Translation.tr("No pending tasks")
                                    color: Appearance.colors.colOnSurfaceVariant
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                            }
                        }
                    }

                    // ── 页 1：媒体 ────────────────────────────────────────
                    RowLayout {
                        spacing: 16

                        // 封面
                        Rectangle {
                            Layout.alignment: Qt.AlignTop
                            implicitWidth: 176
                            implicitHeight: 176
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colSurfaceContainerHigh
                            clip: true

                            Image {
                                id: coverImage
                                anchors.fill: parent
                                source: root.player?.trackArtUrl ?? ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: status === Image.Ready
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
                                    Layout.fillWidth: true
                                    implicitHeight: 4
                                    radius: height / 2
                                    color: Appearance.colors.colSurfaceContainerHighest

                                    Rectangle {
                                        width: parent.width * Math.max(0, Math.min(1,
                                            (root.player?.position ?? 0) / Math.max(1, root.player?.length ?? 1)))
                                        height: parent.height
                                        radius: parent.radius
                                        color: Appearance.colors.colPrimary
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
                                        anchors.centerIn: parent
                                        text: (root.player?.isPlaying ?? false) ? "pause" : "play_arrow"
                                        iconSize: Appearance.font.pixelSize.huge
                                        color: Appearance.colors.colOnPrimary
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

                            // 当前歌词
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                visible: LyricsService.currentText.length > 0

                                StyledText {
                                    Layout.fillWidth: true
                                    text: LyricsService.currentText
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                    color: Appearance.colors.colPrimary
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.DemiBold
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    visible: LyricsService.currentTrans.length > 0
                                    text: LyricsService.currentTrans
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                    color: Appearance.colors.colSecondary
                                    font.pixelSize: Appearance.font.pixelSize.smaller
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

                        Item {
                            Layout.fillHeight: true
                        }
                    }

                    // ── 页 3：天气 ────────────────────────────────────────
                    RowLayout {
                        spacing: 16

                        ColumnLayout {
                            Layout.alignment: Qt.AlignTop
                            spacing: 4

                            RowLayout {
                                spacing: 10

                                MaterialSymbol {
                                    text: Icons.getWeatherIcon(Weather.data.wCode) ?? "cloud"
                                    iconSize: 48
                                    color: Appearance.colors.colPrimary
                                }

                                ColumnLayout {
                                    spacing: -2

                                    StyledText {
                                        text: Weather.data.temp ?? "--"
                                        color: Appearance.colors.colOnLayer1
                                        font.pixelSize: Appearance.font.pixelSize.hugeass
                                        font.weight: Font.Bold
                                    }

                                    StyledText {
                                        text: Weather.data.description ?? ""
                                        color: Appearance.colors.colOnSurfaceVariant
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                    }
                                }
                            }

                            StyledText {
                                text: Weather.data.city ?? ""
                                color: Appearance.colors.colOnSurfaceVariant
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                            }

                            StyledText {
                                text: Translation.tr("Feels like") + " " + (Weather.data.tempFeelsLike ?? "--")
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
                            { icon: "cloud", label: Translation.tr("Weather") }
                        ]

                        delegate: RippleButton {
                            required property var modelData
                            required property int index
                            readonly property bool isCurrent: pager.currentIndex === index

                            implicitWidth: pageTabRow.implicitWidth + 16
                            implicitHeight: 26
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
                                    iconSize: Appearance.font.pixelSize.small
                                    color: isCurrent
                                        ? Appearance.colors.colOnPrimaryContainer
                                        : Appearance.colors.colOnSurfaceVariant
                                }
                                StyledText {
                                    text: modelData.label
                                    color: isCurrent
                                        ? Appearance.colors.colOnPrimaryContainer
                                        : Appearance.colors.colOnSurfaceVariant
                                    font.pixelSize: Appearance.font.pixelSize.smallest
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
