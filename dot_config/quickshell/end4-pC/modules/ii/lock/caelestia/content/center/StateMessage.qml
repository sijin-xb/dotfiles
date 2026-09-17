pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.services
import "../../components"

// 移植自 caelestia-dots/shell（GPL-3.0）modules/lock/center/StateMessage.qml。
// pam.state -> LockContext.showFailure。
Item {
    id: root

    required property var lock

    implicitHeight: Math.max(24, msgRow.implicitHeight)

    Row {
        id: msgRow
        anchors.centerIn: parent
        spacing: 6
        opacity: (root.lock.showFailure || root.lock.unlockInProgress) ? 1 : 0
        Behavior on opacity { Anim { type: Anim.DefaultEffects } }

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: root.lock.showFailure ? "error" : "progress_activity"
            color: root.lock.showFailure ? Appearance.m3colors.m3error : Appearance.m3colors.m3primary
            font.pixelSize: Appearance.font.pixelSize.smallie
            fill: 1
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.lock.showFailure
                ? Translation.tr("Incorrect password")
                : (root.lock.unlockInProgress ? Translation.tr("Unlocking…") : "")
            color: root.lock.showFailure ? Appearance.m3colors.m3error : Appearance.m3colors.m3primary
            font.pixelSize: Appearance.font.pixelSize.smallie
            font.weight: Font.Medium
        }
    }
}
