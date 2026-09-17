pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import "center"

// 移植自 caelestia-dots/shell（GPL-3.0）modules/lock/Content.qml。
// 三栏：左（媒体 + 歌词）/ 中（时钟 + 密码）/ 右（资源）。
RowLayout {
    id: root

    required property var lock
    required property real screenHeight

    spacing: 16

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        spacing: 16

        Media {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 3
            lock: root.lock
        }

        LockLyrics {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 2
            lock: root.lock
        }
    }

    Center {
        Layout.fillHeight: true
        lock: root.lock
        screenHeight: root.screenHeight
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        spacing: 16

        Resources {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}
