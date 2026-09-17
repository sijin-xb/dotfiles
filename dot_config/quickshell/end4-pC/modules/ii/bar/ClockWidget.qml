import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * 居中时钟。
 *
 * 显示项对齐 caelestia 的 bar.clock（background / showIcon / showDate /
 * showSeconds / showAmPm）。
 *
 * **悬停不做任何事**（不弹预览弹窗、不变色、不改指针形状）。交互全部是点击/滚轮：
 *   左键           → bar.clock.clickAction：dashboard / sidebarRight /
 *                    wallpaperSelector / none
 *   右键           → 右侧边栏（日历 + 通知）
 *   中键           → 复制「日期 + 时间」到剪贴板
 *   滚轮           → 切换秒显示；按住 Shift 切换 12/24 小时制
 *   Esc / 点击外部 → 关闭仪表盘
 */
BarWidgetSwitcher {
    id: root

    readonly property var clockOptions: Config.options.bar.clock
    property bool showDate: root.clockOptions.showDate
    property bool showSeconds: root.clockOptions.showSeconds
    property bool showIcon: root.clockOptions.showIcon
    property bool showAmPm: root.clockOptions.showAmPm
    property bool hasBackground: root.clockOptions.background

    // 时间拆解直接走 DateTime 单例（SystemClock 已按秒刷新），不自己再起定时器
    readonly property var clockDate: DateTime.clock.date
    readonly property string hourText: DateTime.hourStr
    readonly property string minuteText: DateTime.minuteStr
    readonly property string secondText: Qt.locale().toString(root.clockDate, "ss")
    readonly property string amPmText: DateTime.use12HourFormat ? Qt.locale().toString(root.clockDate, "ap") : ""
    readonly property bool hasAmPm: root.showAmPm && root.amPmText.length > 0
    readonly property string timeText: root.showSeconds
        ? `${root.hourText}:${root.minuteText}:${root.secondText}`
        : `${root.hourText}:${root.minuteText}`

    // ── 交互 ────────────────────────────────────────────────────────────
    function toggleDashboard() {
        GlobalStates.clockDashboardOpen = !GlobalStates.clockDashboardOpen;
    }

    function copyTimeToClipboard() {
        const text = `${Qt.locale().toString(root.clockDate, Config.options.time.dateWithYearFormat)} ${root.timeText}`;
        Quickshell.clipboardText = text;
        Quickshell.execDetached(["notify-send", Translation.tr("Clock"), text, "-a", "Shell"]);
    }

    function runClickAction() {
        switch (root.clockOptions.clickAction) {
        case "dashboard":
            root.toggleDashboard();
            break;
        case "sidebarRight":
            GlobalStates.clockDashboardOpen = false;
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
            break;
        case "wallpaperSelector":
            GlobalStates.clockDashboardOpen = false;
            GlobalStates.wallpaperSelectorOpen = !GlobalStates.wallpaperSelectorOpen;
            break;
        default:
            break;
        }
    }

    function handleClick(event) {
        if (event.button === Qt.MiddleButton) {
            if (root.clockOptions.middleClickCopy)
                root.copyTimeToClipboard();
        } else if (event.button === Qt.RightButton) {
            GlobalStates.clockDashboardOpen = false;
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
        } else {
            root.runClickAction();
        }
    }

    function handleWheel(event) {
        if (event.modifiers & Qt.ShiftModifier) {
            // 12/24 小时制：直接改写 time.format 的前缀
            const fmt = Config.options.time.format;
            const use12 = fmt.toLowerCase().indexOf("ap") !== -1;
            Config.options.time.format = use12
                ? fmt.replace(/ap/i, "")
                : fmt.replace(/hh/, "hh ap");
        } else if (root.clockOptions.wheelSwitchSeconds) {
            root.showSeconds = !root.showSeconds;
            Config.options.bar.clock.showSeconds = root.showSeconds;
        }
    }

    // 其它面板打开时收起仪表盘，避免两个浮层叠着
    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen)
                GlobalStates.clockDashboardOpen = false;
        }
        function onSettingsOpenChanged() {
            if (GlobalStates.settingsOpen)
                GlobalStates.clockDashboardOpen = false;
        }
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen)
                GlobalStates.clockDashboardOpen = false;
        }
    }

    // caelestia 的 bar.clock.background：给整个时钟垫一层玻璃容器
    LiquidGlass {
        id: clockBackground
        z: -1
        anchors.centerIn: parent
        width: root.implicitWidth - (root.isMaterial ? 8 : root.horizontalExtraPadding)
        height: root.implicitHeight - 8
        radius: Appearance.rounding.full
        visible: root.hasBackground
        tint: Qt.rgba(Appearance.colors.colSurfaceContainerHigh.r, Appearance.colors.colSurfaceContainerHigh.g,
            Appearance.colors.colSurfaceContainerHigh.b, 0.7)
    }

    colDefault: Component {
        ColumnLayout {
            id: column
            anchors.centerIn: parent
            spacing: root.hasAmPm ? 1 : 0

            Column {
                Layout.alignment: Qt.AlignHCenter
                spacing: -4

                Repeater {
                    model: root.showSeconds
                        ? [root.hourText, root.minuteText, root.secondText]
                        : [root.hourText, root.minuteText]

                    delegate: StyledText {
                        required property string modelData
                        width: implicitWidth
                        horizontalAlignment: Text.AlignHCenter
                        font.letterSpacing: -0.2
                        font.features: { "tnum": 1 }
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnLayer1
                        text: modelData
                    }
                }

                StyledText {
                    visible: root.hasAmPm
                    width: implicitWidth
                    horizontalAlignment: Text.AlignHCenter
                    font.letterSpacing: -0.2
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                    text: root.amPmText
                }
            }

            StyledText {
                visible: root.showDate
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 5
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnLayer1
                text: DateTime.shortDate
            }
        }
    }

    colMaterial: Component {
        ColumnLayout {
            id: clockWidget
            spacing: 2
            Layout.alignment: Qt.AlignHCenter

            Column {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 2
                spacing: -4

                Repeater {
                    model: root.showSeconds
                        ? [root.hourText, root.minuteText, root.secondText]
                        : [root.hourText, root.minuteText]

                    delegate: StyledText {
                        required property string modelData
                        width: implicitWidth
                        horizontalAlignment: Text.AlignHCenter
                        font.letterSpacing: -0.2
                        font.features: { "tnum": 1 }
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colPrimary
                        text: modelData
                    }
                }

                StyledText {
                    visible: root.hasAmPm
                    width: implicitWidth
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colPrimary
                    text: root.amPmText
                }
            }

            Rectangle {
                visible: root.showIcon
                width: 25
                height: 25
                radius: Appearance.rounding.full
                color: Appearance.colors.colPrimary
                Layout.alignment: Qt.AlignHCenter

                MaterialSymbol {
                    anchors.centerIn: parent
                    fill: 0
                    text: "calendar_month"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }

    rowDefault: Component {
        RowLayout {
            spacing: 4

            MaterialSymbol {
                visible: root.showIcon
                text: "calendar_month"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colPrimary
            }

            StyledText {
                visible: root.showDate
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
                text: DateTime.longDate
            }

            StyledText {
                visible: root.showDate
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
                text: "•"
            }

            StyledText {
                font.pixelSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnLayer1
                text: root.timeText
                font.letterSpacing: -0.4
                font.features: { "tnum": 1 }
            }

            StyledText {
                visible: root.hasAmPm
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1
                text: root.amPmText
            }
        }
    }

    rowMaterial: Component {
        RowLayout {
            id: pill
            spacing: 4

            MaterialSymbol {
                visible: root.showIcon
                text: "calendar_month"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colPrimary
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                visible: root.showDate
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnPrimaryContainer
                text: DateTime.longDate
                Layout.alignment: Qt.AlignVCenter
                leftPadding: 5
            }

            Rectangle {
                implicitWidth: timeText.implicitWidth + 16
                implicitHeight: 24
                radius: Appearance.rounding.full
                color: Appearance.colors.colPrimary

                StyledText {
                    id: timeText
                    anchors.centerIn: parent
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: Appearance.colors.colOnPrimary
                    font.weight: Font.Bold
                    text: root.timeText
                    font.features: { "tnum": 1 }
                    font.letterSpacing: -0.4
                }
            }

            Rectangle {
                visible: root.hasAmPm
                z: 1
                implicitWidth: ampmText.implicitWidth + 8
                implicitHeight: 24
                radius: Appearance.rounding.full
                color: Appearance.colors.colTertiaryContainer
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: -10
                StyledText {
                    id: ampmText
                    anchors.centerIn: parent
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colPrimary
                    text: root.amPmText
                }
            }
        }
    }

    // 交互全部走点击/滚轮。**悬停在这里彻底不做任何事**：
    // 不弹预览弹窗、不变色、不改指针形状 —— 时钟的悬停效果已按需求移除。
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: event => root.handleClick(event)
        onWheel: event => root.handleWheel(event)
    }
}
