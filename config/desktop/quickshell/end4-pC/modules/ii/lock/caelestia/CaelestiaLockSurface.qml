pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Caelestia.Config
import qs.modules.common
import qs.services
import "components"
import "content"

// 移植自 caelestia-dots/shell（GPL-3.0）modules/lock/LockSurface.qml。
// 结构：模糊壁纸背景 + 居中方块（锁图标旋转）→ 展开成横条。
// 配色/字体/圆角：统一走 end4-pC 的 Appearance。
// 认证：复用 LockContext（PAM + 指纹 + keyring）。
Item {
    id: root

    required property var context       // LockContext

    // 本 Item 由 WlSessionLockSurface 的 Loader(anchors.fill) 拉伸至全屏，
    // root.height 就是屏幕高度。不要走 parent.screen 父链。
    readonly property real screenHeight: root.height > 0 ? root.height : 1080

    // 展开区域尺寸：屏高的 58%，16:9 比例。Caelestia 原版是 0.7，1080p 下偏大。
    readonly property real expandedHeight: Math.max(360, screenHeight * 0.58)
    readonly property real expandedWidth: expandedHeight * (16 / 9)

    readonly property alias unlocking: unlockAnim.running

    // 壁纸源：与 shell 其余部分一致
    readonly property string wallpaperSource:
        Wallpapers.previewPath || Wallpapers.confirmedPath || Config.options.background.wallpaperPath

    Connections {
        function onUnlocked(): void {
            unlockAnim.start();
        }
        target: root.context
    }

    // ── 解锁动画 ─────────────────────────────────────────────
    SequentialAnimation {
        id: unlockAnim
        ParallelAnimation {
            Anim {
                target: lockContent
                properties: "implicitWidth,implicitHeight"
                to: lockContent.size
            }
            Anim {
                target: lockBg
                property: "radius"
                to: lockContent.radius
            }
            Anim {
                target: content
                property: "scale"
                to: 0
            }
            Anim {
                target: content
                property: "opacity"
                to: 0
                type: Anim.StandardSmall
            }
            Anim {
                target: lockIcon
                property: "opacity"
                to: 1
                type: Anim.StandardLarge
            }
            Anim {
                target: background
                property: "opacity"
                to: 0
                type: Anim.StandardLarge
            }
            SequentialAnimation {
                PauseAnimation {
                    duration: Tokens.anim.durations.small
                }
                Anim {
                    type: Anim.Standard
                    target: lockContent
                    property: "opacity"
                    to: 0
                }
            }
        }
    }

    // ── 入场动画 ─────────────────────────────────────────────
    ParallelAnimation {
        id: initAnim
        running: true

        Anim {
            target: background
            property: "opacity"
            to: 1
            type: Anim.StandardLarge
        }
        SequentialAnimation {
            ParallelAnimation {
                Anim {
                    target: lockContent
                    property: "scale"
                    to: 1
                    type: Anim.FastSpatial
                }
                Anim {
                    target: lockContent
                    property: "rotation"
                    to: 360
                    duration: Tokens.anim.durations.expressiveFastSpatial
                    easing: Tokens.anim.standardAccel
                }
            }
            ParallelAnimation {
                Anim {
                    target: lockIcon
                    property: "rotation"
                    to: 360
                    easing: Tokens.anim.standardDecel
                }
                Anim {
                    type: Anim.DefaultEffects
                    target: lockIcon
                    property: "opacity"
                    to: 0
                }
                Anim {
                    type: Anim.DefaultEffects
                    target: content
                    property: "opacity"
                    to: 1
                }
                Anim {
                    target: content
                    property: "scale"
                    to: 1
                }
                Anim {
                    target: lockBg
                    property: "radius"
                    to: Appearance.rounding.verylarge
                }
                Anim {
                    target: lockContent
                    property: "implicitWidth"
                    to: root.expandedWidth
                }
                Anim {
                    target: lockContent
                    property: "implicitHeight"
                    to: root.expandedHeight
                }
            }
        }
    }

    // ── 模糊壁纸背景 ─────────────────────────────────────────
    Item {
        id: background
        anchors.fill: parent
        opacity: 0

        Image {
            anchors.fill: parent
            source: root.wallpaperSource
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize: Qt.size(width, height)

            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1
                blurMax: 64
                autoPaddingEnabled: false
            }
        }

        // 轻微压暗，提高文字可读性
        Rectangle {
            anchors.fill: parent
            color: Appearance.m3colors.m3scrim
            opacity: 0.28
        }
    }

    // ── 居中方块 → 展开 ──────────────────────────────────────
    Item {
        id: lockContent

        readonly property int size: 96
        readonly property int radius: size / 4

        anchors.centerIn: parent
        implicitWidth: size
        implicitHeight: size

        rotation: 180
        scale: 0

        StyledRect {
            id: lockBg
            anchors.fill: parent
            color: Appearance.m3colors.m3surfaceContainerLow
            radius: parent.radius
            opacity: 0.94

            border.width: 1
            border.color: Qt.alpha(Appearance.m3colors.m3outlineVariant, 0.35)

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                blurMax: 24
                shadowColor: Qt.alpha(Appearance.m3colors.m3shadow, 0.45)
                shadowVerticalOffset: 6
            }
        }

        StyledText {
            id: lockIcon
            anchors.centerIn: parent
            text: "lock"
            color: Appearance.m3colors.m3onSurface
            font.family: Appearance.font.family.iconMaterial
            font.pixelSize: 44
            font.weight: Font.Bold
            rotation: 180
        }

        Loader {
            id: content
            anchors.centerIn: parent
            width: Math.max(1, root.expandedWidth - 48)
            height: Math.max(1, root.expandedHeight - 48)

            opacity: 0
            scale: 0
            active: true
            sourceComponent: Content {
                lock: root.context
                screenHeight: root.screenHeight
            }
        }
    }
}
