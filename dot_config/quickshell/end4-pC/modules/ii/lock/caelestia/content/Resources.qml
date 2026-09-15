pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import M3Shapes
import qs.modules.common
import qs.services
import "../components"

// 移植自 caelestia-dots/shell（GPL-3.0）modules/lock/Resources.qml。
StyledRect {
    id: root

    implicitHeight: 96
    radius: Appearance.rounding.large
    color: Appearance.m3colors.m3surfaceContainer

    RowLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        Resource {
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
        Layout.fillHeight: true

        // 三种 MaterialShape 视觉占比不同（Pentagon 内缩、Slanted/Gem 更满），
        // 统一取较短边作为形状尺寸并居中，避免高低不齐。
        readonly property real shapeSize: Math.min(width, height)

        MaterialShape {
            id: shape
            anchors.centerIn: parent
            implicitSize: res.shapeSize
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
            layer.effect: Mask { maskSource: shape }

            sourceComponent: Item {
                WavyTopRect {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    implicitHeight: shape.height * Math.max(0, Math.min(1, res.fillValue))
                    color: res.fillColour
                }
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: -3

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: res.icon
                color: Appearance.m3colors.m3onSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.smallie
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: res.value
                color: res.colour
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
            }
        }

        Behavior on fillValue { Anim {} }
    }
}
