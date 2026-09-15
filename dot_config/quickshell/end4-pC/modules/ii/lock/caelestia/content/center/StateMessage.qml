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

    implicitHeight: msg.implicitHeight

    StyledText {
        id: msg
        anchors.centerIn: parent
        text: root.lock.showFailure ? Translation.tr("Incorrect password") : ""
        color: Appearance.m3colors.m3error
        font.pixelSize: Appearance.font.pixelSize.small
        animate: true
        opacity: root.lock.showFailure ? 1 : 0
        Behavior on opacity { Anim { type: Anim.DefaultEffects } }
    }
}
