import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls

/**
 * A ListView with animations.
 */
ListView {
    id: root
    spacing: 5
    property real removeOvershoot: 20 // Account for gaps and bouncy animations
    property int dragIndex: -1
    property real dragDistance: 0
    property bool popin: true
    property bool animateAppearance: true
    property bool animateMovement: false


    // Legacy properties kept for backward compatibility:
    // Anime.qml and AiChat.qml override these to get 1.4x faster scroll.
    // They are passed into InertialScrollEngine via scrollEngine.touchpadSensitivity
    // and scrollEngine.wheelScrollAmount bindings below.
    property real touchpadScrollFactor: Config?.options.interactions.scrolling.touchpadScrollFactor ?? 1.0
    property real mouseScrollFactor: Config?.options.interactions.scrolling.mouseScrollFactor ?? 1.0
    property real mouseScrollDeltaThreshold: Config?.options.interactions.scrolling.mouseScrollDeltaThreshold ?? 120

    function resetDrag() {
        root.dragIndex = -1
        root.dragDistance = 0
    }

    maximumFlickVelocity: 3500
    boundsBehavior: Flickable.DragOverBounds

    ScrollBar.vertical: StyledScrollBar {}

    // Physics engine (child of this ListView)
    property var _engine: null
    // WheelHandler dynamically installed on parent (ancestor of this ListView).
    // Ancestor WheelHandlers fire BEFORE ListView's C++ wheelEvent in Qt 6.
    property var _parentHandler: null

    Component {
        id: _engineComp
        InertialScrollEngine {
            flickable: root
            touchpadSensitivity: (Config?.options.interactions.scrolling.touchpadSensitivity ?? 3.5)
                                 * root.touchpadScrollFactor
            wheelScrollAmount: Math.round(
                (Config?.options.interactions.scrolling.wheelScrollAmount ?? 100)
                * root.mouseScrollFactor)
            mouseScrollDeltaThreshold: root.mouseScrollDeltaThreshold
        }
    }

    Component.onCompleted: {
        _engine = _engineComp.createObject(root)
        if (parent) _attachHandler(parent)
    }

    onParentChanged: {
        if (_parentHandler) { _parentHandler.destroy(); _parentHandler = null }
        if (parent && _engine) _attachHandler(parent)
    }

    Component.onDestruction: {
        if (_parentHandler) { _parentHandler.destroy(); _parentHandler = null }
    }

    function _attachHandler(parentItem) {
        _parentHandler = Qt.createQmlObject(
            'import QtQuick; WheelHandler { target: null; acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad }',
            parentItem
        )
        var eng = _engine
        var flick = root
        _parentHandler.wheel.connect(function(event) {
            if (event.x >= flick.x && event.x < flick.x + flick.width &&
                event.y >= flick.y && event.y < flick.y + flick.height) {
                console.log("[SLV] wheel over listview: " + event.angleDelta.y)
                eng.handleWheel(event)
            }
        })
    }

    add: Transition {
        animations: animateAppearance ? [
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                properties: popin ? "opacity,scale" : "opacity",
                from: 0,
                to: 1,
            }),
        ] : []
    }

    addDisplaced: Transition {
        animations: animateAppearance ? [
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                property: "y",
            }),
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                properties: popin ? "opacity,scale" : "opacity",
                to: 1,
            }),
        ] : []
    }
    
    displaced: Transition {
        animations: root.animateMovement ? [
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                property: "y",
            }),
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                properties: "opacity,scale",
                to: 1,
            }),
        ] : []
    }

    move: Transition {
        animations: root.animateMovement ? [
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                property: "y",
            }),
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                properties: "opacity,scale",
                to: 1,
            }),
        ] : []
    }
    moveDisplaced: Transition {
        animations: root.animateMovement ? [
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                property: "y",
            }),
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                properties: "opacity,scale",
                to: 1,
            }),
        ] : []
    }

    remove: Transition {
        animations: animateAppearance ? [
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                property: "x",
                to: root.width + root.removeOvershoot,
            }),
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                property: "opacity",
                to: 0,
            })
        ] : []
    }

    // This is movement when something is removed, not removing animation!
    removeDisplaced: Transition { 
        animations: animateAppearance ? [
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                property: "y",
            }),
            Appearance?.animation.elementMove.numberAnimation.createObject(this, {
                properties: "opacity,scale",
                to: 1,
            }),
        ] : []
    }
}
