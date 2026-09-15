pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import "../../components"

// 移植自 caelestia-dots/shell（GPL-3.0）modules/lock/center/Clock.qml。
// 时 m3primary / 分 m3secondary，分色排版。字号走 end4-pC 的 Appearance。
Item {
    id: root

    required property real centerScale

    readonly property int timeSize: Math.round(64 * Math.max(0.8, centerScale))

    property date now: new Date()
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.now = new Date()
    }

    implicitWidth: hours.implicitWidth + minutes.implicitWidth + 2
    implicitHeight: hours.implicitHeight

    StyledText {
        id: hours
        text: Qt.formatDateTime(root.now, "hh")
        color: Appearance.m3colors.m3primary
        font.pixelSize: root.timeSize
        font.weight: Font.DemiBold
        font.letterSpacing: -2
    }

    StyledText {
        id: minutes
        anchors.left: hours.right
        anchors.baseline: hours.baseline
        text: Qt.formatDateTime(root.now, "mm")
        color: Appearance.m3colors.m3secondary
        font.pixelSize: root.timeSize
        font.weight: Font.DemiBold
        font.letterSpacing: -2
    }
}
