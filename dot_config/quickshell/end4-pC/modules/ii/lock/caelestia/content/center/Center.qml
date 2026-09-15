pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import "../../components"

// 移植自 caelestia-dots/shell（GPL-3.0）modules/lock/Center.qml。
ColumnLayout {
    id: root

    required property var lock
    required property real screenHeight

    readonly property real centerScale: Math.min(1, (screenHeight > 0 ? screenHeight : 1440) / 1440)
    readonly property int centerWidth: Math.round(340 * Math.max(0.85, centerScale))

    Layout.preferredWidth: centerWidth
    Layout.fillWidth: false
    Layout.fillHeight: true
    spacing: 12

    property date now: new Date()
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.now = new Date()
    }

    Clock {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 8
        centerScale: root.centerScale
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        text: Qt.formatDateTime(root.now, "dddd • d MMM").toUpperCase()
        color: Appearance.m3colors.m3onSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smallie
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2
    }

    ProfilePic {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 12
        Layout.bottomMargin: 12
        centerWidth: root.centerWidth
    }

    PasswordInput {
        Layout.alignment: Qt.AlignHCenter
        centerScale: Math.max(0.85, root.centerScale)
        centerWidth: root.centerWidth
        lock: root.lock
    }

    StateMessage {
        Layout.fillWidth: true
        lock: root.lock
    }

    Item { Layout.fillHeight: true }
}
