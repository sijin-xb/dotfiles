pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.modules.common

// 移植自 caelestia-dots/shell（GPL-3.0）。
// 配色从 Caelestia 的 Colours.palette.m3* 改为 end4-pC 的 Appearance.m3colors.m3*（同名）。
Text {
    id: root

    property bool animate: false

    renderType: Text.NativeRendering
    textFormat: Text.PlainText
    color: Appearance.m3colors.m3onSurface
    font: Tokens.font.body.small

    Behavior on color {
        CAnim {}
    }

    Behavior on text {
        enabled: root.animate

        SequentialAnimation {
            Anim {
                target: root
                property: "opacity"
                to: 0
                type: Anim.FastEffects
            }
            PropertyAction {}
            Anim {
                target: root
                property: "opacity"
                to: 1
                type: Anim.DefaultEffects
            }
        }
    }
}
