pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import "../../components"

// 移植自 caelestia-dots/shell（GPL-3.0）modules/lock/center/Clock.qml。
// 时 m3primary / 分 m3secondary，分色排版。字号走 end4-pC 的 Appearance。
Item {
    id: root

    required property real centerScale
    property date now: new Date()

    readonly property int timeSize: Math.round(72 * Math.max(0.85, centerScale))

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.now = new Date()
    }

    implicitWidth: clockRow.implicitWidth
    implicitHeight: clockRow.implicitHeight

    Row {
        id: clockRow
        anchors.centerIn: parent
        spacing: 4

        StyledText {
            text: Qt.formatDateTime(root.now, "HH")
            color: Appearance.m3colors.m3primary
            font.pixelSize: root.timeSize
            font.weight: Font.Bold
            font.letterSpacing: -1.5
        }

        StyledText {
            text: ":"
            color: Qt.alpha(Appearance.m3colors.m3outlineVariant, 0.7)
            font.pixelSize: root.timeSize
            font.weight: Font.Normal
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -Math.round(root.timeSize * 0.05)
        }

        StyledText {
            text: Qt.formatDateTime(root.now, "mm")
            color: Appearance.m3colors.m3secondary
            font.pixelSize: root.timeSize
            font.weight: Font.Bold
            font.letterSpacing: -1.5
        }
    }
}
