import QtQuick
import Caelestia.Config
import qs.modules.common
import "."

// 移植自 caelestia-dots/shell（GPL-3.0）。
StyledText {
    property real fill
    property int grade: Appearance.m3colors.darkmode ? -25 : 0
    property font fontStyle: Tokens.font.icon.small

    font: Tokens.font.icon.size(fontStyle.pointSize).weight(fontStyle.weight).vaxes(fontStyle.variableAxes).fill(fill.toFixed(1)).grade(grade).build()
}
