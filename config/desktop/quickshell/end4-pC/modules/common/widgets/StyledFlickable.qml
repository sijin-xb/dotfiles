import QtQuick
import QtQuick.Controls
import qs.modules.common

/**
 * A Flickable with standard styling.
 * For inertial scroll: use ContentPage.qml (settings) or wrap in an Item
 * with a static WheelHandler + InertialScrollEngine pointing to this Flickable.
 */
Flickable {
    id: root
    maximumFlickVelocity: 3500
    boundsBehavior: Flickable.DragOverBounds

    ScrollBar.vertical: StyledScrollBar {}
}
