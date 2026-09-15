import QtQuick
import qs.modules.common

// 移植自 caelestia-dots/shell（GPL-3.0）。
// 字号由调用方设 font.pixelSize；FILL/GRAD 通过 variableAxes 控制。
StyledText {
    id: root

    property real fill: 0
    property int grade: Appearance.m3colors.darkmode ? -25 : 0

    horizontalAlignment: Text.AlignHCenter
    font.family: Appearance.font.family.iconMaterial
    font.pixelSize: Appearance.font.pixelSize.large
    font.weight: Font.Medium
    font.variableAxes: ({
        "FILL": root.fill,
        "GRAD": root.grade,
        "opsz": root.font.pixelSize
    })
}
