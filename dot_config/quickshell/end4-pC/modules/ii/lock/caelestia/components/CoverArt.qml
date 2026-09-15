pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import M3Shapes
import Caelestia.Config
import qs.modules.common
import "."

// 移植自 caelestia-dots/shell（GPL-3.0）。
// Players.active -> MprisController.activePlayer；Colours.palette.* -> Appearance.m3colors.*。
// artUrl 由调用方通过 artSource 传入，避免与 end4-pC 的 MPRIS 服务耦合。
Item {
    id: root

    readonly property alias shape: shape

    property bool hadPrevious
    property string artSource: ""
    property bool isPlaying: false
    property color fallbackColour: Appearance.m3colors.m3surfaceContainerHighest

    // 轻微外发光，与背景分离
    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        blurMax: 1
        shadowColor: Appearance.m3colors.m3outline
        shadowOpacity: 0.3
    }

    Behavior on fallbackColour {
        CAnim {}
    }

    Item {
        id: shapeWrapper

        anchors.fill: parent
        layer.enabled: true
        opacity: root.fallbackColour.a

        MaterialShape {
            id: shape

            implicitSize: root.width
            shape: MaterialShape.Cookie12Sided
            color: Qt.alpha(root.fallbackColour, 1)

            Anim on rotation {
                running: true
                paused: !root.isPlaying
                from: 360
                to: 0
                duration: 23500
                easing.type: Easing.Linear
                loops: Animation.Infinite
            }
        }
    }

    MaterialIcon {
        anchors.centerIn: parent

        grade: 200
        text: image.status === Image.Error ? "broken_image" : "art_track"
        color: Appearance.m3colors.m3onSurfaceVariant
        fontStyle: Tokens.font.icon.size((parent.width * 0.35) || 1).build()
        opacity: image.status === Image.Null || image.status === Image.Error ? 1 : 0
        animate: true

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Loader {
        anchors.centerIn: parent
        asynchronous: true
        active: opacity > 0
        opacity: image.status === Image.Loading ? 1 : 0

        sourceComponent: LoadingIndicator {
            implicitSize: root.width * 0.3
            color: Appearance.m3colors.m3primaryContainer
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    FadeImage {
        id: image

        anchors.fill: parent
        source: root.artSource

        layer.enabled: true
        layer.effect: Mask {
            maskSource: shapeWrapper
        }
    }
}
