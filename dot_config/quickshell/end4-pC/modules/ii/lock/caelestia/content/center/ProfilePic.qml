pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import M3Shapes
import qs.modules.common
import "../../components"

// 移植自 caelestia-dots/shell（GPL-3.0）modules/lock/center/ProfilePic.qml。
Item {
    id: root

    required property int centerWidth
    readonly property int avatarSize: Math.round(centerWidth * 0.40)
    readonly property color bgColour: Appearance.m3colors.m3surfaceContainerHighest

    readonly property string avatarSource: {
        const p = Config.options?.profile
        if (p && p.avatarPath && p.avatarPath !== "")
            return Qt.resolvedUrl(p.avatarPicture ?? p.avatarPath)
        return Qt.resolvedUrl(`file:///home/${Quickshell.env("USER") ?? "user"}/.face`)
    }

    implicitWidth: avatarSize + 12
    implicitHeight: avatarSize + 12

    // 外层微妙光晕描边
    MaterialShape {
        id: halo
        anchors.centerIn: parent
        implicitSize: root.avatarSize + 8
        shape: MaterialShape.ClamShell
        color: Qt.alpha(Appearance.m3colors.m3primaryContainer, 0.5)
        layer.enabled: true
    }

    MaterialShape {
        id: shape
        anchors.centerIn: parent
        implicitSize: root.avatarSize
        shape: MaterialShape.ClamShell
        color: root.bgColour
        layer.enabled: true
    }

    MaterialIcon {
        anchors.centerIn: parent
        text: "person"
        color: Appearance.m3colors.m3onSurfaceVariant
        font.pixelSize: Math.round(root.avatarSize * 0.42)
        visible: pfp.status !== Image.Ready
    }

    Image {
        id: pfp
        anchors.fill: shape
        source: root.avatarSource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true

        layer.enabled: true
        layer.effect: Mask {
            maskSource: shape
        }
    }
}
