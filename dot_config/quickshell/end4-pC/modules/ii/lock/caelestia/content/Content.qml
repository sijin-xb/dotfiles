pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "center"

// 移植自 caelestia-dots/shell（GPL-3.0）modules/lock/Content.qml。
// 三栏：左（媒体 + 歌词）/ 中（时钟 + 密码）/ 右（资源 + 通知）。
RowLayout {
    id: root

    required property var lock

    spacing: Tokens.spacing.largeIncreased * 2

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        Media {
            Layout.fillWidth: true
            Layout.fillHeight: true
            lock: root.lock
        }

        LockLyrics {
            Layout.fillWidth: true
            lock: root.lock
        }
    }

    Center {
        lock: root.lock
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        Resources {
            Layout.fillWidth: true
        }

        // 阶段 3：通知面板
        Item { Layout.fillWidth: true; Layout.fillHeight: true }
    }
}
