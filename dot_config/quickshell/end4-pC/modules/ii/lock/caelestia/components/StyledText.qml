import QtQuick
import qs.modules.common

// 移植自 caelestia-dots/shell（GPL-3.0）。
// 字体改用 end4-pC 的 Appearance 系统，与 shell 其余部分统一。
Text {
    id: root

    property bool animate: false

    renderType: Text.NativeRendering
    textFormat: Text.PlainText
    color: Appearance.m3colors.m3onSurface
    font.family: Appearance.font.family.main
    font.pixelSize: Appearance.font.pixelSize.small
    font.hintingPreference: Font.PreferDefaultHinting
    verticalAlignment: Text.AlignVCenter

    Behavior on color {
        CAnim {}
    }
}
