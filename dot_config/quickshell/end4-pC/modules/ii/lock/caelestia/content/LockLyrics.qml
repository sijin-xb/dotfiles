pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.modules.common
import qs.services
import "../components"

// 歌词卡：直接复用 end4-pC 的 LyricsService（7 行窗口 + 逐字进度）。
// Caelestia 锁屏本身没有歌词，这是本仓库独有功能。
StyledRect {
    id: root

    required property var lock

    implicitHeight: layout.implicitHeight + layout.anchors.margins * 2
    radius: Tokens.rounding.extraLarge
    color: Appearance.m3colors.m3surfaceContainer

    readonly property var lines: LyricsService.slots
    readonly property int activeIdx: LyricsService.before

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Tokens.padding.extraLarge
        spacing: Tokens.spacing.small

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
                font: index === root.activeIdx
                    ? Tokens.font.body.medium
                    : Tokens.font.body.small
                opacity: modelData === "" ? 0 : (index === root.activeIdx ? 1 : 0.6)
                Behavior on opacity { Anim { type: Anim.DefaultEffects } }
                Behavior on color { CAnim {} }
            }
        }
    }
}
