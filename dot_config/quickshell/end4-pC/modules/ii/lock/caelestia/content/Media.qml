pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import M3Shapes
import Caelestia.Config
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

    implicitHeight: layout.implicitHeight + layout.anchors.margins * 2
    radius: Tokens.rounding.extraLarge
    color: Appearance.m3colors.m3surfaceContainer

    FadeImage {
        anchors.fill: parent
        source: root.artUrl
        visible: root.artUrl !== ""

        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        sourceSize: {
            const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
            return Qt.size(width * dpr, height * dpr);
        }

        layer.enabled: true
        opacity: status === Image.Ready ? 1 : 0

        StyledRect {
            anchors.fill: parent
            color: Appearance.m3colors.m3surface
            opacity: 0.7
        }

        Behavior on opacity {
            Anim { type: Anim.StandardExtraLarge }
        }
    }

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Tokens.padding.extraLarge
        spacing: Tokens.spacing.extraSmall

        CoverArt {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(root.width * 0.5, 140)
            Layout.preferredHeight: width
            artSource: root.artUrl
            isPlaying: root.isPlaying
            visible: root.artUrl !== ""
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            animate: true
            text: root.player?.trackTitle || "Nothing playing"
            color: Appearance.m3colors.m3primary
            horizontalAlignment: Text.AlignHCenter
            font: Tokens.font.title.medium
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            animate: true
            text: root.player?.trackArtist || "Try playing some music!"
            color: Appearance.m3colors.m3onSurfaceVariant
            horizontalAlignment: Text.AlignHCenter
            font: Tokens.font.body.small
            elide: Text.ElideRight
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.medium
            spacing: Tokens.spacing.extraSmall

            component CtrlBtn: MaterialShape {
                id: btn
                required property string glyph
                required property bool interactable
                property var onActivate

                implicitSize: 44
                shape: MaterialShape.Circle
                color: ma.pressed ? Appearance.m3colors.m3surfaceContainerHighest
                     : ma.containsMouse ? Appearance.m3colors.m3surfaceContainerHigh
                     : Appearance.m3colors.m3surfaceContainer
                opacity: btn.interactable ? 1 : 0.35

                Behavior on color { CAnim {} }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: btn.glyph
                    color: Appearance.m3colors.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
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
