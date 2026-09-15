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

    implicitHeight: 150
    radius: Appearance.rounding.large
    color: Appearance.m3colors.m3surfaceContainer

    readonly property var lines: LyricsService.slots
    readonly property int activeIdx: LyricsService.before

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 14
        spacing: 3

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
                font.weight: index === root.activeIdx ? Font.DemiBold : Font.Normal
                opacity: modelData === "" ? 0 : (index === root.activeIdx ? 1 : 0.55)
                Behavior on opacity { Anim { type: Anim.DefaultEffects } }
                Behavior on color { CAnim {} }
            }
        }
    }
}
