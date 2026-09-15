import QtQuick
import Quickshell.Widgets

// 移植自 caelestia-dots/shell（GPL-3.0）。
ClippingRectangle {
    id: root

    color: "transparent"

    Behavior on color {
        CAnim {}
    }
}
