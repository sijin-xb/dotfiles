pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import M3Shapes
import qs.modules.common
import qs.services
import "../components"

// 移植自 caelestia-dots/shell（GPL-3.0）modules/lock/Media.qml。
// Players.active -> MprisController.activePlayer。
StyledClippingRect {
    id: root

    required property var lock

    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool isPlaying: player?.isPlaying ?? false
    readonly property string artUrl: {
        if (!player) return ""
        const u = player.trackArtUrl
        return (u && u !== "") ? u : ""
    }

    implicitHeight: Math.max(180, layout.implicitHeight + 32)
    radius: Appearance.rounding.large
    color: Appearance.m3colors.m3surfaceContainer

    FadeImage {
        anchors.fill: parent
        source: root.artUrl
        visible: root.artUrl !== ""
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(width, height)
        layer.enabled: true
        opacity: status === Image.Ready ? 1 : 0

        StyledRect {
            anchors.fill: parent
            color: Appearance.m3colors.m3surface
            opacity: 0.72
        }

        Behavior on opacity { Anim { type: Anim.StandardLarge } }
    }

    ColumnLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: 18
        spacing: 4

        CoverArt {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 96
            Layout.preferredHeight: 96
            artSource: root.artUrl
            isPlaying: root.isPlaying
            visible: root.artUrl !== ""
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 8
            animate: true
            text: root.player?.trackTitle || Translation.tr("Nothing playing")
            color: Appearance.m3colors.m3primary
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            animate: true
            text: root.player?.trackArtist || Translation.tr("Try playing some music!")
            color: Appearance.m3colors.m3onSurfaceVariant
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Appearance.font.pixelSize.smallie
            elide: Text.ElideRight
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 10
            spacing: 8

            component CtrlBtn: MaterialShape {
                id: btn
                required property string glyph
                required property bool interactable
                property var onActivate

                implicitSize: 36
                shape: MaterialShape.Circle
                color: ma.pressed ? Appearance.m3colors.m3surfaceContainerHighest
                     : ma.containsMouse ? Appearance.m3colors.m3surfaceContainerHigh
                     : Appearance.m3colors.m3surfaceContainerLow
                opacity: btn.interactable ? 1 : 0.35

                Behavior on color { CAnim {} }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: btn.glyph
                    color: Appearance.m3colors.m3onSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.normal
                }

                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: btn.interactable
                    cursorShape: btn.interactable ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (btn.onActivate) btn.onActivate()
                }
            }

            CtrlBtn {
                glyph: "skip_previous"
                interactable: root.player?.canGoPrevious ?? false
                onActivate: root.player?.previous()
            }
            CtrlBtn {
                glyph: root.isPlaying ? "pause" : "play_arrow"
                interactable: root.player?.canTogglePlaying ?? false
                onActivate: root.player?.togglePlaying()
            }
            CtrlBtn {
                glyph: "skip_next"
                interactable: root.player?.canGoNext ?? false
                onActivate: root.player?.next()
            }
        }
    }
}
