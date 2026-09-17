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

    readonly property real progress: {
        if (!player || !player.length || player.length <= 0) return 0
        return Math.max(0, Math.min(1, player.position / player.length))
    }

    function fmtTime(s: real): string {
        const totalSec = Math.max(0, Math.floor(s || 0));
        const m = Math.floor(totalSec / 60);
        const sec = totalSec % 60;
        return m + ":" + (sec < 10 ? "0" : "") + sec;
    }

    Timer {
        interval: 1000
        running: root.isPlaying && root.player !== null
        repeat: true
        onTriggered: if (root.player) root.player.positionChanged()
    }

    implicitHeight: Math.max(220, layout.implicitHeight + 32)
    radius: Appearance.rounding.large
    color: Appearance.m3colors.m3surfaceContainer

    border.width: 1
    border.color: Qt.alpha(Appearance.m3colors.m3outlineVariant, 0.35)

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
            color: Appearance.m3colors.m3surfaceContainer
            opacity: 0.82
        }

        Behavior on opacity { Anim { type: Anim.StandardLarge } }
    }

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 16
        spacing: 4

        Item { Layout.fillHeight: true }

        CoverArt {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 96
            Layout.preferredHeight: 96
            artSource: root.artUrl
            isPlaying: root.isPlaying
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 8
            animate: true
            text: root.player?.trackTitle || Translation.tr("Nothing playing")
            color: Appearance.m3colors.m3onSurface
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.Bold
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

        // 进度条
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 8
            visible: root.player !== null && (root.player.length ?? 0) > 0

            StyledText {
                text: root.fmtTime(root.player?.position ?? 0)
                color: Appearance.m3colors.m3onSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.smallest
            }

            StyledRect {
                id: trackBar
                Layout.fillWidth: true
                implicitHeight: 4
                radius: 2
                color: Appearance.m3colors.m3surfaceContainerHighest

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * root.progress
                    radius: 2
                    color: Appearance.m3colors.m3primary
                    Behavior on width { Anim { type: Anim.FastEffects } }
                }
            }

            StyledText {
                text: root.fmtTime(root.player?.length ?? 0)
                color: Appearance.m3colors.m3onSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.smallest
            }
        }

        // 控制按钮
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 8
            spacing: 12

            component SecondaryBtn: MaterialShape {
                id: sBtn
                required property string glyph
                required property bool interactable
                property var onActivate

                implicitSize: 38
                shape: MaterialShape.Circle
                color: Appearance.m3colors.m3surfaceContainerHigh
                opacity: sBtn.interactable ? 1 : 0.35

                Behavior on color { CAnim {} }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: sBtn.glyph
                    color: Appearance.m3colors.m3onSurface
                    font.pixelSize: Appearance.font.pixelSize.large
                }

                StateLayer {
                    disabled: !sBtn.interactable
                    radius: Appearance.rounding.full
                    onClicked: if (sBtn.onActivate) sBtn.onActivate()
                }
            }

            SecondaryBtn {
                glyph: "skip_previous"
                interactable: root.player?.canGoPrevious ?? false
                onActivate: root.player?.previous()
            }

            // 主播放按钮
            MaterialShape {
                id: playBtn
                readonly property bool interactable: root.player?.canTogglePlaying ?? false

                implicitSize: 48
                shape: MaterialShape.Circle
                color: Appearance.m3colors.m3primary
                opacity: playBtn.interactable ? 1 : 0.35

                Behavior on color { CAnim {} }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.isPlaying ? "pause" : "play_arrow"
                    color: Appearance.m3colors.m3onPrimary
                    font.pixelSize: Appearance.font.pixelSize.larger
                    fill: 1
                }

                StateLayer {
                    disabled: !playBtn.interactable
                    radius: Appearance.rounding.full
                    onClicked: root.player?.togglePlaying()
                }
            }

            SecondaryBtn {
                glyph: "skip_next"
                interactable: root.player?.canGoNext ?? false
                onActivate: root.player?.next()
            }
        }

        Item { Layout.fillHeight: true }
    }
}
