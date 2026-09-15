pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import M3Shapes
import Caelestia.Config
import qs.modules.common
import qs.services
import "../components"

// 移植自 caelestia-dots/shell（GPL-3.0）modules/lock/Resources.qml。
// Cpu/Memory/Storage -> end4-pC 的 ResourceUsage 单例。
StyledRect {
    id: root

    readonly property real fontScale: {
        const diff = width / 391 - 1;
        return 1 + Math.pow(Math.abs(diff), 0.8) * Math.sign(diff);
    }

    implicitHeight: layout.implicitHeight + layout.anchors.margins * 2
    radius: Tokens.rounding.extraLarge
    color: Appearance.m3colors.m3surfaceContainer

    RowLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.large

        Resource {
            id: cpu

            icon: "memory"
            value: `${Math.round(ResourceUsage.cpuUsage * 100)}%`
            fillValue: ResourceUsage.cpuUsage
            colour: Appearance.m3colors.m3primary
            shapeColour: Appearance.m3colors.m3primaryContainer
            fillColour: Qt.alpha(Appearance.m3colors.m3secondary, 0.3)
            shape: MaterialShape.Pentagon
        }

        Resource {
            icon: "memory_alt"
            value: `${Math.round(ResourceUsage.memoryUsedPercentage * 100)}%`
            fillValue: ResourceUsage.memoryUsedPercentage
            colour: Appearance.m3colors.m3tertiary
            shapeColour: Appearance.m3colors.m3onTertiary
            fillColour: Qt.alpha(Appearance.m3colors.m3tertiary, 0.3)
            shape: MaterialShape.Slanted
        }

        Resource {
            icon: "hard_disk"
            value: `${Math.round(ResourceUsage.diskUsedPercentage * 100)}%`
            fillValue: ResourceUsage.diskUsedPercentage
            colour: Appearance.m3colors.m3secondary
            shapeColour: Appearance.m3colors.m3secondaryContainer
            fillColour: Qt.alpha(Appearance.m3colors.m3secondary, 0.4)
            shape: MaterialShape.Gem
        }
    }

    component Resource: Item {
        id: res

        required property string icon
        required property string value
        required property color colour
        required property color shapeColour
        property color fillColour
        property real fillValue: -1
        property alias shape: shape.shape
        readonly property alias mShape: shape

        Layout.fillWidth: true
        implicitHeight: width

        Behavior on shapeColour { CAnim {} }

        MaterialShape {
            id: shape

            implicitSize: res.width
            color: Qt.alpha(res.shapeColour, 1)
            opacity: res.shapeColour.a
            layer.enabled: true
        }

        Loader {
            id: fillLoader

            anchors.fill: shape
            active: res.fillValue >= 0
            asynchronous: true

            layer.enabled: active
            layer.effect: Mask {
                maskSource: shape
            }

            sourceComponent: Item {
                WavyTopRect {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom

                    implicitHeight: shape.implicitSize * Math.max(0, Math.min(1, res.fillValue))
                    color: res.fillColour
                }
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: -Tokens.spacing.extraSmall

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: res.icon
                color: Appearance.m3colors.m3secondary
                fontStyle: Tokens.font.icon.builders.medium.scale(root.fontScale).build()
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: res.value
                color: res.colour
                font: Tokens.font.headline.builders.large.scale(root.fontScale).width(50).build()
            }
        }

        Behavior on fillValue { Anim {} }
    }
}
