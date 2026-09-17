pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.services
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
    spacing: 8

    property date now: new Date()
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.now = new Date()
    }

    Item { Layout.fillHeight: true }

    Clock {
        Layout.alignment: Qt.AlignHCenter
        centerScale: root.centerScale
        now: root.now
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        text: Qt.formatDateTime(root.now, "dddd • d MMM")
        color: Appearance.m3colors.m3onSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.small
        font.weight: Font.Medium
        font.letterSpacing: 0.8
    }

    ProfilePic {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 8
        Layout.bottomMargin: 2
        centerWidth: root.centerWidth
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        Layout.bottomMargin: 8
        text: SystemInfo.username
        color: Appearance.m3colors.m3onSurface
        font.pixelSize: Appearance.font.pixelSize.normal
        font.weight: Font.DemiBold
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
