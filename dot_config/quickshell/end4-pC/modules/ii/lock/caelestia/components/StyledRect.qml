import QtQuick

// 移植自 caelestia-dots/shell（GPL-3.0）。
Rectangle {
    id: root

    color: "transparent"

    Behavior on color {
        CAnim {}
    }
}
