import QtQuick
import QtQuick.Effects
import "."

// 移植自 caelestia-dots/shell（GPL-3.0）。
MultiEffect {
    property color sourceColor: "black"

    colorization: 1
    brightness: 1 - sourceColor.hslLightness

    Behavior on colorizationColor {
        CAnim {}
    }
}
