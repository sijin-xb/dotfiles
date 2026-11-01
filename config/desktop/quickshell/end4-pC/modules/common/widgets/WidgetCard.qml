import QtQuick
import qs.modules.common

Rectangle {
    id: root
    required property var widget
    property bool blurred: Config.options.background.widgets.blurWidgets
    property bool shadowed: Config.options.background.widgets.shadow
    property color tint: Appearance.colors.colLayer1
    property real tintOpacity: 0.55

    radius: Appearance.rounding?.verylarge ?? 30
    color: Appearance.colors.colPrimaryContainer

    StyledRectangularShadow {
        target: root
        z: -2
        visible: root.shadowed
    }

    FastBlurred {
        anchors.fill: parent
        anchors.margins: root.blurred ? -1 : 0
        blurSource: root.widget.wallpaperItem
        cardRadius: root.radius + (root.blurred ? 1 : 0)
        tint: root.tint
        tintOpacity: root.tintOpacity
        trackX: root.widget.x + root.x
        trackY: root.widget.y + root.y
        visible: root.blurred
    }
}
