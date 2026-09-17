import QtQuick
import QtQuick.Layouts
import Quickshell
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
 * 定位对齐 caelestia 的 Dashboard：把「时间」相关的信息集中到一个从栏中央
 * 拉开的浮层里，而不是只靠悬停看一个小 tooltip。
 *
 * 内容：大时钟 / 完整日期 / 月历 / 世界时钟 / 番茄钟 / 待办
 * 交互：左键时钟切换开关；点击浮层外或按 Esc 关闭。
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
    readonly property int cardMaxHeight: 660
    // 同时受屏幕高度约束，避免在小屏上把底部内容裁掉
    readonly property real cardHeight: Math.min(contentColumn.implicitHeight + 32,
        Math.min(root.cardMaxHeight, root.height - Appearance.sizes.barHeight - 40))

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
    // 需要真实键盘焦点，Esc 才收得到
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

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
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.OutCubic
                }
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    GlobalStates.clockDashboardOpen = false;
                    event.accepted = true;
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
                spacing: 14

                // ── 头部：大时钟 + 完整日期 ─────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ColumnLayout {
                        spacing: 2

                        Row {
                            spacing: 1

                            StyledText {
                                text: DateTime.hourStr
                                color: Appearance.m3colors.m3primary
                                font.pixelSize: 46
                                font.weight: Font.Bold
                                font.letterSpacing: -1.5
                            }

                            StyledText {
                                text: ":"
                                color: Qt.alpha(Appearance.m3colors.m3outlineVariant, 0.7)
                                font.pixelSize: 46
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 5
                            }

                            StyledText {
                                text: DateTime.minuteStr
                                color: Appearance.m3colors.m3secondary
                                font.pixelSize: 46
                                font.weight: Font.Bold
                                font.letterSpacing: -1.5
                            }

                            StyledText {
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 9
                                leftPadding: 4
                                text: Qt.locale().toString(DateTime.clock.date, "ss")
                                color: Appearance.colors.colOnSurfaceVariant
                                font.pixelSize: Appearance.font.pixelSize.large
                                font.features: { "tnum": 1 }
                            }
                        }

                        RowLayout {
                            spacing: 6

                            StyledText {
                                text: Qt.locale().toString(DateTime.clock.date, "dddd")
                                color: Appearance.colors.colPrimary
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                            }

                            StyledText {
                                text: Qt.locale().toString(DateTime.clock.date, "yyyy/MM/dd")
                                color: Appearance.colors.colOnSurfaceVariant
                                font.pixelSize: Appearance.font.pixelSize.small
                            }

                            StyledText {
                                visible: DateTime.use12HourFormat
                                text: Qt.locale().toString(DateTime.clock.date, "ap")
                                color: Appearance.colors.colOnSurfaceVariant
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        spacing: 2

                        RippleButton {
                            implicitWidth: 34
                            implicitHeight: 34
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
                            implicitWidth: 34
                            implicitHeight: 34
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
                            implicitWidth: 34
                            implicitHeight: 34
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

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Appearance.colors.colOutlineVariant
                }

                // ── 主体：月历 / 世界时钟+番茄钟 / 待办 ─────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 14

                    ColumnLayout {
                        spacing: 6

                        StyledText {
                            text: Translation.tr("Calendar")
                            color: Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                        }

                        CalendarWidget {
                            Layout.alignment: Qt.AlignHCenter
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

                // ── 底部：系统信息 ───────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    MaterialSymbol {
                        text: "timelapse"
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    StyledText {
                        text: Translation.tr("System Uptime")
                        color: Appearance.colors.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }

                    StyledText {
                        text: DateTime.uptime
                        color: Appearance.colors.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    StyledText {
                        text: Translation.tr("Click outside or press Esc to close")
                        color: Appearance.colors.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        opacity: 0.7
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
    }
}
