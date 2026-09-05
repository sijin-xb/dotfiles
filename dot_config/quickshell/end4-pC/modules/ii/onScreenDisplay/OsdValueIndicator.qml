import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

// Material You style dial: value arc around a centered icon, percentage
// below. Replaces the old horizontal pill; keeps the same interface
// (value/icon/name/rotateIcon/scaleIcon + from/to).
Item {
    id: root
    required property real value
    required property string icon
    required property string name
    property bool rotateIcon: false
    property bool scaleIcon: false
    property real from: 0
    property real to: 1
    readonly property real normalizedValue: Math.max(0, Math.min(1, (value - from) / ((to - from) || 1)))

    readonly property real dialSize: 150
    readonly property real ringStroke: 12

    implicitWidth: dialSize + 4 * Appearance.sizes.elevationMargin
    implicitHeight: dialSize + 4 * Appearance.sizes.elevationMargin

    // Translucent backdrop so the ring reads over any wallpaper
    Rectangle {
        anchors.centerIn: parent
        width: root.dialSize
        height: root.dialSize
        radius: width / 2
        color: Appearance.colors.colLayer0
        opacity: 0.92
    }

    Shape {
        id: ring
        anchors.centerIn: parent
        width: root.dialSize - 24
        height: root.dialSize - 24
        readonly property real cx: width / 2
        readonly property real cy: height / 2
        readonly property real r: width / 2 - root.ringStroke / 2

        ShapePath {
            // Track: full circle (two arcs)
            fillColor: "transparent"
            strokeColor: Appearance.colors.colSecondaryContainer
            strokeWidth: root.ringStroke
            capStyle: ShapePath.RoundCap
            PathSvg {
                path: `M ${ring.cx + ring.r} ${ring.cy} A ${ring.r} ${ring.r} 0 1 1 ${ring.cx - ring.r} ${ring.cy} A ${ring.r} ${ring.r} 0 1 1 ${ring.cx + ring.r} ${ring.cy}`
            }
        }
        ShapePath {
            // Value arc: clockwise from 12 o'clock
            fillColor: "transparent"
            strokeColor: Appearance.colors.colPrimary
            strokeWidth: root.ringStroke
            capStyle: ShapePath.RoundCap
            PathSvg {
                path: {
                    const frac = root.normalizedValue;
                    if (frac <= 0.001) return "";
                    if (frac >= 0.999)
                        return `M ${ring.cx + ring.r} ${ring.cy} A ${ring.r} ${ring.r} 0 1 1 ${ring.cx - ring.r} ${ring.cy} A ${ring.r} ${ring.r} 0 1 1 ${ring.cx + ring.r} ${ring.cy}`;
                    const angle = frac * 2 * Math.PI;
                    const endX = ring.cx + ring.r * Math.sin(angle);
                    const endY = ring.cy - ring.r * Math.cos(angle);
                    const largeArc = frac > 0.5 ? 1 : 0;
                    return `M ${ring.cx} ${ring.cy - ring.r} A ${ring.r} ${ring.r} 0 ${largeArc} 1 ${endX} ${endY}`;
                }
            }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 2

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: root.icon
            iconSize: 34
            color: Appearance.colors.colOnSurface
            rotation: 180 * (root.rotateIcon ? root.normalizedValue : 0)
            scale: root.scaleIcon ? 0.7 + 0.3 * root.normalizedValue : 1

            Behavior on rotation {
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
            }
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: `${Math.round(root.normalizedValue * 100)}%`
            font.pixelSize: Appearance.font.pixelSize.small
            font.features: { "tnum": 1 }
            color: Appearance.colors.colOnSurfaceVariant
        }
    }
}
