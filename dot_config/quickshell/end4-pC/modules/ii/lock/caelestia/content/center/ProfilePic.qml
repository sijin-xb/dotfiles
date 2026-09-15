pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import M3Shapes
import Caelestia.Config
import qs.modules.common
import "../../components"

// 移植自 caelestia-dots/shell（GPL-3.0）modules/lock/center/ProfilePic.qml。
// 头像来源改用 end4-pC 约定：Config.options.profile.avatarPath 优先，
// 否则回退 ~/.face。
Item {
    id: root

    required property int centerWidth
    readonly property color bgColour: Appearance.m3colors.m3surfaceContainerHighest

    readonly property string avatarSource: {
        const p = Config.options?.profile
        if (p && p.avatarPath && p.avatarPath !== "")
            return Qt.resolvedUrl(p.avatarPicture ?? p.avatarPath)
        return Qt.resolvedUrl(`file:///home/${Quickshell.env("USER") ?? "user"}/.face`)
    }

    implicitWidth: Math.round(centerWidth * 0.7)
    implicitHeight: {
        shape.height;
        return shape.pathBounds().height;
    }

    MaterialShape {
        id: shape

        anchors.centerIn: parent
        implicitSize: root.implicitWidth

        shape: MaterialShape.ClamShell
        color: Qt.alpha(root.bgColour, 1)
        opacity: root.bgColour.a
        layer.enabled: true
    }

    MaterialIcon {
        anchors.centerIn: parent

        text: "person"
        color: Appearance.m3colors.m3onSurfaceVariant
        fontStyle: Tokens.font.icon.size(root.centerWidth / 4).build()
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
