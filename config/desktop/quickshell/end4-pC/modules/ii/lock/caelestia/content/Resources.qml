pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import M3Shapes
import qs.modules.common
import qs.services
import "../components"

// 移植自 caelestia-dots/shell（GPL-3.0）modules/lock/Resources.qml。
ColumnLayout {
    id: root

    spacing: 16

    ResourceCard {
        label: Translation.tr("CPU")
        icon: "memory"
        value: `${Math.round(ResourceUsage.cpuUsage * 100)}%`
        fillValue: ResourceUsage.cpuUsage
        colour: Appearance.m3colors.m3primary
        shapeColour: Appearance.m3colors.m3primaryContainer
        fillColour: Qt.alpha(Appearance.m3colors.m3primary, 0.4)
        iconColour: Appearance.m3colors.m3onPrimaryContainer
        shape: MaterialShape.Pentagon
    }

    ResourceCard {
        label: Translation.tr("RAM")
        icon: "memory_alt"
        value: `${Math.round(ResourceUsage.memoryUsedPercentage * 100)}%`
        fillValue: ResourceUsage.memoryUsedPercentage
        colour: Appearance.m3colors.m3tertiary
        shapeColour: Appearance.m3colors.m3tertiaryContainer
        fillColour: Qt.alpha(Appearance.m3colors.m3tertiary, 0.4)
        iconColour: Appearance.m3colors.m3onTertiaryContainer
        shape: MaterialShape.Slanted
    }

    ResourceCard {
        label: Translation.tr("Disk")
        icon: "storage"
        value: `${Math.round(ResourceUsage.diskUsedPercentage * 100)}%`
        fillValue: ResourceUsage.diskUsedPercentage
        colour: Appearance.m3colors.m3secondary
        shapeColour: Appearance.m3colors.m3secondaryContainer
        fillColour: Qt.alpha(Appearance.m3colors.m3secondary, 0.4)
        iconColour: Appearance.m3colors.m3onSecondaryContainer
        shape: MaterialShape.Gem
    }

    component ResourceCard: StyledRect {
        id: card

        required property string label
        required property string icon
        required property string value
        required property real fillValue
        required property color colour
        required property color shapeColour
        required property color fillColour
        required property color iconColour
        required property int shape

        Layout.fillWidth: true
        Layout.fillHeight: true

        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainer

        border.width: 1
        border.color: Qt.alpha(Appearance.m3colors.m3outlineVariant, 0.35)

        RowLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 16

            // 左侧液态形状水波
            Item {
                id: shapeWrapper
                readonly property real shapeSize: Math.min(56, Math.max(36, parent.height - 8))
                implicitWidth: shapeSize
                implicitHeight: shapeSize
                Layout.alignment: Qt.AlignVCenter

                MaterialShape {
                    id: mShape
                    anchors.fill: parent
                    shape: card.shape
                    color: card.shapeColour
                    layer.enabled: true
                }

                Loader {
                    anchors.fill: mShape
                    active: card.fillValue >= 0
                    asynchronous: true
                    layer.enabled: active
                    layer.effect: Mask { maskSource: mShape }

                    sourceComponent: Item {
                        WavyTopRect {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            implicitHeight: mShape.height * Math.max(0, Math.min(1, card.fillValue))
                            color: card.fillColour
                        }
                    }
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: card.icon
                    color: card.iconColour
                    font.pixelSize: Appearance.font.pixelSize.normal
                    fill: 1
                }
            }

            // 右侧指标与横向进度条
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        text: card.label
                        color: Appearance.m3colors.m3onSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        text: card.value
                        color: card.colour
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Bold
                    }
                }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 6
                    radius: 3
                    color: Appearance.m3colors.m3surfaceContainerHighest

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * Math.max(0, Math.min(1, card.fillValue))
                        radius: 3
                        color: card.colour
                        Behavior on width { Anim { type: Anim.DefaultEffects } }
                    }
                }
            }
        }

        Behavior on fillValue { Anim {} }
    }
}
