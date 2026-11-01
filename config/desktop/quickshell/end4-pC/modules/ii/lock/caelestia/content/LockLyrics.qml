pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.services
import "../components"

// 歌词卡：复用 end4-pC 的 LyricsService（7 行窗口）。
StyledRect {
    id: root

    required property var lock

    implicitHeight: 160
    radius: Appearance.rounding.large
    color: Appearance.m3colors.m3surfaceContainer

    border.width: 1
    border.color: Qt.alpha(Appearance.m3colors.m3outlineVariant, 0.35)

    readonly property var lines: LyricsService.slots
    readonly property int activeIdx: LyricsService.before
    readonly property bool hasLyrics: lines && lines.some(l => l && l.trim() !== "")

    // 空状态提示
    Column {
        anchors.centerIn: parent
        spacing: 6
        visible: !root.hasLyrics

        MaterialIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "lyrics"
            color: Appearance.m3colors.m3onSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.large
            opacity: 0.45
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Translation.tr("No lyrics available")
            color: Appearance.m3colors.m3onSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.smallie
            opacity: 0.55
        }
    }

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 14
        spacing: 2
        visible: root.hasLyrics

        Item { Layout.fillHeight: true }

        Repeater {
            model: root.lines

            StyledText {
                required property string modelData
                required property int index

                Layout.fillWidth: true
                text: modelData
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                animate: true
                color: index === root.activeIdx
                    ? Appearance.m3colors.m3primary
                    : Appearance.m3colors.m3onSurfaceVariant
                font.pixelSize: index === root.activeIdx
                    ? Appearance.font.pixelSize.small
                    : Appearance.font.pixelSize.smallie
                font.weight: index === root.activeIdx ? Font.Bold : Font.Normal
                opacity: modelData === "" ? 0 : (index === root.activeIdx ? 1 : 0.45)
                Behavior on opacity { Anim { type: Anim.DefaultEffects } }
                Behavior on color { CAnim {} }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
