pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * 概览窗口缩略图的悬浮信息卡：标题/应用、实时 CPU 占用与内存（整个进程树）、
 * 所在工作区，以及「聚焦 / 关闭」操作。
 *
 * winStats.sh 输出原始 CPU ticks，这里对相邻两次采样做差得到占用率：
 * 打开瞬间先采一次基准，600ms 后再采一次，之后每 1.5s 刷新一次，
 * 只有卡片打开时才会轮询。打开时有淡入 + 逐行错峰入场动画。
 */
Popup {
    id: root

    property var windowData
    readonly property string address: windowData?.address ?? ""
    readonly property bool isHyprlandWindow: (windowData?.pid ?? 0) > 0
    property real cpuPercent: -1
    property real memKb: 0
    property var prevSample: null
    property bool valueFlash: false // 数值刚刷新时闪一下主题色

    readonly property string cpuText: cpuPercent < 0 ? "…" : `${Math.round(cpuPercent)}%`
    readonly property string memText: {
        if (memKb >= 1024 * 1024)
            return (memKb / 1024 / 1024).toFixed(1) + " G";
        if (memKb >= 1024)
            return Math.round(memKb / 1024) + " M";
        return Math.round(memKb) + " K";
    }

    function hoverEnter() {
        hideTimer.stop();
        if (!opened)
            openCard();
    }
    function hoverExit() {
        hideTimer.restart();
    }
    function dismiss() {
        hideTimer.stop();
        close();
    }
    function openCard() {
        cpuPercent = -1;
        memKb = 0;
        prevSample = null;
        open();
        Qt.callLater(position);
        refresh();
    }
    // 默认显示在缩略图上方，顶部空间不够时翻转到下方
    function position() {
        const scene = parent.mapToItem(null, 0, 0);
        const fitsAbove = scene.y > (root.height + 14);
        y = fitsAbove ? -height - 10 : parent.height + 10;
        x = -(width - parent.width) / 2;
    }
    function refresh() {
        if (address.length === 0 || !isHyprlandWindow || statsProc.running)
            return;
        statsProc.running = true;
    }
    function applyClient(c) {
        if (c.address !== root.address)
            return;
        const now = Date.now();
        if (prevSample && prevSample.pid === c.pid && c.clkTck > 0) {
            const dt = (now - prevSample.at) / 1000;
            const dTicks = c.cpuTicks - prevSample.cpuTicks;
            if (dt > 0.2)
                cpuPercent = Math.max(0, dTicks / dt / c.clkTck * 100);
        } else {
            cpuPercent = -1;
        }
        memKb = c.rssKb;
        prevSample = {
            pid: c.pid,
            cpuTicks: c.cpuTicks,
            at: now
        };
        valueFlash = true;
        flashReset.restart();
    }

    width: 252
    padding: 12
    closePolicy: Popup.NoAutoClose

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: 150
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            property: "scale"
            from: 0.9
            to: 1
            duration: 220
            easing.type: Easing.OutBack
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "opacity"
            to: 0
            duration: 120
            easing.type: Easing.InQuad
        }
        NumberAnimation {
            property: "scale"
            to: 0.93
            duration: 120
            easing.type: Easing.InQuad
        }
    }

    onOpenedChanged: {
        if (opened)
            warmupTimer.restart();
    }
    onAddressChanged: {
        if (opened)
            close();
    }

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (!GlobalStates.overviewOpen)
                root.dismiss();
        }
    }

    Timer {
        id: pollTimer
        interval: 1500
        running: root.opened
        repeat: true
        onTriggered: root.refresh()
    }
    Timer { // 打开后很快补采第二次，CPU 占用率能立刻出现
        id: warmupTimer
        interval: 600
        onTriggered: root.refresh()
    }
    Timer {
        id: hideTimer
        interval: 400
        onTriggered: root.close()
    }
    Timer {
        id: flashReset
        interval: 250
        onTriggered: root.valueFlash = false
    }

    Process {
        id: statsProc
        command: [`${Directories.scriptPath}/pet/winStats.sh`]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const arr = JSON.parse(text);
                    for (const c of arr)
                        root.applyClient(c);
                } catch (e) {}
            }
        }
    }

    background: Rectangle {
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2
        border.width: 1
        border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.72)
        HoverHandler {
            onHoveredChanged: {
                if (hovered)
                    hideTimer.stop();
                else
                    root.hoverExit();
            }
        }
    }

    // 逐行错峰入场：opened 时依次淡入 + 从左侧滑入
    component RevealRow: SequentialAnimation {
        id: revealAnim
        property Item revealItem
        property Translate revealTranslate
        property int revealDelay: 0
        running: root.opened
        loops: 1
        PauseAnimation {
            duration: revealAnim.revealDelay
        }
        ParallelAnimation {
            NumberAnimation {
                target: revealAnim.revealItem
                property: "opacity"
                to: 1
                duration: 170
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: revealAnim.revealTranslate
                property: "x"
                to: 0
                duration: 170
                easing.type: Easing.OutCubic
            }
        }
    }

    contentItem: ColumnLayout {
        spacing: 7

        RowLayout { // 头部：应用图标 + 标题 + 窗口类
            id: headerRow
            spacing: 8
            Layout.fillWidth: true
            opacity: 0
            transform: Translate {
                id: headerRowT
                x: -8
            }
            RevealRow {
                revealItem: headerRow
                revealTranslate: headerRowT
                revealDelay: 0
            }

            Image {
                Layout.alignment: Qt.AlignTop
                source: Quickshell.iconPath(AppSearch.guessIcon(root.windowData?.class), "image-missing")
                sourceSize: Qt.size(20, 20)
                width: 20
                height: 20
            }
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: root.windowData?.title ?? ""
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.fillWidth: true
                    text: `${root.windowData?.class ?? ""}${root.windowData?.xwayland ? " · XWayland" : ""}`
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                }
            }
        }

        RowLayout { // 处理器
            id: cpuRow
            spacing: 8
            Layout.fillWidth: true
            opacity: 0
            transform: Translate {
                id: cpuRowT
                x: -8
            }
            RevealRow {
                revealItem: cpuRow
                revealTranslate: cpuRowT
                revealDelay: 45
            }

            MaterialSymbol {
                text: "speed"
                iconSize: 16
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                text: "处理器"
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1
            }
            Item {
                Layout.fillWidth: true
            }
            StyledText {
                text: root.cpuText
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: root.valueFlash ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                Behavior on color {
                    ColorAnimation {
                        duration: 700
                    }
                }
            }
        }

        RowLayout { // 内存
            id: memRow
            spacing: 8
            Layout.fillWidth: true
            opacity: 0
            transform: Translate {
                id: memRowT
                x: -8
            }
            RevealRow {
                revealItem: memRow
                revealTranslate: memRowT
                revealDelay: 90
            }

            MaterialSymbol {
                text: "memory"
                iconSize: 16
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                text: "内存"
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1
            }
            Item {
                Layout.fillWidth: true
            }
            StyledText {
                text: root.memText
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: root.valueFlash ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                Behavior on color {
                    ColorAnimation {
                        duration: 700
                    }
                }
            }
        }

        RowLayout { // 工作区
            id: wsRow
            spacing: 8
            Layout.fillWidth: true
            opacity: 0
            transform: Translate {
                id: wsRowT
                x: -8
            }
            RevealRow {
                revealItem: wsRow
                revealTranslate: wsRowT
                revealDelay: 135
            }

            MaterialSymbol {
                text: "grid_view"
                iconSize: 16
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                text: `工作区 ${root.windowData?.workspace?.id ?? "?"}`
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1
            }
            Item {
                Layout.fillWidth: true
            }
        }

        RowLayout { // 操作
            id: actionRow
            spacing: 8
            Layout.topMargin: 2
            Layout.fillWidth: true
            visible: root.isHyprlandWindow
            opacity: visible ? 0 : 1
            transform: Translate {
                id: actionRowT
                x: -8
            }
            RevealRow {
                revealItem: actionRow
                revealTranslate: actionRowT
                revealDelay: 180
            }

            DialogButton {
                buttonText: "聚焦"
                implicitHeight: 30
                padding: 10
                Layout.fillWidth: true
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                colText: Appearance.m3colors.m3onPrimary
                onClicked: {
                    Hyprland.dispatch(`hl.dsp.focus({ window = "address:${root.address}" })`);
                    GlobalStates.overviewOpen = false;
                }
            }
            DialogButton {
                buttonText: "关闭"
                implicitHeight: 30
                padding: 10
                Layout.fillWidth: true
                colText: Appearance.colors.colError
                onClicked: {
                    Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${root.address}" })`);
                    root.dismiss();
                }
            }
        }
    }
}
